-- Copyright (c) 2017, Herman Bergwerf. All rights reserved.
-- Use of this source code is governed by an AGPL-3.0-style license
-- that can be found in the LICENSE file.

--------------------------------------------------------------------------------
-- Naming conventions:
-- + Do not use reserved keywords (SQL standard)
-- + Foreign key field names have a '_id' suffix
-- + Do not use abbreviations unless very common or required
--------------------------------------------------------------------------------

CREATE EXTENSION pgcrypto;

--------------------------------------------------------------------------------
-- Descriptors and translations
--------------------------------------------------------------------------------

-- Language
CREATE TABLE language (
  id    serial  PRIMARY KEY,
  code  text    NOT NULL UNIQUE
    CHECK (code ~ '^[a-z]{2}(_([a-zA-Z]{2}){1,2})?_[A-Z]{2}$') -- Validate ISO language code format.
);

-- Descriptor
-- Should NOT contain separate records for abbreviations or acronyms.
CREATE TABLE descriptor (
  id  serial  PRIMARY KEY
);

-- Translation of a descriptor
CREATE TABLE translation (
  id             serial   PRIMARY KEY,
  descriptor_id  integer  NOT NULL REFERENCES descriptor(id),
  language_id      integer  NOT NULL REFERENCES language(id),
  content        text     NOT NULL
    CHECK (content ~ E'^(?:[^\\s]+ )*[^\\s]+$'), -- Check for repeated spaces in the regex.
  
  -- Translations should have a unique meaning. If there are translations that
  -- can mean different things, the translation should be further specified.
  -- (as in Wikipedia page titles)
  UNIQUE (language_id, content)
);

-- Subject
CREATE TABLE subject (
  id             serial   PRIMARY KEY,
  descriptor_id  integer  NOT NULL UNIQUE REFERENCES descriptor(id)
);

--------------------------------------------------------------------------------
-- Functions and expression storage
--------------------------------------------------------------------------------

-- Function keyword types
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
  'symbol',

  -- Special case: this keyword is directly related to a LaTeX command.
  'latex'
);

-- Function
CREATE TABLE function (
  id              serial    PRIMARY KEY,
  subject_id      integer   NOT NULL REFERENCES subject(id),
  descriptor_id   integer   UNIQUE REFERENCES descriptor(id),
  generic         boolean   NOT NULL CHECK (NOT generic OR argument_count < 2),
  rearrangeable   boolean   NOT NULL CHECK (NOT (rearrangeable AND argument_count < 2)),
  argument_count  smallint  NOT NULL CHECK (argument_count >= 0),

  -- It is not feasible to make unique keywords. It is not required to configure
  -- a keyword. Operator functions do not have keywords. Exotic functions might
  -- not use a keyword (instead the descriptor could be used for lookup).
  keyword         text      CHECK (keyword ~ E'^[a-z]+[0-9]*$'),
  keyword_type    keyword_type,

  -- LaTeX template may be empty. Operator information, the keyword, or the
  -- descriptor can also be used to print this function.
  latex_template  text      CHECK ((latex_template = '') IS NOT TRUE),

  -- Do not repeat the same LaTeX template within the same subject.
  UNIQUE (subject_id, latex_template),

  -- Non-generic function with >0 arguments must have a name.
  -- E.g. functions such as ?a, ?fn(x) or x can be left unnamed.
  CONSTRAINT non_generic_with_args_needs_name CHECK
    (NOT (NOT generic AND argument_count > 0 AND descriptor_id IS NULL)),

  -- Keyword and keyword type must both be defined or not at all.
  CONSTRAINT keyword_must_have_type CHECK
    ((keyword IS NULL AND keyword_type IS NULL) OR
     (keyword IS NOT NULL AND keyword_type IS NOT NULL)),
  
  -- At least a keyword or a LaTeX template must be provided for printing.
  CONSTRAINT must_have_keyword_or_template CHECK
    (keyword IS NOT NULL OR latex_template IS NOT NULL)
);

CREATE INDEX function_keyword_index ON function(keyword);

-- Operator evaluation (relevant for printing parentheses)
CREATE TYPE operator_associativity AS ENUM ('ltr', 'rtl');

-- Recognized operator types.
-- + pefix has one argument and is placed before the argument (e.g. ~)
-- + infix has two arguments and is placed between the arguments (e.g. +)
-- + postfix has one argument and is placed after the argument (e.g. !)
CREATE TYPE operator_type AS ENUM ('prefix', 'infix', 'postfix');

-- Operator properties
CREATE TABLE operator (
  id                 serial                  PRIMARY KEY,
  function_id        integer                 NOT NULL UNIQUE REFERENCES function(id),
  precedence_level   smallint                NOT NULL CHECK (precedence_level > 0),
  associativity      operator_associativity  NOT NULL,
  operator_type      operator_type           NOT NULL,
  character          char(1)                 NOT NULL UNIQUE,
  editor_template    text                    NOT NULL UNIQUE
);

CREATE TYPE expression_type AS ENUM ('integer', 'function', 'generic');

-- Expression node
-- Note: expression references have not been implemented yet to reduce
-- complexity. The main objective is to make expressions indexable. This could
-- potentially also be achieved by writing a custom index in C.
CREATE TABLE expression (
  id         serial     PRIMARY KEY,
  data       bytea      NOT NULL UNIQUE,
  hash       bytea      NOT NULL UNIQUE,

  -- Rendered LaTeX expression
  latex      text,

  -- All function IDs in this expression for fast indexing and searching.
  functions  integer[]  NOT NULL,

  -- Node information.
  node_type       expression_type  NOT NULL,
  node_value      integer          NOT NULL,
  node_arguments  integer[]        NOT NULL -- ELEMENT REFERENCES expression(id)
);

CREATE INDEX expression_functions_index on expression USING GIN (functions);

--------------------------------------------------------------------------------
-- Rules and definitions
--------------------------------------------------------------------------------

-- Rule (equation of two expression)
-- Optimizations that could be implemented in the future:
-- + Set explicit reversibility (adds ability to force single direction).
-- + Add index for top level function ID.
CREATE TABLE rule (
  id                   serial     PRIMARY KEY,
  proof_id             integer,
  left_expression_id   integer    NOT NULL REFERENCES expression(id),
  right_expression_id  integer    NOT NULL REFERENCES expression(id),
  left_array_data      integer[]  NOT NULL,
  right_array_data     integer[]  NOT NULL,

  UNIQUE (left_expression_id, right_expression_id)
);

-- A rule definition
CREATE TABLE definition (
  id       serial   PRIMARY KEY,
  rule_id  integer  NOT NULL UNIQUE REFERENCES rule(id)

  -- TODO:
  -- + Theoretical definition (mathematical property of functions)
  -- + Empirical definition (physics)
);

--------------------------------------------------------------------------------
-- Expression manipulation
--------------------------------------------------------------------------------

CREATE TABLE proof (
  id             serial   PRIMARY KEY,
  first_step_id  integer  NOT NULL,
  last_step_id   integer  NOT NULL,

  UNIQUE (first_step_id, last_step_id)
);

-- Add rule proof constraint.
ALTER TABLE rule ADD FOREIGN KEY (proof_id) REFERENCES proof(id);

CREATE TYPE step_type AS ENUM (
  'set',         -- Set expression to arbitrary value.
  'copy_proof',  -- Copy first and last expression of a proof.
  'rule_normal', -- Substitute a -> b, evaluate b from a.
  'rule_invert', -- Substitute b -> a, evaluate a from b (invert rule sides).
  'rule_mirror', -- Substitute a -> b, evaluate a from b (mirror evaluation).
  'rule_revert', -- Substitute b -> a, evaluate b from a (invert and mirror).
  'rearrange'    -- Rearrange using the given format.
);

-- Expression manipulation step
CREATE TABLE step (
  id             serial     PRIMARY KEY,
  previous_id    integer    REFERENCES step(id),
  expression_id  integer    NOT NULL REFERENCES expression(id),

  -- Manipulation parameters
  position       smallint   NOT NULL CHECK (position >= 0),
  step_type      step_type  NOT NULL,
  proof_id       integer    REFERENCES proof(id),
  rule_id        integer    REFERENCES rule(id),
  rearrange      smallint[],

  -- Enforce various constraints.
  CONSTRAINT valid_type CHECK (
    (previous_id = NULL AND step_type = 'set') OR
    (previous_id != NULL AND (
      (step_type = 'copy_proof' AND proof_id IS NOT NULL) OR
      (step_type = 'rearrange' AND rearrange IS NOT NULL) OR
      (rule_id IS NOT NULL))))
);

-- Add proof step constraints.
ALTER TABLE proof ADD FOREIGN KEY (first_step_id) REFERENCES step(id);
ALTER TABLE proof ADD FOREIGN KEY (last_step_id) REFERENCES step(id);

--------------------------------------------------------------------------------
-- Create user and restrict access.
--------------------------------------------------------------------------------

REVOKE CONNECT ON DATABASE eqdb FROM public;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM public;

CREATE USER eqdb WITH ENCRYPTED PASSWORD '$password' CONNECTION LIMIT 100;
GRANT CONNECT ON DATABASE eqdb TO eqdb;
GRANT SELECT, INSERT ON ALL TABLES IN SCHEMA public TO eqdb;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public to eqdb;
GRANT USAGE ON LANGUAGE plperl TO eqdb;
