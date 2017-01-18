--------------------------------------------------------------------------------
-- Naming conventions:
-- + Do not use reserved keywords (SQL standard)
-- + Foreign key field names have a '_id' suffix
-- + Do not use abbreviations unless very common or required
--------------------------------------------------------------------------------

CREATE EXTENSION pgcrypto;

--------------------------------------------------------------------------------
-- Descriptors
--------------------------------------------------------------------------------

-- Descriptor
--
-- Should NOT contain separate records for abbreviations or acronyms.
CREATE TABLE descriptor (
  id  serial  PRIMARY KEY
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
  descriptor_id  integer  NOT NULL UNIQUE REFERENCES descriptor(id),
  locale_id      integer  NOT NULL REFERENCES locale(id),
  content        text     NOT NULL
    CHECK (content ~ E'^(?:[^\\s]+ )*[^\\s]+$') -- Check for repeated spaces in the regex.
);

--------------------------------------------------------------------------------
-- Categories and expression storage
--------------------------------------------------------------------------------

-- Category
CREATE TABLE category (
  id             serial     PRIMARY KEY,
  parents        integer[]  NOT NULL
);

-- Category name: reference decriptor

-- Function
CREATE TABLE function (
  id              serial    PRIMARY KEY,
  category_id     integer   NOT NULL REFERENCES category(id),
  argument_count  smallint  NOT NULL CHECK (argument_count >= 0),
  latex_template  text      NOT NULL,
  generic         boolean   NOT NULL
);

-- Function subfield: reference descriptor
-- Function name: reference descriptor
-- Function tags: reference descriptor
-- Function keywords: reference keyword

-- Operator evaluation (relevant for printing parentheses)
CREATE TYPE read_evaluation_type AS ENUM ('isolated', 'afirst', 'bfirst');

-- Operator configuration
CREATE TABLE operator_configuration (
  id                serial                PRIMARY KEY,
  function_id       integer               NOT NULL UNIQUE REFERENCES function(id),
  precedence_level  smallint              NOT NULL CHECK (precedence_level > 0),
  evaluation_type   read_evaluation_type  NOT NULL
);

-- Inline reference to another expression reference.
CREATE TYPE expression_reference_type AS ENUM ('function', 'integer');
CREATE TYPE expression_reference AS (
  id    integer,
  type  expression_reference_type
);

-- Expression node
CREATE TABLE expression (
  id         serial                PRIMARY KEY,
  reference  expression_reference  NOT NULL,
  data       bytea                 NOT NULL UNIQUE,
  hash       bytea                 NOT NULL UNIQUE
);

-- Function expression reference
CREATE TABLE function_reference (
  id           serial                  PRIMARY KEY,
  function_id  integer                 NOT NULL REFERENCES function(id),
  arguments    expression_reference[]  NOT NULL
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
  parent_id            integer           REFERENCES lineage(id),
  branch_index         integer  NOT NULL DEFAULT 0,
  initial_category_id  integer  NOT NULL REFERENCES category(id)
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
-- commpon point (a joint could automatically transform into a new lineage?).

CREATE TYPE rule_proof_node_direction AS ENUM ('ascend', 'descend');
CREATE TYPE rule_proof_node AS (
  lineage_id   integer,
  direction    rule_proof_node_direction
);

-- Rule (equation of two expression)
-- Note: manually or automatically keep track of alternative proofs?
CREATE TABLE rule (
  id                serial             PRIMARY KEY,
  left_lineage_id   integer            NOT NULL REFERENCES lineage(id),
  left_index        integer            NOT NULL,
  right_lineage_id  integer            NOT NULL REFERENCES lineage(id),
  right_index       integer            NOT NULL,
  weight            integer            NOT NULL,
  proof             rule_proof_node[]  NOT NULL UNIQUE,

  UNIQUE (left_lineage_id, left_index, right_lineage_id, right_index)
);

-- Lineage expression
CREATE TABLE lineage_expression (
  id                     serial    PRIMARY KEY,
  expression_id          integer   NOT NULL REFERENCES expression(id),
  lineage_id             integer   NOT NULL REFERENCES lineage(id),
  lineage_index          integer   NOT NULL,
  weightsum              integer   NOT NULL,
  rule_id                integer            REFERENCES rule(id),
  substitution_position  smallint  NOT NULL CHECK (substitution_position >= 0),

  UNIQUE (lineage_id, lineage_index)
);

-- Rule translocation
CREATE TABLE translocate (
  id                 serial   PRIMARY KEY,
  rule_id            integer  NOT NULL REFERENCES rule(id),
  in_expression_id   integer  NOT NULL REFERENCES expression(id),
  out_expression_id  integer  NOT NULL REFERENCES expression(id),
  tree_id            integer  NOT NULL REFERENCES lineage_tree(id)
);

-- Lineage root definition
CREATE TABLE definition (
  id       serial   PRIMARY KEY,
  tree_id  integer  NOT NULL UNIQUE REFERENCES lineage_tree(id)
);

--------------------------------------------------------------------------------
-- Emperical values and expression evaluation
--------------------------------------------------------------------------------

-- Empirical value reference source
CREATE TABLE empirical_reference (
  id   serial  PRIMARY KEY,
  doi  text    NOT NULL UNIQUE
);

-- Empirical values
CREATE TABLE emperical_value (
  id             serial   PRIMARY KEY,
  val            numeric  NOT NULL UNIQUE,
  expression_id  integer  REFERENCES expression(id),
  reference_id   integer  REFERENCES empirical_reference(id)
);

CREATE TYPE evaluation_parameter_type as ENUM ('empirical', 'computed');
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
