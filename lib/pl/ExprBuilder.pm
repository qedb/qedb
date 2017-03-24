# Copyright (c) 2017, Herman Bergwerf. All rights reserved.
# Use of this source code is governed by an AGPL-3.0-style license
# that can be found in the LICENSE file.

package ExprBuilder;
require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(expr_number expr_symbols expr_function expr_generic_function);

use strict;
use warnings;

# Jenkins one-at-a-time hash
{
  package EqLib::Hash;

  sub jenkins_oaat {
    my $hash = 0;
    foreach (@_) {
      $hash += $_;
      $hash += 0x1fffffff & ($hash << 10);
      $hash ^= 0x1fffffff & ($hash >> 6);
    }
    $hash += 0x1fffffff & ($hash << 3);
    $hash ^= 0x1fffffff & ($hash >> 11);
    $hash += 0x1fffffff & ($hash << 15);
    return $hash;
  }
  
  sub jenkins_oaat_str {
    return jenkins_oaat(map(ord, split(//, shift)));
  }
}

# Expression array builders.
{
  package EqLib::Expr;
  
  my $EXPR_INTEGER       = 1;
  my $EXPR_SYMBOL        = 2;
  my $EXPR_SYMBOL_GEN    = 3;
  my $EXPR_FUNCTION      = 4;
  my $EXPR_FUNCTION_GEN  = 5;
  
  # Create expression from data array (add hash and bless).
  sub make_expr {
    my @array = @_;
    unshift(@array, EqLib::Hash::jenkins_oaat(@array));
    my $ref = \@array;
    bless $ref, 'EqLib::Expr::WithOperators';
    return \@array;
  }
  
  # Create function from argument array.
  sub make_function {
    my @data = (shift, EqLib::Hash::jenkins_oaat_str(shift), 0, 0);
    foreach my $arg (@_) {
      $data[2]++;
      if (ref($arg) eq 'EqLib::Expr::WithOperators') {
        push(@data, @$arg);
      } else {
        my $numdata = number($arg);
        push(@data, @$numdata);
      }
    }
    $data[3] = scalar(@data) - 4;
    return make_expr(@data);
  }
  
  sub number { return make_expr($EXPR_INTEGER, $_[0]); }
  
  sub symbol {
    return make_expr($EXPR_SYMBOL,
      EqLib::Hash::jenkins_oaat_str($_[0]));
  }
  sub symbol_gen {
    return make_expr($EXPR_SYMBOL_GEN,
      EqLib::Hash::jenkins_oaat_str($_[0]));
  }
  
  sub function { return make_function($EXPR_FUNCTION, @_); }
  sub function_gen { return make_function($EXPR_FUNCTION_GEN, @_); }
  
  sub _auto_symbol {
    my $str = $_;
    if (substr($str, 0, 1) eq '?') {
      return symbol_gen(substr $str, 1);
    } else {
      return symbol($str);
    }
  }
  
  sub symbols {
    my @strs = split(/,\s/, shift);
    return map(_auto_symbol, @strs);
  }
}

# Operators for expression arrays (which are blessed with this 'class').
{
  package EqLib::Expr::WithOperators;
  
  sub make_op_args {
    if ($_[2]) {
      return ($_[0], $_[1]);
    } else {
      return ($_[1], $_[0]);
    }
  }
  
  use overload
    '+' => sub { EqLib::Expr::function('+', make_op_args($_[0], $_[1], $_[2])); },
    '-' => sub { EqLib::Expr::function('-', make_op_args($_[0], $_[1], $_[2])); },
    '*' => sub { EqLib::Expr::function('*', make_op_args($_[0], $_[1], $_[2])); },
    '/' => sub { EqLib::Expr::function('/', make_op_args($_[0], $_[1], $_[2])); },
    '^' => sub { EqLib::Expr::function('^', make_op_args($_[0], $_[1], $_[2])); },
    '>>' => sub { [$_[0], $_[1]]; };
}

# Public API functions.
sub expr_number { EqLib::Expr::number(@_); }
sub expr_symbols { EqLib::Expr::symbols(@_); }
sub expr_function { EqLib::Expr::function(@_); }
sub expr_generic_function { EqLib::Expr::function_gen(@_); }

# Succesfully load module.
return 1;
