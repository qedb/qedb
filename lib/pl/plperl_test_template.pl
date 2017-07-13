# Copyright (c) 2017, Herman Bergwerf. All rights reserved.
# Use of this source code is governed by an AGPL-3.0-style license
# that can be found in the LICENSE file.

#
# Modified version of algorithm source that can be used with PL/Perl.
#
# Modifications:
# - Use anonymous subroutines (preserve: exists, defined, scalar, pop, push)
# - Remove debug calls.
#
sub plperl_function {
# INSERT

return $match_subs->(@_);
}

# Mini test.
print(plperl_function(
  [5, 4, 1, 2, 6, 7, 2, 9, 3, 1, 1], # expr left
  [6, 4, 1, 2, 6, 3, 1, 1, 7, 2, 9], # expr right
  [1, 4, 1, 2, 6, 3, 3, 8, 4, 3, 9], # subs left
  [2, 4, 1, 2, 6, 4, 3, 9, 3, 3, 8], # subs right
  undef) # computable ids
  ? 'PASS!!!' : 'FAIL :(', "\n");
