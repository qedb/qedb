# Copyright (c) 2017, Herman Bergwerf. All rights reserved.
# Use of this source code is governed by an AGPL-3.0-style license
# that can be found in the LICENSE file.

# Utilities to build expression data using Perl syntax.
package ExprBuilder;
require Exporter;
@ISA        = qw(Exporter);
@EXPORT_OK  = qw(expr_number expr_symbols expr_function expr_generic_function format_expression);

use strict;
use warnings;

use ExprUtils qw(expr_hash_mix expr_hash_postprocess expr_hash expr_hash_str);

# Operators for expression arrays (which are blessed with this 'class').
{
  package ExprOperators;
  
  # Arrange arguments according to operator direction.
  sub _arrange_args {
    my ($arg1, $arg2, $swap) = @_;
    return $swap ? ($arg2, $arg1) : ($arg1, $arg2);
  }
  
  use overload
    '+' => sub { ExprBuilder::expr_function('+', _arrange_args(@_)); },
    '-' => sub { ExprBuilder::expr_function('-', _arrange_args(@_)); },
    '*' => sub { ExprBuilder::expr_function('*', _arrange_args(@_)); },
    '/' => sub { ExprBuilder::expr_function('/', _arrange_args(@_)); },
    '^' => sub { ExprBuilder::expr_function('^', _arrange_args(@_)); },
    '>>' => sub {
      my ($arg1, $arg2, $swap) = @_;
      return $swap ? [$arg2, $arg1] : [$arg1, $arg2];
    };
}

my $EXPR_INTEGER       = 1;
my $EXPR_SYMBOL        = 2;
my $EXPR_SYMBOL_GEN    = 3;
my $EXPR_FUNCTION      = 4;
my $EXPR_FUNCTION_GEN  = 5;
my %formatting_data;
  
# Build expression from data array (add hash and bless).
sub _build_expr {
  my @array = @_;
  unshift(@array, expr_hash(@array));
  my $ref = \@array;
  bless($ref, 'ExprOperators');
  return $ref;
}

# Build function from argument array.
sub _build_function {
  my ($type, $str, @args) = @_;
  my $id = expr_hash_str($str);
  $formatting_data{$id} = $str;
  my @data = (0, $type, $id, 0, 0);
  my $hash = 0;
  $hash = expr_hash_mix($hash, $type);
  $hash = expr_hash_mix($hash, $id);

  foreach my $arg (@args) {
    $data[3]++;
    if (ref($arg) eq 'ExprOperators') {
      push(@data, @$arg);
      $hash = expr_hash_mix($hash, $arg->[0]);
    } else {
      my $numdata = expr_number($arg);
      push @data, @$numdata;
      $hash = expr_hash_mix($hash, $numdata->[0]);
    }
  }

  $data[4] = scalar(@data) - 5;
  $data[0] = expr_hash_postprocess($hash);

  my $ref = \@data;
  bless($ref, 'ExprOperators');
  return $ref;
}

# Build symbol.
sub _build_symbol {
  my ($type, $str) = @_;
  my $id = expr_hash_str($str);
  $formatting_data{$id} = $str;
  return _build_expr($type, $id);
}

sub expr_number { _build_expr($EXPR_INTEGER, @_); }
sub expr_symbol { _build_symbol($EXPR_SYMBOL, @_); }
sub expr_generic_symbol { _build_symbol($EXPR_SYMBOL_GEN, @_); }
sub expr_function { _build_function($EXPR_FUNCTION, @_); }
sub expr_generic_function { _build_function($EXPR_FUNCTION_GEN, @_); }

# Build symbol from provided string. Symbol will be generic if the string starts
# with a question mark. 
sub _auto_symbol {
  my $str = $_;
  if (substr($str, 0, 1) eq '?') {
    return expr_generic_symbol(substr($str, 1));
  } else {
    return expr_symbol($str);
  }
}

# Build array of symbols from the provided string with comma separated symbol
# labels.
sub expr_symbols {
  my ($str) = @_;
  my @strs = split(/,\s/, $str);
  return map(_auto_symbol, @strs);
}

# Format expression data as string using %formatting_data.
sub format_expression {
  my ($data, $indent, $ptr, $indent_lvl) = @_;

  # Default arguments.
  if (!defined($indent)) { $indent = 0; }
  if (!defined($ptr)) { my $ptr_v = 0; $ptr = \$ptr_v; }
  if (!defined($indent_lvl)) { $indent_lvl = 0; }

  my $hash = $data->[$$ptr++];
  my $type = $data->[$$ptr++];
  my $value = $data->[$$ptr++];
  my $indent_str = $indent ? "\n" . (' ' x ($indent_lvl * 2)) : '';

  if ($type == $EXPR_FUNCTION || $type == $EXPR_FUNCTION_GEN) {
    my $argc = $data->[$$ptr];
    $$ptr += 2;
    my @args;

    while ($argc > 0) {
      $argc--;
      push(@args, format_expression($data, $indent, $ptr, $indent_lvl + 1));
    }

    return sprintf('%s%s%s[%d](%s)', $indent_str,
      $type == $EXPR_FUNCTION_GEN ? '?' : '',
      $formatting_data{$value}, $hash, join(', ', @args));
  } elsif ($type == $EXPR_SYMBOL || $type == $EXPR_SYMBOL_GEN) {
    return sprintf('%s%s%s[%d]', $indent_str,
      $type == $EXPR_SYMBOL_GEN ? '?' : '',
      $formatting_data{$value}, $hash);
  } else {
    return sprintf('%s%d', $indent_str, $value);
  }
}

1;
