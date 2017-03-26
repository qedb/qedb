#!/usr/bin/env perl

# Copyright (c) 2017, Herman Bergwerf. All rights reserved.
# Use of this source code is governed by an AGPL-3.0-style license
# that can be found in the LICENSE file.

use strict;

use Term::ANSIColor;
use Time::HiRes  qw(time);
use ExprUtils    qw(set_debug debug);
use ExprBuilder  qw(expr_symbols expr_function expr_generic_function format_expression);
use ExprPattern  qw(expr_match_pattern expr_match_rule);

if ($ARGV[0] eq 'debug') {
  set_debug(1);
} else {
  set_debug(0);
}

my ($a, $b, $c, $d, $x, $y, $z) = expr_symbols('?a, ?b, ?c, ?d, x, y, z');
sub d { expr_function('d', @_); }
sub lim { expr_function('lim', @_); }
sub diff { expr_function('diff', @_); }
sub f { expr_generic_function('f', @_); }
sub sine { expr_function('sine', @_); }

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
my $rule_n = 8;
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
  [6, $a * $x + $a * $y >> $a * ($x + $y)],
  [7, diff(sine($x^2), $x) >> diff($x^2, $x) * diff(sine($x^2), $x^2)],
  [8, diff($x^2, $x) >> lim(d($x), 0, ((($x + d($x))^2) - (($x)^2)) / d($x))]
);

# Test result printer.
my $test_index = 0;
sub print_test_result {
  my ($name, $pass) = @_;
  print($pass ? color('bright_green') : color('bright_red'));
  print('test #', ++$test_index, ' (', $name, '): ',  $pass ? 'PASS' : 'FAIL', "\n");
  
  if (!$pass) {
    print(color('reset'));
    exit(1);
  }
}

# Run pattern tests.
foreach my $test_data (@pattern_tests) {
  # Alternate debug color.
  print(color($test_index % 2 == 0 ? 'white' : 'cyan'));

  my $result = expr_match_pattern($test_data->[1], $test_data->[2]);
  print_test_result 'pattern match', $result == $test_data->[0];
}

# Run rule tests.
foreach my $test_data (@rule_tests) {
  my @expr_left = @{$test_data->[1]->[0]};
  my @expr_right = @{$test_data->[1]->[1]};

  # Print expression.
  print(color('yellow'));
  debug("\nEQUATION:\n",
      format_expression(\@expr_left, 1), "\n\n=\n",
      format_expression(\@expr_right, 1), "\n\n");
  
  # Find matching rule (there can be only 1).
  my @matching_rules;
  for (my $i = 1; $i <= $rule_n; $i++) {
    # Alternate debug color.
    print(color($i % 2 == 0 ? 'white' : 'cyan'));

    my $rule_data = $rules{$i};
    my @rule_left = @{$rule_data->[0]};
    my @rule_right = @{$rule_data->[1]};

    debug(color('yellow'), "\nRULE:\n",
        format_expression(\@rule_left, 0), "\n=\n",
        format_expression(\@rule_right, 0), "\n\n");
    
    # Alternate debug color.
    print(color($i % 2 == 0 ? 'white' : 'cyan'));

    my $result = expr_match_rule(
      \@expr_left, \@expr_right,
      \@rule_left, \@rule_right);
    if ($result) {
      push @matching_rules, $i;
    }
  }

  my $expect = $test_data->[0];
  my $did_pass = scalar(@matching_rules) == 1 && $expect == $matching_rules[0];
  print_test_result 'rule match', $did_pass;
}

sub run_rule_benchmark_cycles {
  my ($n) = @_;

  for (my $count = 0; $count < $n; $count++) {
    foreach my $test_data (@rule_tests) {
      my @expr_left = @{$test_data->[1]->[0]};
      my @expr_right = @{$test_data->[1]->[1]};
      my $rule_n = 8;
      for (my $i = 1; $i <= $rule_n; $i++) {
        my $rule_data = $rules{$i};
        my @rule_left = @{$rule_data->[0]};
        my @rule_right = @{$rule_data->[1]};
        my $result = expr_match_rule(
          \@expr_left, \@expr_right,
          \@rule_left, \@rule_right);
      }
    }
  }
}

print(color('reset'), "All tests successful.\n");

# Run benchmark (if specified in command line argument).
if ($ARGV[0] eq 'benchmark') {
  # Warmup
  print("Benchmark warmup...\n");
  run_rule_benchmark_cycles(10000);

  # Time
  print("Actual benchmark...\n");
  my $benchmark_cycles = 10000;
  my $start_time = time();
  run_rule_benchmark_cycles($benchmark_cycles);
  my $end_time = time();
  my $s_per_call = ($end_time - $start_time) /
    (scalar(@rule_tests) * $rule_n * $benchmark_cycles);
  printf("Avg. time per call: %.2fns\n", $s_per_call * 1000000000);
  printf("Avg. calls per second: %.2f\n", 1 / $s_per_call);
}
