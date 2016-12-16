-- Category
CREATE TABLE category (
	"id"      serial  PRIMARY KEY,
	"parent"  int     REFERENCES category(id) NOT NULL
);

-- Expression superset
CREATE TABLE superset (
	"id" serial PRIMARY KEY
);

-- Expression set
CREATE TABLE eqset (
	"id"        serial  PRIMARY KEY,
	"category"  int     REFERENCES category(id) NOT NULL,
	"superset"  int     REFERENCES superset(id) NOT NULL
);

-- Set alias
CREATE TABLE alias (
	"id"   serial  PRIMARY KEY,
	"src"  int     REFERENCES eqset(id) NOT NULL,
	"dst"  int     REFERENCES eqset(id) NOT NULL
);

-- Function
CREATE TABLE function (
	"id"         serial  PRIMARY KEY,
	"category"   int     REFERENCES category(id) NOT NULL,
	"agcount"    int     NOT NULL,
	"asciiname"  text    NOT NULL UNIQUE,
	"latex"      text    NOT NULL
);

-- Defenition
CREATE TABLE definition (
	"id"        serial  PRIMARY KEY,
	"category"  int     REFERENCES category(id)  NOT NULL,
	"left"      int     REFERENCES eqset(id)     NOT NULL,
	"right"     int     REFERENCES eqset(id)     NOT NULL
);

-- Expression
CREATE TABLE expression (
	"id"    serial  PRIMARY KEY,
	"set"   int     REFERENCES eqset(id) NOT NULL,
	"data"  bytea   NOT NULL UNIQUE
);

-- Numeric data
CREATE TABLE number (
	"id"     serial  PRIMARY KEY,
	"value"  float8  NOT NULL UNIQUE
);

-- Numeric expression
CREATE TABLE numexpr (
	"id"      serial  PRIMARY KEY,
	"expr"    int     REFERENCES expression(id)  NOT NULL UNIQUE,
	"number"  int     REFERENCES number(id)      NOT NULL
);

-- Function expression
CREATE TABLE fnexpr (
	"id"    serial  PRIMARY KEY,
	"expr"  int     REFERENCES expression(id)  NOT NULL UNIQUE,
	"fn"    int     REFERENCES function(id)    NOT NULL
);

-- Function expression arguments
CREATE TABLE fnargs (
	"id"    serial  PRIMARY KEY,
	"fn"    int     REFERENCES fnexpr(id)      NOT NULL,
	"expr"  int     REFERENCES expression(id)  NOT NULL,
	"argi"  int     NOT NULL
);

-- Expression transformation
CREATE TABLE transform (
	"id"      serial  PRIMARY KEY,
	"src"     int     REFERENCES expression(id)  NOT NULL,
	"dst"     int     REFERENCES expression(id)  NOT NULL,
	"input"   int     REFERENCES expression(id)  NOT NULL,
	"output"  int     REFERENCES expression(id)  NOT NULL
);

-- Transformation output values
CREATE TABLE transformval (
	"id"         serial  PRIMARY KEY,
	"transform"  int     REFERENCES transform(id)   NOT NULL,
	"function"   int     REFERENCES function(id)    NOT NULL,
	"value"      int     REFERENCES expression(id)  NOT NULL
);
