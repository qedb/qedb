#!/usr/bin/env perl

# Copyright (c) 2017, Herman Bergwerf. All rights reserved.
# Use of this source code is governed by an AGPL-3.0-style license
# that can be found in the LICENSE file.

use strict;

use Term::ANSIColor;
use Time::HiRes  qw(time);
use ExprUtils    qw(expr_hash_str set_debug debug);
use ExprBuilder  qw(expr_number expr_symbols expr_function expr_generic_function format_expression);
use ExprPattern  qw(match_expr match_subs);

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
sub g { expr_function('g', @_); }
sub h { expr_function('h', @_); }
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
my $rule_n = 12;
my %rules = (
  1 => $a + $b >> $b + $a,
  2 => $a - $b >> $b - $a,
  3 => $a * $b >> $b * $a,
  4 => $a + ($b + $c) >> ($a + $b) + $c,
  5 => $a * ($b * $c) >> ($a * $b) * $c,
  6 => $a * $b + $a * $c >> $a * ($b + $c),
  7 => diff(f($a), $b) >> diff($a, $b) * diff(f($a), $a),
  8 => diff(f($a), $a) >> lim(d($a), 0, (f($a + d($a)) - f($a)) / d($a)),
  9 => diff($a^$b, $a) >> $b * ($a^($b - 1)),
  10 => $a - $b >> $a + ~$b,
  11 => ($a^$b * $a^$c) >> ($a ^ ($b + $c)),
  12 => ($b*$a + $c*$a) >> (($b + $c)*$a)
);

# Rule inputs that are tested, format: [RULE#, EQUATION].
my @rule_tests = (
  [1, $x + 1 >> 1 + $x],
  [6, $a * $x + $a * $y >> $a * ($x + $y)],
  [7, diff(sine($x^2), $x) >> diff($x^2, $x) * diff(sine($x^2), $x^2)],
  [8, diff($x^2, $x) >> lim(d($x), 0, ((($x + d($x))^2) - (($x)^2)) / d($x))],
  [1, expr_number(1) + expr_number(2) >> expr_number(3)],
  [9, diff($x^2, $x) >> 2*($x^1)],
  [10, $x - $y >> $x + ~$y],
  [10, $x - 1 >> $x + -1],
  [11, ($x^1 * $x^2) >> ($x^3)],
  [11, ($x^expr_number(-1) * $x^4) >> ($x^3)],
  [12, ($y*$x + $z*$x) >> (($y+$z)*$x)],
  [12, ($y*$x + $y*$x) >> (($y+$y)*$x)],
  [12, (expr_number(1)*$x + expr_number(1)*$x) >> (2*$x)],
  [-1, diff(g($x), $x) >> lim(d($x), 0, ($x - g($x)) / d($x))],
  [8, diff($c*$d, $c) >> lim(d($c), 0, (($c + d($c))*$d - ($c*$d)) / d($c))],
  [8, diff(g($x)*h($x), $x) >> lim(d($x), 0,
    ((g($x + d($x))*h($x + d($x))) - (g($x)*h($x))) / d($x))]
);

# Exceptional case that was found in the usage of this function where in
# diff(f(x), x) => lim(d(x), 0, (f(x + d(x)) - f(x)) / d(x))
# `f(x + d(x))` can be any expression for the algorithm to report a match.
# (in the test data its `x`)
my @bug1_expr_left = (
  733172344,4,22,3,40,662684094,4,21,1,3,910648714,3,18,1,1,0,756435250,4,5,2,
  24,603155738,4,3,2,11,910648714,3,18,129606980,5,20,1,3,910648714,3,18,
  662684094,4,21,1,3,910648714,3,18);
my @bug1_expr_right = (
  909282448,4,23,2,11,910648714,3,18,129606980,5,20,1,3,910648714,3,18);
my @bug1_subs_left = (
  298586446,4,22,3,58,662684094,4,21,1,3,910648714,3,18,1,1,0,976197574,4,5,2,
  42,396128080,4,3,2,29,76780122,5,20,1,16,1022394746,4,2,2,11,910648714,3,18,
  662684094,4,21,1,3,910648714,3,18,129606980,5,20,1,3,910648714,3,18,662684094,
  4,21,1,3,910648714,3,18);
my @bug1_subs_right = (
  909282448,4,23,2,11,910648714,3,18,129606980,5,20,1,3,910648714,3,18);
my @bug1_computable = (2,3,4,7);

print('Bug 1 result: ', match_subs(\@bug1_expr_left, \@bug1_expr_right,
  \@bug1_subs_left, \@bug1_subs_right, \@bug1_computable), "\n");

# Computable function IDs.
my @computable_ids = map { expr_hash_str($_) } ('+', '-', '*', '~');

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

  my $result = match_expr($test_data->[1], $test_data->[2]);
  print_test_result('pattern match', $result == $test_data->[0]);
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

    my $result = match_subs(
      \@expr_left, \@expr_right,
      \@rule_left, \@rule_right,
      \@computable_ids);
    if ($result) {
      push @matching_rules, $i;
    }
  }

  my $expect = $test_data->[0];
  my $nmatching = scalar(@matching_rules);
  my $did_pass = $expect == -1 ? $nmatching == 0 :
    ($nmatching == 1 && $expect == $matching_rules[0]);
  print_test_result('rule match', $did_pass);
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
        my $result = match_subs(
          \@expr_left, \@expr_right,
          \@rule_left, \@rule_right,
          \@computable_ids);
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
