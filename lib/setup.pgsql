--------------------------------------------------------------------------------
-- Naming conventions:
-- + Do not use reserved keywords (SQL standard)
-- + Foreign key field names have a '_id' suffix
-- + Do not use abbreviations unless very common or required
--------------------------------------------------------------------------------

CREATE EXTENSION pgcrypto;

--------------------------------------------------------------------------------
-- Categories and expression storage
--------------------------------------------------------------------------------

-- Category
CREATE TABLE category (
  id    serial     PRIMARY KEY,
  path  integer[]  NOT NULL
);

-- Function
CREATE TABLE func (
  id           serial   PRIMARY KEY,
  category_id  integer  REFERENCES category(id) NOT NULL,
  generic      boolean  NOT NULL,
  latex        text     NOT NULL
);

CREATE TYPE expression_reference_type AS ENUM ('function', 'integer');
CREATE TYPE expression_reference AS (
  id              integer,
  reference_type  expression_reference_type
);

-- Expression node
CREATE TABLE expression (
  id         serial                PRIMARY KEY,
  reference  expression_reference  NOT NULL,
  data       bytea                 NOT NULL UNIQUE,
  hash       bytea                 NOT NULL UNIQUE
);

-- Function expression
CREATE TABLE func_reference (
  id         serial                  PRIMARY KEY,
  func_id    integer                 NOT NULL REFERENCES func(id),
  arguments  expression_reference[]  NOT NULL
);

-- Integer expression
CREATE TABLE int_reference (
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

-- Rule (equation of two expression)
CREATE TABLE rule (
  id                serial     PRIMARY KEY,
  left_lineage_id   integer    NOT NULL REFERENCES lineage(id),
  left_index        integer    NOT NULL,
  right_lineage_id  integer    NOT NULL REFERENCES lineage(id),
  right_index       integer    NOT NULL,
  weight            integer    NOT NULL,
  path              integer[]  NOT NULL UNIQUE,

  UNIQUE (left_lineage_id, left_index, right_lineage_id, right_index)
);

-- Lineage expression
CREATE TABLE lineage_expression (
  id             serial   PRIMARY KEY,
  expression_id  integer  NOT NULL REFERENCES expression(id),
  lineage_id     integer  NOT NULL REFERENCES lineage(id),
  lineage_index  integer  NOT NULL,
  weightsum      integer  NOT NULL,
  rule_id        integer           REFERENCES rule(id),

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
  ref       integer,
  ref_type  evaluation_parameter_type
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

CREATE USER eqpg WITH ENCRYPTED PASSWORD '$password';
GRANT CONNECT ON DATABASE eqdb TO eqpg;
GRANT SELECT, INSERT ON ALL TABLES IN SCHEMA public TO eqpg;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public to eqpg;