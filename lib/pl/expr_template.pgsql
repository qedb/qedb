-- Copyright (c) 2017, Herman Bergwerf. All rights reserved.
-- Use of this source code is governed by an AGPL-3.0-style license
-- that can be found in the LICENSE file.

CREATE EXTENSION plperl;

-- To test:
--
-- SELECT * FROM rule WHERE match_subs(
--   ARRAY[5, 4, 1, 2, 6, 7, 2, 9, 3, 1, 1],
--   ARRAY[6, 4, 1, 2, 6, 3, 1, 1, 7, 2, 9],
--   left_array_data, right_array_data, ARRAY[1, 2, 3]);

CREATE FUNCTION match_subs(
  integer[], -- expr left
  integer[], -- expr right
  integer[], -- rule left
  integer[], -- rule right
  integer[]) -- computable ids
RETURNS boolean AS $BODY$
# INSERT

return $match_subs->(@_);
$BODY$
  LANGUAGE plperl;
