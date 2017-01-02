CREATE TYPE expression_type AS ENUM ('number', 'function', 'symbol');
CREATE TYPE expression_link AS (
  id    int,
  type  expression_type
);

CREATE SEQUENCE expression_sequence;

-- Category
CREATE TABLE category (
  id      serial  PRIMARY KEY,
  parent  int     REFERENCES category(id) NOT NULL
);

-- Global expression set
CREATE TABLE global_set (
  id serial PRIMARY KEY
);

-- Category expression set
CREATE TABLE category_set (
  id        serial  PRIMARY KEY,
  category  int     REFERENCES category(id) NOT NULL,
  parent    int     REFERENCES global_set(id) NOT NULL
);

-- Set alias (merge sets when they collide)
CREATE TABLE alias (
  id   serial  PRIMARY KEY,
  src  int     REFERENCES category_set(id) NOT NULL,
  dst  int     REFERENCES category_set(id) NOT NULL
);

-- Function
CREATE TABLE function (
  id         serial  PRIMARY KEY,
  generic    bool    NOT NULL,
  category   int     REFERENCES category(id) NOT NULL,
  argcount   int     NOT NULL,
  latex      text    NOT NULL
);

-- Defenition
CREATE TABLE definition (
  id           serial           PRIMARY KEY,
  category_id  int              NOT NULL REFERENCES category(id),
  left_id      expression_link  NOT NULL,
  right_id     expression_link  NOT NULL
);

-- Numeric data
CREATE TABLE number (
  id    serial  PRIMARY KEY,
  data  float8  NOT NULL UNIQUE
);

-- Number expression
CREATE TABLE number_expression (
  id      int  NOT NULL DEFAULT nextval('expression_sequence'),
  number  int  NOT NULL REFERENCES number(id)
);

-- Function expression
CREATE TABLE function_expression (
  id      int  NOT NULL DEFAULT nextval('expression_sequence'),
  fn      int  NOT NULL REFERENCES function(id),
  args    expression_link[]
);

-- Symbol expression
CREATE TABLE symbol_expression (
  id      int  NOT NULL DEFAULT nextval('expression_sequence'),
  fn      int  NOT NULL REFERENCES function(id)
);

-- Expression transformation
CREATE TABLE transform (
	id      serial           PRIMARY KEY,
	src     expression_link  NOT NULL,
	dst     expression_link  NOT NULL,
	input   expression_link  NOT NULL,
	output  expression_link  NOT NULL
);
