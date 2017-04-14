-- Copyright (c) 2017, Herman Bergwerf. All rights reserved.
-- Use of this source code is governed by an AGPL-3.0-style license
-- that can be found in the LICENSE file.

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

-- Generic mapping
-- This is neccesary to close a loophole in expression rewriting:
-- + f(?x) = ?x + g, g = ?x
-- + f(2?x) = 2?x + g = 2?x + ?x
-- + f(?x) = ?x + ?x, f(2?x) = 2?x + 2?x
CREATE TABLE lineage_step_generic_mapping (
  id             serial   PRIMARY KEY,
  step_id        integer  NOT NULL REFERENCES lineage_step(id),
  generic_id     integer  NOT NULL REFERENCES function(id),
  expression_id  integer  NOT NULL REFERENCES expression(id)
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

--------------------------------------------------------------------------------
-- Page
--------------------------------------------------------------------------------

CREATE TABLE page (
  id             serial   PRIMARY KEY,
  draft_id       integer  NOT NULL REFERENCES page_draft(id),
  descriptor_id  integer  NOT NULL UNIQUE REFERENCES descriptor(id)
);

CREATE TABLE page_definition (
  id             serial   PRIMARY KEY,
  page_id        integer  NOT NULL REFERENCES page(id),
  definition_id  integer  NOT NULL REFERENCES definition(id),
  sequence       integer  NOT NULL CHECK (sequence > 0)
);

CREATE TABLE page_lineage (
  id                serial   PRIMARY KEY,
  page_id           integer  NOT NULL REFERENCES page(id),
  lineage_start_id  integer  NOT NULL REFERENCES lineage_step(id),
  lineage_end_id    integer  NOT NULL REFERENCES lineage_step(id),
  sequence          integer  NOT NULL CHECK (sequence > 0)
);

CREATE TABLE page_illustration (
  id        serial   PRIMARY KEY,
  page_id   integer  NOT NULL REFERENCES page(id),
  sequence  integer  NOT NULL CHECK (sequence > 0),
  data      json
);
