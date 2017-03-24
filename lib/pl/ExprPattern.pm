# Copyright (c) 2017, Herman Bergwerf. All rights reserved.
# Use of this source code is governed by an AGPL-3.0-style license
# that can be found in the LICENSE file.

package ExprPattern;
require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(expr_match_pattern expr_match_rule);

use strict;
use warnings;

# Simple logging.
# We avoid Log::Message::Simple to reduce dependencies.
my $debug_print = 0;
sub debug {
  if ($debug_print) {
    print 'LOG: ', @_;
  }
}

my $EXPR_INTEGER       = 1;
my $EXPR_SYMBOL        = 2;
my $EXPR_SYMBOL_GEN    = 3;
my $EXPR_FUNCTION      = 4;
my $EXPR_FUNCTION_GEN  = 5;

# Recursive expression pattern matching.
# TODO: store final index pointer values back into references.
sub match_pattern {
  my ($write_mapping, $mapping_hash, $mapping_ptrs,
    $ptr_e, $ptr_p, @data) = @_;
    
  my $argc = 1; # arguments left to be processed.

  # Iterate through data untill out of arguments.
  # Returns success if loop completes. If a mismatch is found the function
  # should be terminated directly.
  while ($argc > 0) {
    $argc--;
    
    my $hash_e = $data[$ptr_e++];
    my $hash_p = $data[$ptr_p++];
    my $type_e = $data[$ptr_e++];
    my $type_p = $data[$ptr_p++];
    my $value_e = $data[$ptr_e++];
    my $value_p = $data[$ptr_p++];
  
    if ($type_p == $EXPR_SYMBOL_GEN || $type_p == $EXPR_FUNCTION_GEN) {  
      # Store expression hash in generic mapping.
      if (!$write_mapping) {
        if ($$mapping_hash{$value_p} != $hash_e) {
          return 0;
        }

        # Run internal remapping.
        if ($type_p == $EXPR_FUNCTION_GEN) {
          my $ptrs = $$mapping_ptrs{$value_p};
          my $mptr_e = $$ptrs[0];
          my $mptr_p = $$ptrs[1];

          # Assume strict mode is used, meaning that the source pattern only has
          # a single argument. This code does not enforce that this argument maps
          # to a syol (instead it can be any expression). This is done in eqlib
          # to isolate the cases where internal remapping is allowed.
          my $srcsym_id = $data[$mptr_p + 2];
          my $dstsym_hash = $$mapping_hash{$srcsym_id};
          
          # If the argument symbol is not mapped yet, we will map it to the
          # expression function first argument (only if it has 1 argument!).
          # if (!$dstsym_hash) {
          #   if () {

          #   } else {
          #     return 0;
          #   }
          # }

          $$mapping_hash{$srcsym_id} = $dstsym_hash;

          if (!match_pattern(0, $mapping_hash, $mapping_ptrs,
              $mptr_e, $mptr_p, @data)) {
            return 0;
          }
        }
      } elsif (exists $$mapping_hash{$value_p}) {
        if ($$mapping_hash{$value_p} != $hash_e) {
          return 0;
        }
      } else {
        $$mapping_hash{$value_p} = $hash_e;

        # Also store pointer mapping for generic functions (to process internal
        # remapping later).
        if ($type_p == $EXPR_FUNCTION_GEN) {
          # expr ptr starts at expression, pattern ptr starts at first argument.
          $$mapping_ptrs{$value_p} = [$ptr_e - 3, $ptr_p + 2];
        }
      }
      
      # Jump over function body.
      if ($type_e == $EXPR_FUNCTION || $type_e == $EXPR_FUNCTION_GEN) {
        $ptr_e += 2 + $data[$ptr_e + 1];
      }
      if ($type_p == $EXPR_FUNCTION_GEN) {
        $ptr_p += 2 + $data[$ptr_p + 1];
      }
    } elsif ($type_p == $EXPR_INTEGER || $type_p == $EXPR_SYMBOL) {
      # There is no need to skip the function content of the expression. If it
      # is a function the pattern is not matching anymore.
      if (!($type_e == $type_p && $value_e == $value_p)) {
        return 0;
      }
    } elsif ($type_p == $EXPR_FUNCTION) {
      debug "pattern is function #$value_p\n";
  
      if ($type_e == $EXPR_FUNCTION && $value_e == $value_p) {
        my $argc_e = $data[$ptr_e++];
        my $argc_p = $data[$ptr_p++];
  
        debug "matching function, argument count: $argc_e, $argc_p\n";
  
        # Both functions must have the same number of arguments.
        if ($argc_e == $argc_p) {
          # Skip content-length.
          $ptr_e++;
          $ptr_p++;
        
          # Add argument count to the total.
          $argc += $argc_p;
        } else {
          # Different number of arguments.
          return 0;
        }
      } else {
        # Pattern is a function but expression is not.
        return 0;
      }
    } else {
      # Unknown expression type.
      return 0;
    }
  }

  # Also return pointer value.
  return (1, $ptr_e, $ptr_p);
}

# Initialization for match_pattern.
sub expr_match_pattern {
  my ($expression, $pattern) = @_;
  my (%mapping_hash, %mapping_ptrs);
  my $ptr_e = 0;
  my $ptr_p = scalar(@$expression);
  
  debug 'expression: ', join(', ', @$expression), "\n";
  debug 'pattern: ', join(', ', @$pattern), "\n";
  
  my $result = match_pattern(
    1, \%mapping_hash, \%mapping_ptrs, $ptr_e, $ptr_p, @$expression, @$pattern);
  return !($result == 0);
}

# Rule matching
sub expr_match_rule {
  my ($expr_left, $expr_right, $rule_left, $rule_right) = @_;
  my (%mapping_hash, %mapping_ptrs);
  my $ptr_e = 0;
  my $ptr_p = scalar(@$expr_left) + scalar(@$expr_right);
  my @data = (@$expr_left, @$expr_right, @$rule_left, @$rule_right);
  
  (my $result_left, $ptr_e, $ptr_p) = match_pattern(
    1, \%mapping_hash, \%mapping_ptrs, $ptr_e, $ptr_p, @data);
  if (!$result_left) {
    return 0;
  }
  
  my $result_right = match_pattern(
    0, \%mapping_hash, \%mapping_ptrs, $ptr_e, $ptr_p, @data);
  return !($result_right == 0);
}

# Succesfully load module.
return 1;
