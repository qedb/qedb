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

-- Descriptor
-- Should NOT contain separate records for abbreviations or acronyms.
CREATE TABLE descriptor (
  id  serial  PRIMARY KEY
);

-- Subject
-- A descriptor should be approved to be a subject. Subjects are used for
-- categories and for secundary function grouping.
CREATE TABLE subject (
  id             serial   PRIMARY KEY,
  descriptor_id  integer  NOT NULL UNIQUE REFERENCES descriptor(id)
);

-- Locale
CREATE TABLE locale (
  id    serial  PRIMARY KEY,
  code  text    NOT NULL UNIQUE
    CHECK (code ~ '^[a-z]{2}(_([a-zA-Z]{2}){1,2})?_[A-Z]{2}$') -- Match validate ISO locale code format.
);

-- Translation of a descriptor
CREATE TABLE translation (
  id             serial   PRIMARY KEY,
  descriptor_id  integer  NOT NULL REFERENCES descriptor(id),
  locale_id      integer  NOT NULL REFERENCES locale(id),
  content        text     NOT NULL
    CHECK (content ~ E'^(?:[^\\s]+ )*[^\\s]+$'), -- Check for repeated spaces in the regex.
  
  -- Translations should have a unique meaning. If there are translations that
  -- can mean different things, the translation should be further specified.
  -- (as in Wikipedia page titles)
  UNIQUE (locale_id, content)
);

--------------------------------------------------------------------------------
-- Categories and expression storage
--------------------------------------------------------------------------------

-- Category
-- The referenced subject can not already be used by any function subject tag.
-- Currently a category must be tied to a subject. This in order to prevent
-- unclarity about the category contents.
CREATE TABLE category (
  id          serial     PRIMARY KEY,
  subject_id  integer    NOT NULL UNIQUE REFERENCES subject(id),
  parents     integer[]  NOT NULL
);

-- Function
-- Soft constraint: non-generic function with >0 arguments must have a name.
CREATE TABLE function (
  id              serial    PRIMARY KEY,
  category_id     integer   NOT NULL REFERENCES category(id),
  descriptor_id   integer   UNIQUE REFERENCES descriptor(id),
  argument_count  smallint  NOT NULL CHECK (argument_count >= 0),
  latex_template  text      NOT NULL CHECK (NOT latex_template = ''),
  generic         boolean   NOT NULL CHECK (NOT generic OR argument_count < 2)
);
CREATE INDEX function_category_id_index ON function(category_id);

-- Function subject tag
-- The referenced subject can not already be used by a category.
CREATE TABLE function_subject_tag (
  id           serial   PRIMARY KEY,
  function_id  integer  NOT NULL REFERENCES function(id),
  subject_id   integer  NOT NULL REFERENCES subject(id)
);

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

-- Operator evaluation (relevant for printing parentheses)
CREATE TYPE operator_associativity AS ENUM ('ltr', 'rtl');

-- Operator properties
CREATE TABLE operator (
  id                serial                  PRIMARY KEY,
  function_id       integer                 NOT NULL UNIQUE REFERENCES function(id),
  precedence_level  smallint                NOT NULL CHECK (precedence_level > 0),
  associativity     operator_associativity  NOT NULL
);

-- Inline reference to another expression reference.
CREATE TYPE expression_reference_type AS ENUM ('function', 'symbol', 'integer');
CREATE TYPE expression_reference AS (
  key   integer,
  type  expression_reference_type
);

-- Expression node
CREATE TABLE expression (
  id         serial                PRIMARY KEY,
  reference  expression_reference  NOT NULL UNIQUE,
  data       bytea                 NOT NULL UNIQUE,
  hash       bytea                 NOT NULL UNIQUE,

  -- All function IDs in this expression for fast indexing and searching.
  functions  integer[]             NOT NULL
);
CREATE INDEX expression_functions_index on expression USING GIN (functions);

-- Function expression reference
CREATE TABLE function_reference (
  id           serial                  PRIMARY KEY,
  function_id  integer                 NOT NULL REFERENCES function(id),
  arguments    expression_reference[]  NOT NULL CHECK (array_length(arguments, 1) > 0)
);

-- Integer expression reference
CREATE TABLE integer_reference (
  id   serial   PRIMARY KEY,
  val  integer  NOT NULL
);

--------------------------------------------------------------------------------
-- Lineages
--------------------------------------------------------------------------------

-- Lineage tree
CREATE TABLE lineage_tree (
  id  serial PRIMARY KEY
);

-- Lineage
CREATE TABLE lineage (
  id                   serial   PRIMARY KEY,
  tree_id              integer  NOT NULL REFERENCES lineage_tree(id),
  parent_id            integer           REFERENCES lineage(id) DEFAULT NULL,
  branch_index         integer  NOT NULL DEFAULT 0,
  initial_category_id  integer  NOT NULL REFERENCES category(id),
  first_expression_id  integer  NOT NULL REFERENCES expression(id)
);

-- Lineage category transition
CREATE TABLE lineage_transition (
  id           serial   PRIMARY KEY,
  lineage_id   integer  NOT NULL REFERENCES lineage(id),
  category_id  integer  NOT NULL REFERENCES lineage(id),
  start_index  integer  NOT NULL
);

-- TODO: lineage joints. Joints coud be used in both proof searching and to
-- join connecting lineages so that further derivations can be started from a
-- commpon point (a joint could initiate a new lineage?).

-- Rule (equation of two expression)
CREATE TABLE rule (
  id                   serial   PRIMARY KEY,
  category_id          integer  NOT NULL REFERENCES category(id),
  left_expression_id   integer  NOT NULL REFERENCES expression(id),
  right_expression_id  integer  NOT NULL REFERENCES expression(id),

  UNIQUE (left_expression_id, right_expression_id)
);

-- A rule definition.
CREATE TABLE definition (
  id       serial   PRIMARY KEY,
  rule_id  integer  NOT NULL UNIQUE REFERENCES rule(id)

  -- TODO: definition subject, theoretical definition/empirical definition
);

-- Function property naming
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

-- Lineage expression
CREATE TABLE lineage_expression (
  id                     serial    PRIMARY KEY,
  lineage_id             integer   NOT NULL REFERENCES lineage(id),
  lineage_index          integer   NOT NULL CHECK (lineage_index > 0),
  rule_id                integer   NOT NULL REFERENCES rule(id),
  expression_id          integer   NOT NULL REFERENCES expression(id),
  substitution_position  smallint  NOT NULL CHECK (substitution_position >= 0),

  -- Including a summed weight is controversial because it is not final. If a
  -- shorter rule proof is proposed later all weights have to be updated.
  --weightsum              integer   NOT NULL,

  UNIQUE (lineage_id, lineage_index)
);

-- Node in a rule proof path node
CREATE TYPE rule_proof_node_direction AS ENUM ('ascend', 'descend');
CREATE TYPE rule_proof_node AS (
  lineage_id   integer,
  direction    rule_proof_node_direction
);

-- A rule proof by path searching.
CREATE TABLE rule_proof (
  id          serial             PRIMARY KEY,
  rule_id     integer            NOT NULL REFERENCES rule(id),
  left_id     integer            NOT NULL REFERENCES lineage_expression(id),
  right_id    integer            NOT NULL REFERENCES lineage_expression(id),
  proof_path  rule_proof_node[]  NOT NULL UNIQUE,

  UNIQUE (left_id, right_id, proof_path)
);

-- Rule translocation
CREATE TABLE translocate (
  id                 serial   PRIMARY KEY,
  rule_id            integer  NOT NULL REFERENCES rule(id),
  in_expression_id   integer  NOT NULL REFERENCES expression(id),
  out_expression_id  integer  NOT NULL REFERENCES expression(id),
  tree_id            integer  NOT NULL REFERENCES lineage_tree(id)
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
-- Create user and restrict access.
--------------------------------------------------------------------------------

REVOKE CONNECT ON DATABASE eqdb FROM public;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM public;

CREATE USER eqpg WITH ENCRYPTED PASSWORD '$password' CONNECTION LIMIT 100;
GRANT CONNECT ON DATABASE eqdb TO eqpg;
GRANT SELECT, INSERT ON ALL TABLES IN SCHEMA public TO eqpg;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public to eqpg;
