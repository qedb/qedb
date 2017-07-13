#!/bin/bash

PLCODE1="$(awk '/# BEGIN/{flag=1;next}/# END/{flag=0}flag' lib/pl/ExprUtils.pm)"
PLCODE2="$(awk '/# BEGIN/{flag=1;next}/# END/{flag=0}flag' lib/pl/ExprPattern.pm)"
PLCODE="${PLCODE1}"$'\n'"${PLCODE2}"

# Escape '&'.
PLCODE="$(echo "$PLCODE" | sed -e 's/\&/\\&/g')"
# Remove debug() calls.
PLCODE="$(echo "$PLCODE" | perl -pe 'BEGIN{undef $/;} s/\n +debug\(.*\);//g')"
# Make subroutines anonymous.
PLCODE="$(echo "$PLCODE" | perl -pe 's/sub ([a-z_]+) \{/\my \$$1 = sub {/g')"
# Add semicolon after subroutine body.
PLCODE="$(echo "$PLCODE" | perl -pe 'BEGIN{undef $/;} s/\n\}/\n\};/g')"
# Make subroutine calls anonymous.
PLCODE="$(echo "$PLCODE" | perl -pe 's/([a-z_]+)\(/\$$1->\(/g')"
# Declare my $compute_mapped_hash and my $match_pattern first.
PLCODE="$(echo "$PLCODE" | perl -pe 's/my \$match_pattern/my \$match_pattern;\n\$match_pattern/g')"
PLCODE="$(echo "$PLCODE" | perl -pe 's/my \$compute_mapped_hash/my \$compute_mapped_hash;\n\$compute_mapped_hash/g')"
# Escape backslashes.
PLCODE="$(echo "$PLCODE" | sed -e 's/\\/\\\\/g')"
# Substitute into template.
awk -v r="$PLCODE" '{gsub("# INSERT",r);}1' lib/pl/plperl_test_template.pl > lib/pl/plperl_test.pl
awk -v r="$PLCODE" '{gsub("# INSERT",r);}1' lib/pl/expr_template.pgsql > lib/pl/expr.pgsql
