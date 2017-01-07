CREATE EXTENSION pgcrypto;

CREATE TYPE expression_ref AS ENUM ('function', 'integer');
CREATE TYPE expression_link AS (
  id   integer,
  ref  expression_ref
);

CREATE TYPE eval_param_type as ENUM ('empirical', 'computed');
CREATE TYPE eval_param AS (
  ref       integer,
  ref_type  eval_param_type
);

CREATE SEQUENCE expression_sequence;

-- Category
CREATE TABLE category (
  id      serial   PRIMARY KEY,
  parent  integer  REFERENCES category(id)
);

-- Global expression set
CREATE TABLE global_set (
  id  serial  PRIMARY KEY
);

-- Category expression set
CREATE TABLE category_set (
  id        serial   PRIMARY KEY,
  category  integer  REFERENCES category(id) NOT NULL,
  parent    integer  REFERENCES global_set(id) NOT NULL
);

-- Category set link (merge sets when they collide)
CREATE TABLE category_set_link (
  id   serial   PRIMARY KEY,
  src  integer  REFERENCES category_set(id) NOT NULL,
  dst  integer  REFERENCES category_set(id) NOT NULL
);

-- Function
CREATE TABLE fn (
  id         serial   PRIMARY KEY,
  category   integer  REFERENCES category(id) NOT NULL,
  generic    boolean  NOT NULL,
  latex      text     NOT NULL
);

-- Defenition
CREATE TABLE definition (
  id          serial           PRIMARY KEY,
  category    integer          NOT NULL REFERENCES category(id),
  left_expr   expression_link  NOT NULL,
  right_expr  expression_link  NOT NULL,

  UNIQUE (left_expr, right_expr)
);

-- Expression node
--
-- In theory, the id is equal to the expression id in the referenced table. When
-- a new fn_ref or int_ref is created, a new expression node should also be
-- created. Special measures need to be taken to prevent disalignment.
CREATE TABLE expression (
  id    serial           PRIMARY KEY,
  ref   expression_ref   NOT NULL,
  data  bytea            NOT NULL UNIQUE,
  hash  bytea            NOT NULL UNIQUE,
  cset  integer          REFERENCES category_set(id)
);

-- Function expression
CREATE TABLE fn_ref (
  id    integer            NOT NULL DEFAULT nextval('expression_sequence'),
  fn    integer            NOT NULL REFERENCES fn(id),
  args  expression_link[]  NOT NULL
);

-- Integer expression
CREATE TABLE int_ref (
  id   integer  NOT NULL DEFAULT nextval('expression_sequence'),
  num  integer  NOT NULL
);

-- Expression transformation
CREATE TABLE transform (
	id      serial           PRIMARY KEY,
	src     expression_link  NOT NULL,
	dst     expression_link  NOT NULL,
	input   expression_link  NOT NULL,
	output  expression_link  NOT NULL,

  UNIQUE (src, dst)
);

-- Empirical values
CREATE TABLE emperical_value (
  id    serial   PRIMARY KEY,
  val   number   NOT NULL UNIQUE,
  expr  integer  REFERENCES expression(id),
  rnf   integer  REFERENCES empirical_reference(id)
);

-- Empirical value reference source
CREATE TABLE empirical_reference (
  id   serial  PRIMARY KEY,
  doi  text    NOT NULL UNIQUE
);

-- Expression evaluation
CREATE TABLE evaluation (
  id      serial            PRIMARY KEY,
  expr    integer           NOT NULL REFERENCES expression(id),
  params  eval_param[]      NOT NULL,
  result  double precision  NOT NULL,
);

-- Expression pair (must be in the same global set) that is linked to a page.
CREATE TABLE expr_pair (
  id          serial   PRIMARY KEY,
  left_expr   integer  NOT NULL REFERENCES expression(id),
  right_expr  integer  NOT NULL REFERENCES expression(id)
);

-- Expression pair page
CREATE TABLE expr_page (
  id    serial   PRIMARY KEY,
  pair  integer  NOT NULL REFERENCES expr_pair(id)
);

-- Expression pair page row
CREATE TABLE expr_page_row (
  id    serial   PRIMARY KEY,
  page  integer  NOT NULL REFERENCES expr_page(id),
  seq   integer  NOT NULL,

  UNIQUE (page, seq)
);