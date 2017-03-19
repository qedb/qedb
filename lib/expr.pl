#!/bin/perl

use strict;
use Time::HiRes qw(time);

my $EXPR_INTEGER       = 1;
my $EXPR_SYMBOL        = 2;
my $EXPR_SYMBOL_GEN    = 3;
my $EXPR_FUNCTION      = 4;
my $EXPR_FUNCTION_GEN  = 5;

# Simple logging.
my $debuglog_print = @ARGV[0] eq 'debug';
sub debuglog {
  if ($debuglog_print) {
    print 'LOG: ', @_;
  }
}

# Pattern matching algorithm for database rule sequential scans.
sub expr_match {
  my ($exprsrc, $pattern) = @_;

  debuglog 'exprsrc: ', join(', ', @$exprsrc), "\n";
  debuglog 'pattern: ', join(', ', @$pattern), "\n";

  sub skip_function_content {
    my ($data, $type, $ptr) = @_;

    if ($type == $EXPR_FUNCTION || $type == $EXPR_FUNCTION_GEN) {
      # Before this the pointer should point to the argument count.
      $$ptr++;
      # The pointer should now point to the first element after the last
      # element.
      $$ptr += $data->[$$ptr];
    }
  }

  sub check_match {
    my ($exprsrc, $pattern, $ptrE, $ptrP) = @_;

    my $typeE = $exprsrc->[$$ptrE++];
    my $typeP = $pattern->[$$ptrP++];
    my $valueD = $exprsrc->[$$ptrE++];
    my $valueP = $pattern->[$$ptrP++];
    
    if ($typeP == $EXPR_SYMBOL_GEN || $typeP == $EXPR_FUNCTION_GEN) {
      skip_function_content($exprsrc, $typeE, $ptrE);
      skip_function_content($pattern, $typeP, $ptrP);

      # Generic functions always match.
      return 1;
    } elsif ($typeP == $EXPR_INTEGER || $typeP == $EXPR_SYMBOL) {
      # There is no need to skip the function content of typeD. If the value
      # does not match false will directly propagate to the top anyway.
      return $typeE == $typeP && $valueD == $valueP;
    } elsif ($typeP == $EXPR_FUNCTION) {
      debuglog "pattern is function #$valueP\n";

      if ($typeE == $EXPR_FUNCTION && $valueD == $valueP) {
        my $argcE = $exprsrc->[$$ptrE++];
        my $argcP = $pattern->[$$ptrP++];

        # Skip jump numbers.
        $$ptrE++;
        $$ptrP++;

        debuglog "matching functions, argument count: $argcE, $argcP\n";

        if ($argcE == $argcP) {
          while ($argcP > 0) {
            if (!check_match($exprsrc, $pattern, $ptrE, $ptrP)) {
              debuglog 'argument mismatch @ ', $argcE - $argcP, "\n";
              return 0;
            }
            $argcP--;
          }

          # All arguments matched.
          return 1;
        } else {
          return 0;
        }
      } else {
        return 0;
      }
    }

    return 0;
  }

  my $ptrE = 0;
  my $ptrP = 0;
  
  return check_match($exprsrc, $pattern, \$ptrE, \$ptrP);
}

# Some functions to construct test data.
sub numi { my @arr = ($EXPR_INTEGER, @_[0]); return \@arr; }
sub symb { my @arr = ($EXPR_SYMBOL, ord(@_[0])); return \@arr; }
sub symg { my @arr = ($EXPR_SYMBOL_GEN, ord(@_[0])); return \@arr; }
sub func {
  my @data = ($EXPR_FUNCTION, ord(shift), 0, 0);
  foreach my $arg (@_) {
    $data[2]++;
    push(@data, @$arg);
  }
  @data[3] = scalar(@data) - 4;
  return \@data;
}
sub fung {
  # Must have 1 argument.
  my @data = ($EXPR_FUNCTION_GEN, ord(shift), 1, 0);
  my $arg = shift;
  push(@data, @$arg);
  @data[3] = scalar(@$arg);
  return \@data;
}

# Test cases
my @tests = (
  [
    func('+', numi(100), func('/', symb('x'), symb('y'))),
    func('+', symg('a'), symg('b')),
    1
  ],
  [
    func('+', numi(100), func('/', symb('x'), symb('y'))),
    func('+', numi(101), symg('b')),
    0
  ],
  [
    func('+', numi(100), func('/', symb('x'), symb('y'))),
    func('+', symg('a'), symb('b')),
    0
  ],
  [
    func('+', numi(100), func('/', symb('x'), symb('y'))),
    func('+', symg('a'), fung('/', symg('x'))),
    1
  ],
  [
    func('+', numi(100), fung('/', symb('x'), symb('y'))),
    func('+', symg('a'), func('/', symg('x'))),
    0
  ],
  [
    func('+', numi(100), func('/', symb('x'), symb('y'))),
    func('+', symg('a'), func('/', symb('x'), symg('z'))),
    1
  ]
);

my $testI = 0;
foreach my $test (@tests) {
  my $result = expr_match($test->[0], $test->[1]);
  print 'test #', ++$testI, ': ', $result == $test->[2] ? 'PASS' : 'FAIL', "\n";
}

# Performance test, run all 6 test cases 10.000 times.
my $start_time = time();

my $n = 10000;
my $counter = $n;
while ($counter--) {
  foreach my $test (@tests) {
    expr_match($test->[0], $test->[1]);
  }
}

my $end_time = time();
my $s_per_call = ($end_time - $start_time) / (scalar(@tests) * $n);
printf("Avg. time per call: %.2fns\n", $s_per_call * 1000000000);
printf("Avg. calls per second: %.2f\n", 1 / $s_per_call);
