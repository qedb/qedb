-- Copyright (c) 2017, Herman Bergwerf. All rights reserved.
-- Use of this source code is governed by an AGPL-3.0-style license
-- that can be found in the LICENSE file.

CREATE EXTENSION plperl;

-- To test:
--
-- SELECT * FROM rule WHERE match_subs(
--   ARRAY[5, 4, 1, 2, 6, 7, 2, 9, 3, 1, 1],
--   ARRAY[6, 4, 1, 2, 6, 3, 1, 1, 7, 2, 9],
--   left_array_data, right_array_data, ARRAY[1, 2, 3]);

CREATE FUNCTION match_subs(
  integer[], -- expr left
  integer[], -- expr right
  integer[], -- rule left
  integer[], -- rule right
  integer[]) -- computable ids
RETURNS boolean AS $BODY$

my $expr_hash_mix = sub {
  my ($hash, $value) = @_;
  $hash = 0x1fffffff & ($hash + $value);
  $hash = 0x1fffffff & ($hash + ((0x0007ffff & $hash) << 10));
  $hash = $hash ^ ($hash >> 6);
  return $hash;
};

my $expr_hash_postprocess = sub {
  my ($hash) = @_;
  $hash = 0x1fffffff & ($hash + ((0x03ffffff & $hash) << 3));
  $hash = $hash ^ ($hash >> 11);
  return 0x1fffffff & ($hash + ((0x00003fff & $hash) << 15));
};

my $EXPR_INTEGER       = 1;
my $EXPR_SYMBOL        = 2;
my $EXPR_SYMBOL_GEN    = 3;
my $EXPR_FUNCTION      = 4;
my $EXPR_FUNCTION_GEN  = 5;

# Compute hash for the given part of the expression data array. Replacing all
# hashes that are in the mapping with the mapped hashes.
my $compute_mapped_hash;
$compute_mapped_hash = sub {
  my ($ptr, $mapping_hash, $data) = @_;

  my $hash = $data->[$ptr++];
  my $type = $data->[$ptr++];
  my $value = $data->[$ptr++];

  if (exists $$mapping_hash{$hash}) {
    return ($$mapping_hash{$hash}, $ptr);
  } elsif ($type == $EXPR_FUNCTION || $type == $EXPR_FUNCTION_GEN) {
    # Hash all arguments together.
    my $argc = $data->[$ptr];
    $ptr += 2;

    $hash = 0;
    $hash = $expr_hash_mix->($hash, $type);
    $hash = $expr_hash_mix->($hash, $value);

    while ($argc > 0) {
      $argc--;
      (my $arg_hash, $ptr) = $compute_mapped_hash->($ptr, $mapping_hash, $data);
      $hash = $expr_hash_mix->($hash, $arg_hash);
    }

    $hash = $expr_hash_postprocess->($hash);
    $hash = ($hash << 1) & 0x3fffffff;
    return ($hash, $ptr);
  } else {
    return ($hash, $ptr);
  }
};

# Evaluate function using the given mapping.
my $evaluate = sub {
  my ($ptr, $mapping_hash, $computable_ids, $data) = @_;
  my ($id_add, $id_sub, $id_mul, $id_neg) = @$computable_ids;

  # The stack consists of alternating values: (function ID, 0) or (integer, 1).
  my @stack;

  while (1) {
    my $hash = $data->[$ptr++];
    my $type = $data->[$ptr++];
    my $value = $data->[$ptr++];

    if ($type == $EXPR_SYMBOL_GEN || $type == $EXPR_INTEGER) {
      my $argument = $value; # Valid for $type == $EXPR_INTEGER.

      if ($type == $EXPR_SYMBOL_GEN) {
        if (exists $$mapping_hash{$hash}) {
          my $target = $$mapping_hash{$hash};

          # Reconstruct integer value.
          if ($target & 0x1 == 1) {
            $argument = $target >> 2;
            if (($target >> 1) & 0x1 == 1) {
              $argument = -$argument;
            }
          } else {
            # If the generic does not point to an integer, terminate.
            return (undef, $ptr);
          }
        } else {
          return (undef, $ptr);
        }
      }

      # We use the usefull fact that all computable functions have exactly
      # two arguments.
      # We can assume there are elements in the stack at this point since
      # this function is called with the pointer pointing to a function
      # first.
      if ($stack[-1] == 1) {
        # Collapse stack.
        do {
          pop @stack;                    # Remove first argument flag [1].
          my $other = pop @stack;        # Get other integer.
          pop @stack;                    # Remove computation flag [0].
          my $computation = pop @stack;  # Get computation ID.

          # Do computation.
          if ($computation == $id_add)    { $argument = $other + $argument; }
          elsif ($computation == $id_sub) { $argument = $other - $argument; }
          elsif ($computation == $id_mul) { $argument = $other * $argument; }
          elsif ($computation == $id_neg) { $argument = -$argument; }

        } while (@stack && $stack[-1] == 1);

        # If the stack is empty, return the result.
        if (!@stack) {
          return ($argument, $ptr);
        } else {
          push @stack, $argument, 1;
        }
      } else {
        # This is the first argument of the lowest computation in the stack.
        push @stack, $argument, 1;
      }
    } elsif ($type == $EXPR_FUNCTION) {
      if ($value == $id_add || $value == $id_sub ||
          $value == $id_mul || $value == $id_neg) {
        # Push function ID to stack.
        push @stack, $value, 0;

        # Skip argument count and content-length (we know the argument length of
        # all computable functions ahead of time).
        $ptr += 2;

        # If this is the negation function, add a first argument here as an
        # imposter. This way the negation function can be integrated in the same
        # code as the binary operators.
        if ($value == $id_neg) {
          push @stack, 0, 1;
        }
      } else {
        return (undef, $ptr);
      }
    } else {
      return (undef, $ptr);
    }
  }

  # This point will not be reached.
};

my $get_genfn_params = sub {
  my ($ptrs, $mapping_hash, $data) = @_;

  if ((scalar $ptrs) == 3) {
    return $ptrs;
  }

  my $mptr_t = $$ptrs[0];
  my $mptr_p = $$ptrs[1];

  # Get hash of first argument of pattern function.
  # This first argument should be generic.
  my $pattern_arg_hash = $$data[$mptr_p + 5];
  push @$ptrs, $pattern_arg_hash;

  # If no target hash exists and the expression function has 1 argument, the
  # generic is mapped to that argument.
  if (!exists $$mapping_hash{$pattern_arg_hash}) {
    if ($$data[$mptr_t + 3] == 1) {
      # Map pattern argument to hash of first expression argument.
      my $hash = $$data[$mptr_t + 5];
      $$mapping_hash{$pattern_arg_hash} = $hash;
    } else {
      # Argument count not 1, and no target hash exists. So terminate.
      return 0;
    }
  }

  return $ptrs;
};

# Recursive expression pattern matching.
my $match_pattern;
$match_pattern = sub {
  my ($internal_remap, $mapping_hash, $mapping_genfn,
      $ptr_t, $ptr_p, $computable_ids, @data) = @_;

  my $argc = 1; # arguments left to be processed.

  # Iterate through data untill out of arguments.
  # Returns success if loop completes. If a mismatch is found the function
  # should be terminated directly.
  while ($argc > 0) {
    $argc--;

    my $hash_t = $data[$ptr_t++];
    my $hash_p = $data[$ptr_p++];
    my $type_t = $data[$ptr_t++];
    my $type_p = $data[$ptr_p++];
    my $value_t = $data[$ptr_t++];
    my $value_p = $data[$ptr_p++];

    if ($type_p == $EXPR_SYMBOL_GEN) {
      # If the symbol is already mapped to an expression hash, check if the
      # target hash matches this hash in the current position. Else store the
      # target hash.
      if (exists $$mapping_hash{$hash_p}) {
        if ($$mapping_hash{$hash_p} != $hash_t) {
          return 0;
        }
      } else {
        $$mapping_hash{$hash_p} = $hash_t;
      }

      # Jump over function body.
      if ($type_t == $EXPR_FUNCTION || $type_t == $EXPR_FUNCTION_GEN) {
        $ptr_t += 2 + $data[$ptr_t + 1];
      }
    } elsif ($type_p == $EXPR_FUNCTION_GEN) {
      if (exists $$mapping_genfn{$value_p}) {
        # Internal remapping.
        if ($internal_remap) {
          # Disallow generic functions in internal remapping.
          return 0;
        }

        # Retrieve pointers.
        my $ptrs = $get_genfn_params->(
          $$mapping_genfn{$value_p}, $mapping_hash, \@data);
        if ($ptrs == 0) {
          return 0;
        }

        my $mptr_t = $$ptrs[0];
        my $pattern_arg_hash = $$ptrs[2];
        my $pattern_arg_target_hash = $$mapping_hash{$pattern_arg_hash};

        # Compute hash for internal substitution.
        # Overhead of running this when there is no difference is minimal.
        my @result = $compute_mapped_hash->($ptr_p + 2, $mapping_hash, \@data);
        my $computed_hash = $result[0];

        # Deep compare if the computed hash is different.
        if ($computed_hash != $pattern_arg_target_hash) {
          # Temporarily add hash to mapping.
          my $old_hash = $$mapping_hash{$pattern_arg_target_hash};
          $$mapping_hash{$pattern_arg_target_hash} = $computed_hash;

          # Old expression is used as pattern, current expression as target.
          if (!$match_pattern->(1, $mapping_hash, $mapping_genfn,
              $ptr_t - 3, $mptr_t, $computable_ids, @data)) {
            return 0;
          }

          # Restore old mapping.
          $$mapping_hash{$pattern_arg_target_hash} = $old_hash;
        } else {
          # Shallow compare.
          if ($$mapping_hash{$hash_p} != $hash_t) {
            return 0;
          }
        }
      } else {
        $$mapping_hash{$hash_p} = $hash_t;

        # Add expression pointer to mapping for later use.
        # Both pointers point at the start of the expression.
        $$mapping_genfn{$value_p} = [$ptr_t - 3, $ptr_p - 3];
      }

      # Jump over function body. Generic functions operating on generic
      # functions are actually bullshit, but we handle them anyway.
      if ($type_t == $EXPR_FUNCTION || $type_t == $EXPR_FUNCTION_GEN) {
        $ptr_t += 2 + $data[$ptr_t + 1];
      }
      $ptr_p += 2 + $data[$ptr_p + 1];
    } elsif ($type_p == $EXPR_SYMBOL) {
      # During internal remapping a symbol may be mapped to a customly computed
      # hash.
      if ($internal_remap && exists $$mapping_hash{$hash_p}) {
        if ($$mapping_hash{$hash_p} != $hash_t) {
          return 0;
        } else {
          # The symbol is in the mapping and matches the given hash. It is
          # possible that the target is a function so now we need to jump over
          # its function body.
          if ($type_t == $EXPR_FUNCTION || $type_t == $EXPR_FUNCTION_GEN) {
            $ptr_t += 2 + $data[$ptr_t + 1];
          }
        }
      } else {
        if ($type_t != $EXPR_SYMBOL || $value_t != $value_p) {
          return 0;
        }
      }
    } elsif ($type_p == $EXPR_FUNCTION) {  
      if ($type_t == $EXPR_FUNCTION) {
        if ($value_t == $value_p) {
          my $argc_t = $data[$ptr_t++];
          my $argc_p = $data[$ptr_p++];

          # Both functions must have the same number of arguments.
          if ($argc_t == $argc_p) {
            # Skip content-length.
            $ptr_t++;
            $ptr_p++;

            # Add argument count to the total.
            $argc += $argc_p;
          } else {
            # Different number of arguments.
            return 0;
          }
        } else {
          # Function IDs do not match.
          return 0;
        }
      } elsif (!$internal_remap && $type_t == $EXPR_INTEGER) {
        # Note: we do not run this during internal remapping to avoid
        # complicated cases with difficult behavior.

        # Check if pattern function can be evaluated to the same integer as the
        # target expression.
        my ($evaluated_value, $ptr_t) = $evaluate->($ptr_p - 3, $mapping_hash,
            $computable_ids, \@data);

        if ((!defined $evaluated_value) || $value_t != $evaluated_value) {
          return 0;
        } else {
          # Jump over function body.
          $ptr_p += 2 + $data[$ptr_p + 1];
        }
      } else {
        # Expression is not also a function or an integer.
        return 0;
      }
    } elsif ($type_p == $EXPR_INTEGER) {
      # Integers are not very common in patterns. Therefore this is checked
      # last.
      if ($type_t != $EXPR_INTEGER || $value_t != $value_p) {
        return 0;
      }
    } else {
      # Unknown expression type.
      return 0;
    }
  }

  # Also return pointer value.
  return (1, $ptr_t, $ptr_p);
};

# Substitution matching
# It is possible to put match_pattern inside this function for some very minimal
# gain (arguments do not have to be copied).
my $match_subs = sub {
  my ($expr_left, $expr_right, $subs_left, $subs_right, $computable_ids) = @_;
  my (%mapping_hash, %mapping_genfn);
  my $ptr_t = 0;
  my $ptr_p = (scalar @$expr_left) + (scalar @$expr_right);
  my @data = (@$expr_left, @$expr_right, @$subs_left, @$subs_right);

  (my $result_left, $ptr_t, $ptr_p) = $match_pattern->(0,
      \%mapping_hash, \%mapping_genfn, $ptr_t, $ptr_p, $computable_ids, @data);
  if (!$result_left) {
    return 0;
  }

  my ($result_right) = $match_pattern->(0, \%mapping_hash, \%mapping_genfn,
      $ptr_t, $ptr_p, $computable_ids, @data);
  return $result_right;
};

return $match_subs->(@_);
$BODY$
  LANGUAGE plperl;
