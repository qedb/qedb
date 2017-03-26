# Copyright (c) 2017, Herman Bergwerf. All rights reserved.
# Use of this source code is governed by an AGPL-3.0-style license
# that can be found in the LICENSE file.

# Hashing functions used to hash expression data.
package ExprUtils;
require Exporter;
@ISA        = qw(Exporter);
@EXPORT_OK  = qw(expr_hash_mix expr_hash_postprocess expr_hash expr_hash_str set_debug debug);

use strict;
use warnings;

# Simple logging.
# We avoid Log::Message::Simple to reduce dependencies.
my $debug_print = 0;
sub debug {
  if ($debug_print) {
    print @_;
  }
}

sub set_debug {
  $debug_print = $_[0] == 1;
}

sub expr_hash_mix {
  my ($hash, $value) = @_;
  $hash = 0x1fffffff & ($hash + $value);
  $hash = 0x1fffffff & ($hash + ((0x0007ffff & $hash) << 10));
  $hash = $hash ^ ($hash >> 6);
  return $hash;
}

sub expr_hash_postprocess {
  my ($hash) = @_;
  $hash = 0x1fffffff & ($hash + ((0x03ffffff & $hash) << 3));
  $hash = $hash ^ ($hash >> 11);
  return 0x1fffffff & ($hash + ((0x00003fff & $hash) << 15));
}

sub expr_hash {
  my $hash = 0;
  foreach my $value (@_) {
    $hash = expr_hash_mix($hash, $value);
  }
  return expr_hash_postprocess($hash);
}

sub expr_hash_str {
  my ($str) = @_;
  return expr_hash(map(ord, split('', $str)));
}

1;
