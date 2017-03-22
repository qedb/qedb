#!/bin/perl

use strict;

use Time::HiRes qw(time);

my $EXPR_INTEGER       = 1;
my $EXPR_SYMBOL        = 2;
my $EXPR_SYMBOL_GEN    = 3;
my $EXPR_FUNCTION      = 4;
my $EXPR_FUNCTION_GEN  = 5;

# Jenkins one-at-a-time hash
sub jenkins_oaat_combine {
  my $hash = shift;
  foreach (@_) {
    $hash = 0x1fffffff & ($hash + $_);
    $hash = 0x1fffffff & ($hash + ((0x0007ffff & $hash) << 10));
    $hash = $hash ^ ($hash >> 6);
  }
  return $hash;
}

sub jenkins_oaat_finish {
  my $hash = shift;
  $hash = 0x1fffffff & ($hash + ((0x03ffffff & $hash) << 3));
  $hash = $hash ^ ($hash >> 11);
  return 0x1fffffff & ($hash + ((0x00003fff & $hash) << 15));
}

sub jenkins_oaat {
  return jenkins_oaat_finish(jenkins_oaat_combine(0, @_));
}

# Simple logging.
my $debuglog_print = @ARGV[0] eq 'debug';
sub debuglog {
  if ($debuglog_print) {
    print 'LOG: ', @_;
  }
}

# Recursive expression pattern matching.
# TODO: store final index pointer values back into references.
sub match_pattern {
  my ($write_mapping, $mapping_hash_ref, $mapping_ptrs_ref, $ptr_e, $ptr_p, @data) = @_;
  my %mapping_hash = %$mapping_hash_ref;
  my %mapping_ptrs = %$mapping_ptrs_ref;
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
      # When writing a mapping we do not collect generic function arguments.T
      # These can be collected later. This saves performance at the cost of not
      # being strict about a second, equal generic not having arguments. However
      # this should not be a concern anymore at this stage (if it was inserted
      # into the database it is already checked).
      
      # Jump over function body.
      if ($type_e == $EXPR_FUNCTION || $type_e == $EXPR_FUNCTION_GEN) {
        $ptr_e += 1 + $data[$ptr_e + 1];
      }
      if ($type_p == $EXPR_FUNCTION_GEN) {
        $ptr_p += 1 + $data[$ptr_p + 1];
      }
      
      # TODO: store pointers to generic functions and expressions they map to.
      # TODO: when $write_mapping = 0, recursively execute this function.
  
      # Store expression hash in generic mapping.
      if (!$write_mapping || exists $mapping_hash{$value_p}) {
        if (!$mapping_hash{$value_p} == $hash_e) {
          return 0;
        }
      } else {
        $mapping_hash{$value_p} = $hash_e;
      }
    } elsif ($type_p == $EXPR_INTEGER || $type_p == $EXPR_SYMBOL) {
      # There is no need to skip the function content of the expression. If it
      # is a function the pattern is not matching anymore.
      if (!($type_e == $type_p && $value_e == $value_p)) {
        return 0;
      }
    } elsif ($type_p == $EXPR_FUNCTION) {
      debuglog "pattern is function #$value_p\n";
  
      if ($type_e == $EXPR_FUNCTION && $value_e == $value_p) {
        my $argc_e = $data[$ptr_e++];
        my $argc_p = $data[$ptr_p++];
  
        debuglog "matching functions, argument count: $argc_e, $argc_p\n";
  
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
  
  return 1;
}

# Initialization function for match_pattern.
sub expr_match_pattern {
  my ($exprsrc, $pattern) = @_;
  my (%mapping_hash, %mapping_ptrs);
  my $ptr_e = 0;
  my $ptr_p = scalar(@$exprsrc);
  
  debuglog 'exprsrc: ', join(', ', @$exprsrc), "\n";
  debuglog 'pattern: ', join(', ', @$pattern), "\n";
  
  return match_pattern(
    1, \%mapping_hash, \%mapping_ptrs, $ptr_e, $ptr_p, @$exprsrc, @$pattern);
}

# Rule matching
sub expr_match_rule {
  my ($expr_left, $expr_right, $rule_left, $rule_right) = @_;
  my (%mapping_hash, %mapping_ptrs);
  my $ptr_e = 0;
  my $ptr_p = scalar(@$expr_left) + scalar(@$expr_right);
  my @data = (@$expr_left, @$expr_right, @$rule_left, @$rule_right);
  
  my $result_left = match_pattern(
    1, \%mapping_hash, \%mapping_ptrs, $ptr_e, $ptr_p, @data);
  if (!$result_left) {
    return 0;
  }
  
  $ptr_e = $ptr_p = 0;
  return match_pattern(
    0, \%mapping_hash, \%mapping_ptrs, $ptr_e, $ptr_p, @data);
}

# Some functions to construct test data.
sub _expr {
  my @array = @_;
  unshift(@array, jenkins_oaat(@array));
  return \@array;
}

sub _fn {
  my @data = (shift, ord(shift), 0, 0);
  foreach my $arg (@_) {
    $data[2]++;
    push(@data, @$arg);
  }
  $data[3] = scalar(@data) - 4;
  return _expr(@data);
}

sub numi { return _expr($EXPR_INTEGER, @_[0]); }
sub symb { return _expr($EXPR_SYMBOL, ord(@_[0])); }
sub symg { return _expr($EXPR_SYMBOL_GEN, ord(@_[0])); }
sub func { return _fn($EXPR_FUNCTION, @_); }
sub fung { return _fn($EXPR_FUNCTION_GEN, @_); }

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
  my $result = expr_match_pattern($test->[0], $test->[1]);
  print 'test #', ++$testI, ': ', $result == $test->[2] ? 'PASS' : 'FAIL', "\n";
}

# Performance test, run all 6 test cases 10.000 times.
$debuglog_print = 0;
my $start_time = time();

my $n = 10000;
my $counter = $n;
while ($counter--) {
  foreach my $test (@tests) {
    expr_match_pattern($test->[0], $test->[1]);
  }
}

my $end_time = time();
my $s_per_call = ($end_time - $start_time) / (scalar(@tests) * $n);
printf("Avg. time per call: %.2fns\n", $s_per_call * 1000000000);
printf("Avg. calls per second: %.2f\n", 1 / $s_per_call);
