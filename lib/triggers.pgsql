-- Copyright (c) 2017, Herman Bergwerf. All rights reserved.
-- Use of this source code is governed by an AGPL-3.0-style license
-- that can be found in the LICENSE file.

CREATE OR REPLACE FUNCTION clear_expression_latex()
  RETURNS trigger AS $BODY$
BEGIN
  UPDATE expression SET latex = NULL WHERE functions @> ARRAY[NEW.id]::integer[];
  RETURN NULL;
END;
$BODY$
  LANGUAGE plpgsql;

-- Clear expression.latex when the latex template of one associated function is
-- updated.
CREATE TRIGGER function_latex_update
  AFTER UPDATE
  ON function
  FOR EACH ROW
  EXECUTE PROCEDURE clear_expression_latex();
