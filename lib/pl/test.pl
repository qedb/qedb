#!/usr/bin/env perl

# Copyright (c) 2017, Herman Bergwerf. All rights reserved.
# Use of this source code is governed by an AGPL-3.0-style license
# that can be found in the LICENSE file.

use strict;

use Time::HiRes qw(time);
use ExprBuilder qw(expr_symbols expr_function expr_generic_function);
use ExprPattern qw(expr_match_pattern expr_match_rule);

my ($a, $b, $c, $d, $x, $y, $z) = expr_symbols('?a, ?b, ?c, ?d, x, y, z');
sub d { expr_function('d', @_); }
sub lim { expr_function('lim', @_); }
sub diff { expr_function('diff', @_); }
sub f { expr_generic_function('f', @_); }

# Basic pattern matching tests.
# Can be used to compute benchmark.
my @pattern_tests = (
  [1, $x + 1, $a + $b],
  [1, 1 + $x / $y, $a + $b],
  [0, 1 + $a / $b, $x + $y],
  [1, $x+ $x / $y, $x + $a],
  [0, $x * ($y + $z), $a * $b + $c],
  [1, ($x * $y) + $z, $a * $b + $c]
);

# Rules to test against.
my %rules = (
  1 => $a + $b >> $b + $a,
  2 => $a - $b >> $b - $a,
  3 => $a * $b >> $b * $a,
  4 => $a + ($b + $c) >> ($a + $b) + $c,
  5 => $a * ($b * $c) >> ($a * $b) * $c,
  6 => $a * $b + $a * $c >> $a * ($b + $c),
  7 => diff(f($a), $b) >> diff($a, $b) * diff(f($a), $a),
  8 => diff(f($a), $a) >> lim(d($a), 0, (f($a + d($a)) - f($a)) / d($a))
);

# Rule inputs that are tested, format: [RULE#, EQUATION].
my @rule_tests = (
  [1, $x + 1 >> 1 + $x],
  [7, diff(f($x^2), $x) >> diff($x^2, $x) * diff(f($x^2), $x^2)]
);

# Test result printer.
my $test_index = 0;
sub print_test_result {
  my ($name, $pass) = @_;
  print 'test #', ++$test_index, ' (', $name, '): ',  $pass ? 'PASS' : 'FAIL', "\n";
}

# Run pattern tests.
foreach my $test_data (@pattern_tests) {
  my $result = expr_match_pattern($test_data->[1], $test_data->[2]);
  print_test_result 'pattern match', $result == $test_data->[0];
}

# Run rule tests.
foreach my $test_data (@rule_tests) {
  my @expr_left = @{$test_data->[1]->[0]};
  my @expr_right = @{$test_data->[1]->[1]};
  
  # Find matching rule (there can be only 1).
  my @matching_rules;
  while (my ($key, $value) = each %rules) {
    my @rule_left = @{$value->[0]};
    my @rule_right = @{$value->[1]};

    my $result = expr_match_rule(
      \@expr_left, \@expr_right,
      \@rule_left, \@rule_right);
    if ($result) {
      push @matching_rules, $key;
    }
  }

  print_test_result 'rule match', @matching_rules == $test_data->[0];
}

# Run benchmark (if specified in command line argument).
if ($ARGV[0] == 'benchmark') {
  # Warmup

  # Time
}


# # Performance test, run all 6 test cases 10.000 times.
# $debuglog_print = 0;
# my $start_time = time();

# my $n = 10000;
# my $counter = $n;
# while ($counter--) {
#   foreach my $test (@tests) {
#     expr_match_pattern($test->[0], $test->[1]);
#   }
# }

# my $end_time = time();
# my $s_per_call = ($end_time - $start_time) / (scalar(@tests) * $n);
# printf("Avg. time per call: %.2fns\n", $s_per_call * 1000000000);
# printf("Avg. calls per second: %.2f\n", 1 / $s_per_call);
