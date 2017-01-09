CREATE OR REPLACE FUNCTION insert_number(double precision)
  RETURNS TABLE (id integer, val double precision)
  AS $$
  DECLARE numid integer;
  DECLARE numval double precision;
  BEGIN
    SELECT id, val INTO numid, numval FROM numdata WHERE val = $1;
    IF numid IS NULL THEN
      -- Note: it is possible for the insert to fail due to concurrency
      -- with other clients. In this rare case the ON CONFLICT offers a
      -- solution.
      INSERT INTO numdata VALUES (DEFAULT, $1)
      ON CONFLICT ON CONSTRAINT numdata_val_key
        DO UPDATE SET val = $1
      RETURNING id, val INTO numid, numval;
    END IF;
    id := numid;
    val := numval;
    RETURN NEXT;
  END
  $$ LANGUAGE plpgsql;