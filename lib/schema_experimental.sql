-- Copyright (c) 2017, Herman Bergwerf. All rights reserved.
-- Use of this source code is governed by an AGPL-3.0-style license
-- that can be found in the LICENSE file.

CREATE TYPE keyword_type AS ENUM (
  -- [a-z]+ form of an English translation of the function name descriptor
  -- No upper caps allowed! If the original name contains spaces, dashes or
  -- other complex symbols, you should consider to NOT create a 'word' keyword.
  'word',
  
  -- Short form of the function name descriptor
  'acronym',
  'abbreviation',
  
  -- Related to the function LaTeX template
  -- ([a-z]+ form of the function symbol)
  'symbol'
);

-- Keywords ([a-z]+ sequences that identify the function)
-- TODO: more general keywords (vector, circle, algebra)
CREATE TABLE keyword (
  id     serial        PRIMARY KEY,
  value  text          NOT NULL CHECK (value ~ '^[a-z]+$'),
  type   keyword_type  NOT NULL,

  -- Equal values with different types are allowed.
  UNIQUE (value, type)
);

-- Function keyword join
CREATE TABLE function_keyword (
  id           serial   PRIMARY KEY,
  function_id  integer  NOT NULL REFERENCES function(id),
  keyword_id   integer  NOT NULL REFERENCES keyword(id),

  -- Do not repeat keywords.
  UNIQUE (function_id, keyword_id)
);

-- Function definition-from-property naming
CREATE TABLE function_property (
  id             serial   PRIMARY KEY,
  descriptor_id  integer  NOT NULL REFERENCES descriptor(id)
);

-- Function property definition
CREATE TABLE function_property_definition (
  id                    serial   PRIMARY KEY,
  function_id           integer  NOT NULL REFERENCES function(id),
  definition_id         integer  NOT NULL REFERENCES definition(id),
  function_property_id  integer  NOT NULL REFERENCES function_property(id)
);

--------------------------------------------------------------------------------
-- Empirical values and expression evaluation
--------------------------------------------------------------------------------

-- Empirical value reference source
CREATE TABLE empirical_reference (
  id   serial  PRIMARY KEY,
  doi  text    NOT NULL UNIQUE
);

-- Empirical value (e.g. speed of light, or Avogadro's number)
CREATE TABLE empirical_value (
  id             serial   PRIMARY KEY,
  expression_id  integer  REFERENCES expression(id),
  reference_id   integer  REFERENCES empirical_reference(id),
  val            numeric  NOT NULL UNIQUE
);

-- Pre-computed, theoretical value (e.g. Pi, or Phi, or e)
-- Stored as 64bit floating point because that is the limit of computation.
-- Theoretical values are considered exact and their digits beyond 64bit are
-- not interesting.
CREATE TABLE theoretical_value (
  id             serial            PRIMARY KEY,
  expression_id  integer           REFERENCES expression(id),
  val            double precision  NOT NULL UNIQUE
);

CREATE TYPE evaluation_parameter_type as ENUM ('empirical', 'theoretical', 'evaluated');
CREATE TYPE evaluation_parameter AS (
  ref   integer,
  type  evaluation_parameter_type
);

-- Expression evaluation
CREATE TABLE evaluation (
  id             serial                  PRIMARY KEY,
  expression_id  integer                 NOT NULL REFERENCES expression(id),
  params         evaluation_parameter[]  NOT NULL,
  result         double precision        NOT NULL
);
