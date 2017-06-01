--
-- PostgreSQL database cluster dump
--

SET default_transaction_read_only = off;

SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;

--
-- Drop databases
--

DROP DATABASE eqdb;




--
-- Drop roles
--

DROP ROLE eqdb;
DROP ROLE postgres;


--
-- Roles
--

CREATE ROLE eqdb;
ALTER ROLE eqdb WITH NOSUPERUSER INHERIT NOCREATEROLE NOCREATEDB LOGIN NOREPLICATION NOBYPASSRLS CONNECTION LIMIT 100 PASSWORD 'md564d44010a70520d4af7c2c4e08dc8c98';
CREATE ROLE postgres;
ALTER ROLE postgres WITH SUPERUSER INHERIT CREATEROLE CREATEDB LOGIN REPLICATION BYPASSRLS PASSWORD 'md5bed9ea18f44fe0aeb26a86b75fe6a725';






--
-- Database creation
--

CREATE DATABASE eqdb WITH TEMPLATE = template0 OWNER = postgres;
REVOKE CONNECT,TEMPORARY ON DATABASE eqdb FROM PUBLIC;
GRANT CONNECT ON DATABASE eqdb TO eqdb;
GRANT TEMPORARY ON DATABASE eqdb TO PUBLIC;
REVOKE CONNECT,TEMPORARY ON DATABASE template1 FROM PUBLIC;
GRANT CONNECT ON DATABASE template1 TO PUBLIC;


\connect eqdb

SET default_transaction_read_only = off;

--
-- PostgreSQL database dump
--

-- Dumped from database version 9.6.2
-- Dumped by pg_dump version 9.6.2

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: plperl; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS plperl WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plperl; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION plperl IS 'PL/Perl procedural language';


--
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


SET search_path = public, pg_catalog;

--
-- Name: expression_type; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE expression_type AS ENUM (
    'integer',
    'function',
    'generic'
);


ALTER TYPE expression_type OWNER TO postgres;

--
-- Name: keyword_type; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE keyword_type AS ENUM (
    'word',
    'acronym',
    'abbreviation',
    'symbol',
    'latex'
);


ALTER TYPE keyword_type OWNER TO postgres;

--
-- Name: operator_associativity; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE operator_associativity AS ENUM (
    'ltr',
    'rtl'
);


ALTER TYPE operator_associativity OWNER TO postgres;

--
-- Name: operator_type; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE operator_type AS ENUM (
    'prefix',
    'infix',
    'postfix'
);


ALTER TYPE operator_type OWNER TO postgres;

--
-- Name: step_type; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE step_type AS ENUM (
    'set',
    'copy_rule',
    'copy_proof',
    'rule_normal',
    'rule_invert',
    'rule_mirror',
    'rule_revert',
    'rearrange'
);


ALTER TYPE step_type OWNER TO postgres;

--
-- Name: clear_expression_latex(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION clear_expression_latex() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  UPDATE expression SET latex = NULL WHERE functions @> ARRAY[NEW.id]::integer[];
  RETURN NULL;
END;
$$;


ALTER FUNCTION public.clear_expression_latex() OWNER TO postgres;

--
-- Name: expr_match_rule(integer[], integer[], integer[], integer[], integer[]); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION expr_match_rule(integer[], integer[], integer[], integer[], integer[]) RETURNS boolean
    LANGUAGE plperl
    AS $_$
my $EXPR_INTEGER       = 1;
my $EXPR_SYMBOL        = 2;
my $EXPR_SYMBOL_GEN    = 3;
my $EXPR_FUNCTION      = 4;
my $EXPR_FUNCTION_GEN  = 5;

my $expr_hash_mix = sub {
  my ($hash, $value) = @_;
  $hash = 0x1fffffff & ($hash + $value);
  $hash = 0x1fffffff & ($hash + ((0x0007ffff & $hash) << 10));
  $hash = $hash ^ ($hash >> 6);
  return $hash;
};

my $expr_hash_postprocess = sub {
  my ($hash) = @_;
  $hash = 0x1fffffff & ($hash + ((0x03ffffff & $hash) << 3));
  $hash = $hash ^ ($hash >> 11);
  return 0x1fffffff & ($hash + ((0x00003fff & $hash) << 15));
};

# Compute hash for the given part of the expression data array. Replacing all
# hashes that are in the mapping with the mapped hashes.
my $compute_mapped_hash;
$compute_mapped_hash = sub {
  my ($ptr, $mapping_hash, $data) = @_;

  my $hash = $data->[$ptr++];
  my $type = $data->[$ptr++];
  my $value = $data->[$ptr++];

  if (exists $$mapping_hash{$hash}) {
    return ($$mapping_hash{$hash}, $ptr);
  } elsif ($type == $EXPR_FUNCTION || $type == $EXPR_FUNCTION_GEN) {
    # Hash all arguments together.
    my $argc = $data->[$ptr];
    $ptr += 2;

    $hash = 0;
    $hash = $expr_hash_mix->($hash, $type);
    $hash = $expr_hash_mix->($hash, $value);

    while ($argc > 0) {
      $argc--;
      (my $arg_hash, $ptr) = $compute_mapped_hash->($ptr, $mapping_hash, $data);
      $hash = $expr_hash_mix->($hash, $arg_hash);
    }

    $hash = $expr_hash_postprocess->($hash);
    $hash = ($hash << 1) & 0x3fffffff;
    return ($hash, $ptr);
  } else {
    return ($hash, $ptr);
  }
};

# Evaluate function using the given mapping.
my $evaluate = sub {
  my ($ptr, $mapping_hash, $computable_ids, $data) = @_;
  my ($id_add, $id_sub, $id_mul, $id_neg) = @$computable_ids;

  # The stack consists of alternating values: (function ID, 0) or (integer, 1).
  my @stack;

  while (1) {
    my $hash = $data->[$ptr++];
    my $type = $data->[$ptr++];
    my $value = $data->[$ptr++];

    if ($type == $EXPR_SYMBOL_GEN || $type == $EXPR_INTEGER) {
      my $argument = $value; # Valid for $type == $EXPR_INTEGER.

      if ($type == $EXPR_SYMBOL_GEN) {
        if (exists($$mapping_hash{$hash})) {
          my $target = $$mapping_hash{$hash};

          # Reconstruct integer value.
          if ($target & 0x1 == 1) {
            $argument = $target >> 2;
            if (($target >> 1) & 0x1 == 1) {
              $argument = -$argument;
            }
          } else {
            # If the generic does not point to an integer, terminate.
            return (undef, $ptr);
          }
        } else {
          return (undef, $ptr);
        }
      }

      # We use the usefull fact that all computable functions have exactly
      # two arguments.
      # We can assume there are elements in the stack at this point since
      # this function is called with the pointer pointing to a function
      # first.
      if ($stack[-1] == 1) {
        # Collapse stack.
        do {
          pop(@stack);                    # Remove first argument flag [1].
          my $other = pop(@stack);        # Get other integer.
          pop(@stack);                    # Remove computation flag [0].
          my $computation = pop(@stack);  # Get computation ID.

          # Do computation.
          if ($computation == $id_add)    { $argument = $other + $argument; }
          elsif ($computation == $id_sub) { $argument = $other - $argument; }
          elsif ($computation == $id_mul) { $argument = $other * $argument; }
          elsif ($computation == $id_neg) { $argument = -$argument; }

        } while (@stack && $stack[-1] == 1);

        # If the stack is empty, return the result.
        if (!@stack) {
          return ($argument, $ptr);
        } else {
          push(@stack, $argument, 1);
        }
      } else {
        # This is the first argument of the lowest computation in the stack.
        push(@stack, $argument, 1);
      }
    } elsif ($type == $EXPR_FUNCTION) {
      if ($value == $id_add || $value == $id_sub ||
          $value == $id_mul || $value == $id_neg) {
        # Push function ID to stack.
        push(@stack, $value, 0);

        # Skip argument count and content-length (we know the argument length of
        # all computable functions ahead of time).
        $ptr += 2;

        # If this is the negation function, add a first argument here as an
        # imposter. This way the negation function can be integrated in the same
        # code as the binary operators.
        if ($value == $id_neg) {
          push(@stack, 0, 1);
        }
      } else {
        return (undef, $ptr);
      }
    } else {
      return (undef, $ptr);
    }
  }

  # This point will not be reached.
};

# Recursive expression pattern matching.
my $match_pattern;
$match_pattern = sub {
  my ($write_mapping, $internal_remap, $mapping_hash, $mapping_genfn,
      $ptr_t, $ptr_p, $computable_ids, @data) = @_;

  my $argc = 1; # arguments left to be processed.

  # Iterate through data untill out of arguments.
  # Returns success if loop completes. If a mismatch is found the function
  # should be terminated directly.
  while ($argc > 0) {
    $argc--;

    my $hash_t = $data[$ptr_t++];
    my $hash_p = $data[$ptr_p++];
    my $type_t = $data[$ptr_t++];
    my $type_p = $data[$ptr_p++];
    my $value_t = $data[$ptr_t++];
    my $value_p = $data[$ptr_p++];

    if ($type_p == $EXPR_SYMBOL_GEN) {
      if (!$write_mapping || exists($$mapping_hash{$hash_p})) {
        if ($$mapping_hash{$hash_p} != $hash_t) {
          return 0;
        }
      } else {
        $$mapping_hash{$hash_p} = $hash_t;
      }

      # Jump over function body.
      if ($type_t == $EXPR_FUNCTION || $type_t == $EXPR_FUNCTION_GEN) {
        $ptr_t += 2 + $data[$ptr_t + 1];
      }      
    } elsif ($type_p == $EXPR_FUNCTION_GEN) {
      if (!$write_mapping) {
        # Internal remapping.
        if ($internal_remap) {
          # Disallow generic functions in internal remapping.
          return 0;
        }

        # Retrieve pointers.
        my $ptrs = $$mapping_genfn{$value_p};
        my $mptr_t = $$ptrs[0];
        my $pattern_arg_hash = $$ptrs[2];
        my $pattern_arg_target_hash = $$mapping_hash{$pattern_arg_hash};

        # Compute hash for internal substitution.
        # Overhead of running this when there is no difference is minimal.
        my @result = $compute_mapped_hash->($ptr_p + 2, $mapping_hash, \@data);
        my $computed_hash = $result[0];

        # Deep compare if the computed hash is different.
        if ($computed_hash != $pattern_arg_target_hash) {
          # Temporarily add hash to mapping.
          my $old_hash = $$mapping_hash{$pattern_arg_target_hash};
          $$mapping_hash{$pattern_arg_target_hash} = $computed_hash;

          # Old expression is used as pattern, current expression as target.
          if (!$match_pattern->(0, 1, $mapping_hash, $mapping_genfn,
              $ptr_t - 3, $mptr_t, $computable_ids, @data)) {
            return 0;
          }

          # Restore old mapping.
          $$mapping_hash{$pattern_arg_target_hash} = $old_hash;
        } else {
          # Shallow compare.
          if ($$mapping_hash{$hash_p} != $hash_t) {
            return 0;
          }
        }
      } else {
        # Validate against existing mapping hash.
        if (exists $$mapping_hash{$hash_p}) {
          if ($$mapping_hash{$hash_p} != $hash_t) {
            return 0;
          }
        } else {
          $$mapping_hash{$hash_p} = $hash_t;

          # Add expression pointer to mapping for later use.
          # Both pointers point at the start of the expression.
          $$mapping_genfn{$value_p} = [$ptr_t - 3, $ptr_p - 3];
        }
      }

      # Jump over function body.
      # Generic functions operating on generic functions are actually bullshit.
      if ($type_t == $EXPR_FUNCTION || $type_t == $EXPR_FUNCTION_GEN) {
        $ptr_t += 2 + $data[$ptr_t + 1];
      }
      $ptr_p += 2 + $data[$ptr_p + 1];
    } elsif ($type_p == $EXPR_SYMBOL) {
      # Check interal remapping caused by generic functions.
      if ($internal_remap && exists $$mapping_hash{$hash_p}) {
        if ($$mapping_hash{$hash_p} != $hash_t) {
          return 0;
        } else {
          # The symbol is in the mapping and matches the given hash. It is
          # possible that the target is a function so now we need to jump over
          # its function body.
          if ($type_t == $EXPR_FUNCTION || $type_t == $EXPR_FUNCTION_GEN) {
            $ptr_t += 2 + $data[$ptr_t + 1];
          }
        }
      } else {
        if ($type_t != $EXPR_SYMBOL || $value_t != $value_p) {
          return 0;
        }
      }
    } elsif ($type_p == $EXPR_FUNCTION) {  
      if ($type_t == $EXPR_FUNCTION) {
        if ($value_t == $value_p) {
          my $argc_t = $data[$ptr_t++];
          my $argc_p = $data[$ptr_p++];

          # Both functions must have the same number of arguments.
          if ($argc_t == $argc_p) {
            # Skip content-length.
            $ptr_t++;
            $ptr_p++;

            # Add argument count to the total.
            $argc += $argc_p;
          } else {
            # Different number of arguments.
            return 0;
          }
        } else {
          # Function IDs do not match.
          return 0;
        }
      } elsif (!$write_mapping && !$internal_remap && $type_t == $EXPR_INTEGER) {
        # Note: we do not run this during internal remapping to avoid
        # complicated cases with difficult behavior.

        # Check if pattern function can be evaluated to the same integer as the
        # target expression.
        my ($evaluated_value, $ptr_t) = $evaluate->($ptr_p - 3, $mapping_hash,
            $computable_ids, \@data);

        if (!defined($evaluated_value) || $value_t != $evaluated_value) {
          return 0;
        } else {
          # Jump over function body.
          $ptr_p += 2 + $data[$ptr_p + 1];
        }
      } else {
        # Expression is not also a function or an integer.
        return 0;
      }
    } elsif ($type_p == $EXPR_INTEGER) {
      # Integers are not very common in patterns. Therefore this is checked
      # last.
      if ($type_t != $EXPR_INTEGER || $value_t != $value_p) {
        return 0;
      }
    } else {
      # Unknown expression type.
      return 0;
    }
  }

  # Also return pointer value.
  return (1, $ptr_t, $ptr_p);
};

# Rule matching
# It is possible to put match_pattern inside this function for some very minimal
# gain (arguments do not have to be copied).
my $expr_match_rule = sub {
  my ($expr_left, $expr_right, $rule_left, $rule_right, $computable_ids) = @_;
  my (%mapping_hash, %mapping_genfn);
  my $ptr_t = 0;
  my $ptr_p = scalar(@$expr_left) + scalar(@$expr_right);
  my @data = (@$expr_left, @$expr_right, @$rule_left, @$rule_right);

  (my $result_left, $ptr_t, $ptr_p) = $match_pattern->(1, 0,
      \%mapping_hash, \%mapping_genfn, $ptr_t, $ptr_p, $computable_ids, @data);
  if (!$result_left) {
    return 0;
  }

  # Process generic function mapping.
  foreach my $ptrs (values %mapping_genfn) {
    my $mptr_t = $$ptrs[0];
    my $mptr_p = $$ptrs[1];

    # Get hash of first argument of pattern function.
    # This first argument should be generic.
    my $pattern_arg_hash = $data[$mptr_p + 5];
    push @$ptrs, $pattern_arg_hash;

    # If no target hash exists and the expression function has 1 argument, the
    # generic is mapped to that argument.
    if (!exists $mapping_hash{$pattern_arg_hash}) {
      if ($data[$mptr_t + 3] == 1) {
        # Map pattern argument to hash of first expression argument.
        my $hash = $data[$mptr_t + 5];
        $mapping_hash{$pattern_arg_hash} = $hash;
      } else {
        # Argument count not 1, and no target hash exists. So terminate.
        return 0;
      }
    }
  }

  my ($result_right) = $match_pattern->(0, 0, \%mapping_hash, \%mapping_genfn,
      $ptr_t, $ptr_p, $computable_ids, @data);
  return $result_right;
};

return $expr_match_rule->(@_);
$_$;


ALTER FUNCTION public.expr_match_rule(integer[], integer[], integer[], integer[], integer[]) OWNER TO postgres;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: descriptor; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE descriptor (
    id integer NOT NULL
);


ALTER TABLE descriptor OWNER TO postgres;

--
-- Name: descriptor_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE descriptor_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE descriptor_id_seq OWNER TO postgres;

--
-- Name: descriptor_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE descriptor_id_seq OWNED BY descriptor.id;


--
-- Name: expression; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE expression (
    id integer NOT NULL,
    data bytea NOT NULL,
    hash bytea NOT NULL,
    latex text,
    functions integer[] NOT NULL,
    node_type expression_type NOT NULL,
    node_value integer NOT NULL,
    node_arguments integer[] NOT NULL
);


ALTER TABLE expression OWNER TO postgres;

--
-- Name: expression_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE expression_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE expression_id_seq OWNER TO postgres;

--
-- Name: expression_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE expression_id_seq OWNED BY expression.id;


--
-- Name: function; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE function (
    id integer NOT NULL,
    subject_id integer NOT NULL,
    descriptor_id integer,
    generic boolean NOT NULL,
    rearrangeable boolean NOT NULL,
    argument_count smallint NOT NULL,
    keyword text,
    keyword_type keyword_type,
    latex_template text,
    CONSTRAINT function_argument_count_check CHECK ((argument_count >= 0)),
    CONSTRAINT function_check CHECK (((NOT generic) OR (argument_count < 2))),
    CONSTRAINT function_check1 CHECK ((NOT (rearrangeable AND (argument_count < 2)))),
    CONSTRAINT function_keyword_check CHECK ((keyword ~ '^[a-z]+[0-9]*$'::text)),
    CONSTRAINT function_latex_template_check CHECK (((latex_template = ''::text) IS NOT TRUE)),
    CONSTRAINT keyword_must_have_type CHECK ((((keyword IS NULL) AND (keyword_type IS NULL)) OR ((keyword IS NOT NULL) AND (keyword_type IS NOT NULL)))),
    CONSTRAINT must_have_keyword_or_template CHECK (((keyword IS NOT NULL) OR (latex_template IS NOT NULL))),
    CONSTRAINT non_generic_with_args_needs_name CHECK ((NOT ((NOT generic) AND (argument_count > 0) AND (descriptor_id IS NULL))))
);


ALTER TABLE function OWNER TO postgres;

--
-- Name: function_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE function_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE function_id_seq OWNER TO postgres;

--
-- Name: function_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE function_id_seq OWNED BY function.id;


--
-- Name: language; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE language (
    id integer NOT NULL,
    code text NOT NULL,
    CONSTRAINT language_code_check CHECK ((code ~ '^[a-z]{2}(_([a-zA-Z]{2}){1,2})?_[A-Z]{2}$'::text))
);


ALTER TABLE language OWNER TO postgres;

--
-- Name: language_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE language_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE language_id_seq OWNER TO postgres;

--
-- Name: language_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE language_id_seq OWNED BY language.id;


--
-- Name: operator; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE operator (
    id integer NOT NULL,
    function_id integer NOT NULL,
    precedence_level smallint NOT NULL,
    associativity operator_associativity NOT NULL,
    operator_type operator_type NOT NULL,
    "character" character(1) NOT NULL,
    editor_template text NOT NULL,
    CONSTRAINT operator_precedence_level_check CHECK ((precedence_level > 0))
);


ALTER TABLE operator OWNER TO postgres;

--
-- Name: operator_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE operator_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE operator_id_seq OWNER TO postgres;

--
-- Name: operator_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE operator_id_seq OWNED BY operator.id;


--
-- Name: proof; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE proof (
    id integer NOT NULL,
    first_step_id integer NOT NULL,
    last_step_id integer NOT NULL
);


ALTER TABLE proof OWNER TO postgres;

--
-- Name: proof_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE proof_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE proof_id_seq OWNER TO postgres;

--
-- Name: proof_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE proof_id_seq OWNED BY proof.id;


--
-- Name: rule; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE rule (
    id integer NOT NULL,
    step_id integer,
    proof_id integer,
    is_definition boolean NOT NULL,
    left_expression_id integer NOT NULL,
    right_expression_id integer NOT NULL,
    left_array_data integer[] NOT NULL,
    right_array_data integer[] NOT NULL,
    CONSTRAINT left_is_not_right CHECK ((left_expression_id <> right_expression_id)),
    CONSTRAINT step_or_proof_or_definition CHECK (((step_id IS NOT NULL) OR (proof_id IS NOT NULL) OR (is_definition IS TRUE)))
);


ALTER TABLE rule OWNER TO postgres;

--
-- Name: rule_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE rule_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rule_id_seq OWNER TO postgres;

--
-- Name: rule_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE rule_id_seq OWNED BY rule.id;


--
-- Name: step; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE step (
    id integer NOT NULL,
    previous_id integer,
    expression_id integer NOT NULL,
    "position" smallint NOT NULL,
    step_type step_type NOT NULL,
    proof_id integer,
    rule_id integer,
    rearrange smallint[],
    CONSTRAINT step_position_check CHECK (("position" >= 0)),
    CONSTRAINT valid_type CHECK ((((previous_id = NULL::integer) AND (step_type = 'set'::step_type)) OR ((previous_id <> NULL::integer) AND (((step_type = 'copy_proof'::step_type) AND (proof_id IS NOT NULL)) OR ((step_type = 'rearrange'::step_type) AND (rearrange IS NOT NULL)) OR (rule_id IS NOT NULL)))))
);


ALTER TABLE step OWNER TO postgres;

--
-- Name: step_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE step_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE step_id_seq OWNER TO postgres;

--
-- Name: step_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE step_id_seq OWNED BY step.id;


--
-- Name: subject; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE subject (
    id integer NOT NULL,
    descriptor_id integer NOT NULL
);


ALTER TABLE subject OWNER TO postgres;

--
-- Name: subject_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE subject_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE subject_id_seq OWNER TO postgres;

--
-- Name: subject_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE subject_id_seq OWNED BY subject.id;


--
-- Name: translation; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE translation (
    id integer NOT NULL,
    descriptor_id integer NOT NULL,
    language_id integer NOT NULL,
    content text NOT NULL,
    CONSTRAINT translation_content_check CHECK ((content ~ '^(?:[^\s]+ )*[^\s]+$'::text))
);


ALTER TABLE translation OWNER TO postgres;

--
-- Name: translation_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE translation_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE translation_id_seq OWNER TO postgres;

--
-- Name: translation_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE translation_id_seq OWNED BY translation.id;


--
-- Name: descriptor id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY descriptor ALTER COLUMN id SET DEFAULT nextval('descriptor_id_seq'::regclass);


--
-- Name: expression id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY expression ALTER COLUMN id SET DEFAULT nextval('expression_id_seq'::regclass);


--
-- Name: function id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY function ALTER COLUMN id SET DEFAULT nextval('function_id_seq'::regclass);


--
-- Name: language id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY language ALTER COLUMN id SET DEFAULT nextval('language_id_seq'::regclass);


--
-- Name: operator id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY operator ALTER COLUMN id SET DEFAULT nextval('operator_id_seq'::regclass);


--
-- Name: proof id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY proof ALTER COLUMN id SET DEFAULT nextval('proof_id_seq'::regclass);


--
-- Name: rule id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY rule ALTER COLUMN id SET DEFAULT nextval('rule_id_seq'::regclass);


--
-- Name: step id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY step ALTER COLUMN id SET DEFAULT nextval('step_id_seq'::regclass);


--
-- Name: subject id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY subject ALTER COLUMN id SET DEFAULT nextval('subject_id_seq'::regclass);


--
-- Name: translation id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY translation ALTER COLUMN id SET DEFAULT nextval('translation_id_seq'::regclass);


--
-- Data for Name: descriptor; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY descriptor (id) FROM stdin;
1
2
3
4
5
6
7
8
9
10
11
12
13
14
15
16
17
18
19
20
21
22
23
24
25
26
27
28
29
30
31
32
33
\.


--
-- Name: descriptor_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('descriptor_id_seq', 33, true);


--
-- Data for Name: expression; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY expression (id, data, hash, latex, functions, node_type, node_value, node_arguments) FROM stdin;
1	\\x000000000100010009000000000000	\\x43015c596372b689f4f4cefecd30ec1668862206980cb58d65afb225d9c9cbe1	{}_\\text{?}a	{9}	generic	9	{}
156	\\x0000010006000100000000000a000000020000000400000024000000190000002300000000000200020000000200000001060203040500	\\x3ecbfb4016aa4c85ea2183f052359ef568e6f73f36dcacff607d08bbd9f3f290	\N	{10,2,4,36,25,35}	function	2	{25,152}
89	\\x000000000300010009000000190000000e000000000002000000010002	\\x1f8c52915d64d9b999c2333e75ca5255c4142a8f0a977fe71a63355de13db6a6	\\frac{\\partial}{\\partial{}_\\text{?}a}\\hat{e_2}	{9,25,14}	function	25	{1,50}
171	\\x0000010006000200000000000a00000009000000020000000400000007000000190000000000000002000200010002000203060004050100	\\x42b7b23cd171892878e64dc86f1d25c9e27a551ca6a321ec02d950cbcb0ed57b	0{}_\\text{?}b+-\\frac{\\partial}{\\partial{}_\\text{?}a}{}_\\text{?}b	{10,9,2,4,7,25}	function	2	{154,159}
15	\\x00000100030001000100000009000000040000000700000000000200010001020300	\\x7868708f462030521b1f3b26b9818bac00b5429f492f4a5a295135be1c9c34f4	-1{}_\\text{?}a	{9,4,7}	function	4	{14,1}
175	\\x0000000006000200090000000a0000000400000019000000070000001300000000000000020002000100010002030001040501	\\xb171bb99073fa45f4ef7458e63b24fa1cbcd735a1c682cb1360ce5f4fdf16e82	\\left(\\frac{\\partial}{\\partial{}_\\text{?}a}{}_\\text{?}b\\right)\\left(-\\cos{}_\\text{?}b\\right)	{9,10,4,25,7,19}	function	4	{69,174}
2	\\x00000000010001000a000000000000	\\x7411a5ca9021c1572527e434ecfc5439b308a4c41d55e3ee2ce343cf960f5eb4	\N	{10}	generic	10	{}
7	\\x00000000010001000b000000000000	\\x81e70705060646c78a583ab14aabcd545598cbcd420c7973aba1675c2e8b705f	\N	{11}	generic	11	{}
13	\\x00000100000000000100000000	\\xcb8c6ede8e7aef082d6b7f80058cc9b51caf8daeea698e065be21383c51065fc	\N	{}	integer	1	{}
21	\\x000000000100010014000000000000	\\xa87b85903b7498010c55645a4a6c27c9309925173a6177bdcb37e9f6e4354ef2	\N	{20}	generic	20	{}
22	\\x00000000020002001600000014000000010000000001	\\xf7ad21a772c67ff2678b7e83ba90a5b962cc5487adbba18b082688cc387d7ffe	\N	{22,20}	generic	22	{21}
104	\\x0000000005000300090000000a0000000b000000190000001b000000000000000000020002000300040102	\\x59de0b5837f49e86fb623beeb4c45e1be164541380d3475e90a845e06c3ca355	\\frac{\\partial}{\\partial{}_\\text{?}a}\\left(\\begin{matrix}{}_\\text{?}b\\\\{}_\\text{?}c\\end{matrix}\\right)	{9,10,11,25,27}	function	25	{1,65}
47	\\x0000000003000200090000000a0000001b000000000000000200020001	\\x5401ec9a4f5b907348a9e9951e0510da6565c3bbf30e64d1196fb9362d97e8b1	\\left(\\begin{matrix}{}_\\text{?}a\\\\{}_\\text{?}b\\end{matrix}\\right)	{9,10,27}	function	27	{1,2}
107	\\x0000000008000300090000000a0000000b0000000200000019000000040000000d0000000e000000000000000000020002000200000000000304000501060400050207	\\x75f6533aa101ba4567204b690379f7b1b5419b67dbffad4acacd739266f0e5e1	\\frac{\\partial}{\\partial{}_\\text{?}a}{}_\\text{?}b\\hat{e_1}+\\frac{\\partial}{\\partial{}_\\text{?}a}{}_\\text{?}c\\hat{e_2}	{9,10,11,2,25,4,13,14}	function	2	{91,106}
153	\\x00000000060001000a00000002000000040000001900000023000000240000000000020002000200000000000102030405000205030400	\\xe0df99c262f781268612e846b101d91fd47e6e207c9c5babc23af1549a0dee18	\N	{10,2,4,25,35,36}	function	2	{150,152}
169	\\x0000010005000200ffffffff090000000a000000020000000400000019000000000000000200020002000203040005010305040001	\\x3f2a296bdf903533a55741c15603f014350ffbed3db81eda520a22b190852aec	\\left(\\frac{\\partial}{\\partial{}_\\text{?}a}\\left(-1\\right)\\right){}_\\text{?}b+-1\\frac{\\partial}{\\partial{}_\\text{?}a}{}_\\text{?}b	{9,10,2,4,25}	function	2	{167,168}
170	\\x000002000500020000000000ffffffff0a0000000900000002000000040000001900000000000000020002000200020305000306040100	\\xfc01d0b23aab782c8f05d9f7e50a4c0581606a8f9bc67627ab1755546cc619d5	0{}_\\text{?}b+-1\\frac{\\partial}{\\partial{}_\\text{?}a}{}_\\text{?}b	{10,9,2,4,25}	function	2	{154,168}
16	\\x000001000200010001000000090000000600000000000200010002	\\x209140cc8cd71d6d036ba4d6b5f19ec77881b6105cfe09185569ee40cc8020c3	{}_\\text{?}a^{1}	{9,6}	function	6	{1,13}
19	\\x0000000005000300090000000a0000000b00000004000000060000000000000000000200020003040001040002	\\xf737887c811816a54bb3ad9658d5ea4b07623762a32802bfbe85dbdd536a1618	{}_\\text{?}a^{{}_\\text{?}b}{}_\\text{?}a^{{}_\\text{?}c}	{9,10,11,4,6}	function	4	{17,18}
5	\\x0000000003000200090000000a00000003000000000000000200020001	\\x8af96fecdd3af832e9be5b6e7e23e27060e194b300e94a93954ac7e2dc1c2ee1	\N	{9,10,3}	function	3	{1,2}
17	\\x0000000003000200090000000a00000006000000000000000200020001	\\x179655ebc9a1bcc8e05debe8a5658f6c6f5a5a339934ca54eb5e2dc0df1ea618	\N	{9,10,6}	function	6	{1,2}
18	\\x0000000003000200090000000b00000006000000000000000200020001	\\x1a68a647472dc53cf6fbab82825d05945bbc1b46a029514b05127173eb68c1d6	\N	{9,11,6}	function	6	{1,7}
24	\\x00000000020001001400000017000000000001000100	\\x60e62d80304fa9ac770f84c9df8a04815c066b13420feb521878eba6e59b7eda	\N	{20,23}	function	23	{21}
3	\\x00000000020001000a00000007000000000001000100	\\xd419c9a79fedb89dd8fe433025dd1b7eae46f975b3982323e3eccea316b34423	\N	{10,7}	function	7	{2}
180	\\x000001000200010002000000090000000600000000000200010002	\\x4d211308d49e14146f22cea3417f83f8fca62aa4a86d2aeb420427cfb73a1a76	{}_\\text{?}a^{2}	{9,6}	function	6	{1,179}
40	\\x00000000010001001c000000000000	\\xe9cfebc003c8d0fbf9ca336f289d2c0219494c4d846f0335ad9569ef2b00f836	\N	{28}	generic	28	{}
33	\\x000000000100000022000000000000	\\xbb259b48d2f8f7f4c776208ab4b51d3384f79a876291d7d0bcf001f0ed4bda51	\N	{34}	function	34	{}
34	\\x000000000100000021000000000000	\\x2e072772572ac8afc626b23eb0a61bbb693c2d7cb868e88d7152856335e1869d	\N	{33}	function	33	{}
198	\\x000000000600000004000000190000002300000021000000070000001300000002000200000000000100010000010203040503	\\x4425a96209044fd56a655a2558c48216dd33fd7d1820c6240f2c25a59a581544	\N	{4,25,35,33,7,19}	function	4	{119,197}
133	\\x0000000005000000040000001900000023000000210000001300000002000200000000000100000102030403	\\x9825b37bdb4e74c952e8d61cf849580854861b31272ba367570a45e25b68bf18	\N	{4,25,35,33,19}	function	4	{119,35}
31	\\x000000000100000020000000000000	\\xb81721ab27680cb5451215271df3921af7454d9b9dc26f1b0948336abd277053	\N	{32}	function	32	{}
151	\\x00000000030001000a0000001900000023000000000002000000010200	\\x4fb5edd80a20b4777a0df7a4eeef79e5eb6ea0a9ffeb8d80bcb2cf001b13b0e4	\N	{10,25,35}	function	25	{42,2}
96	\\x000001000600020000000000090000000a0000000200000004000000190000000d000000000000000200020002000000020304000105030106	\\xa2f54110440e6fd2d9f51bc9417feec0dcc93f6a7a9e8a0e883990d66f98f20d	\\left(\\frac{\\partial}{\\partial{}_\\text{?}a}{}_\\text{?}b\\right)\\hat{e_1}+{}_\\text{?}b0	{9,10,2,4,25,13}	function	2	{92,95}
120	\\x000000000100000024000000000000	\\xdf813ef5b3b9e1ef75e4aba1bebc59a2c7cc6679acf4e330cca4f911ebee3b14	\N	{36}	function	36	{}
200	\\x000000000900000004000000240000001b0000001900000023000000210000000700000013000000120000000200000002000200000000000100010001000001020003040506070500030405060805	\\x37f9e8d890b302e597f52595d2ed9dae872b0669ce985b8ddcea65dc7b490003	\N	{4,36,27,25,35,33,7,19,18}	function	4	{120,199}
143	\\x000000000700000004000000240000001b0000000700000012000000210000001300000002000000020001000100000001000001020304050605	\\x760f50f31f1061cc728f2f9a6c31e569c6b9c1ed0e5a3a04d784a56a125768f0	\N	{4,36,27,7,18,33,19}	function	4	{120,140}
14	\\x0000010001000000010000000700000001000001	\\x67c383bff6469fd3ef635e7f21fbec2e7a4fb5a5108bdbed69d982793074a848	\N	{7}	function	7	{13}
179	\\x00000100000000000200000000	\\xe62115b1b0a0940392fe419abadbc906d524d2f5e005ce2c982949ac518fc3d2	\N	{}	integer	2	{}
70	\\x0000000005000300090000000a0000000b0000000400000019000000000000000000020002000304000102	\\xeb0ab1606afdf08442c66d0e5a191b90ea0d6196704b93af254d04d5b52192e2	\N	{9,10,11,4,25}	function	4	{69,7}
160	\\x0000000002000200160000000a000000010000000001	\\x3f1b7de375cce4fad86ebd373913e4842ee6621961dbca0b6b3b45bff9b4e516	\N	{22,10}	generic	22	{2}
50	\\x00000000010000000e000000000000	\\xdb3966066a05fab9fa9f317f9a84d1daf73c5e1fc130ab860d6022ad47947378	\N	{14}	function	14	{}
111	\\x0000000005000300090000000a0000000b0000001b000000190000000000000000000200020003040001040002	\\x0b3242009d8b8fd453ae8a70abcc4a4893e22ea2b5bf672f581988ce3b9b3f1e	\\left(\\begin{matrix}\\frac{\\partial}{\\partial{}_\\text{?}a}{}_\\text{?}b\\\\\\frac{\\partial}{\\partial{}_\\text{?}a}{}_\\text{?}c\\end{matrix}\\right)	{9,10,11,27,25}	function	27	{69,71}
113	\\x0000000004000200090000000a0000001900000012000000000000000200010002000301	\\x0167e768741cf78d393f83c157745a2f0693c3218648490205f0a012a50c5754	\\frac{\\partial}{\\partial{}_\\text{?}a}\\sin{}_\\text{?}b	{9,10,25,18}	function	25	{1,112}
116	\\x0000000004000200090000000a0000001900000013000000000000000200010002000301	\\x95e4edaada590f46e50e69bd7db733749be901882b3c9ca0c6138460642c8968	\\frac{\\partial}{\\partial{}_\\text{?}a}\\cos{}_\\text{?}b	{9,10,25,19}	function	25	{1,114}
112	\\x00000000020001000a00000012000000000001000100	\\xa47dac51c4e36a952bfe2a0997aea71e7608d6d8ae93b9be55a2945011a5e202	\N	{10,18}	function	18	{2}
117	\\x00000000030001000a0000000700000012000000000001000100010200	\\xb9a2396340aeed290af2dd97b10f5d14d6717f19dff6bbd2446eb20676650cac	\N	{10,7,18}	function	7	{112}
114	\\x00000000020001000a00000013000000000001000100	\\x6d95778091df64e397c3b748855ed155a76c6080bcf9c2a6cd38a289ad6ce5d5	\N	{10,19}	function	19	{2}
25	\\x00000100000000000000000000	\\xe0afadbd718beefc7b9ec03c368f7f78a9eae4327d59216840678ede42d2fd96	0	{}	integer	0	{}
43	\\x00000000020001001c0000001d000000000001000100	\\x176fa6ccf4bec023d67eb477bdc9e96f6d7754c7215753ef5ce960ffb9b4840c	\N	{28,29}	function	29	{40}
32	\\x00000000020000001d00000020000000010000000001	\\x6d4cacc21a7d6e661d91e872bccad090df57b54449a78799b9201d83a82aa1ba	\N	{29,32}	function	29	{31}
44	\\x00000000040001001c00000019000000230000001d000000000002000000010001020300	\\x99fd71fa9a4dc6aeb8b0e8e02551a1206518152843b971681561f0a7d3b2088e	\N	{28,25,35,29}	function	25	{42,43}
35	\\x00000000020000001300000021000000010000000001	\\x8d519b5c940eb970e9bc0171940d182e2c8c4e46fda9ce0c09773f60f074254f	\N	{19,33}	function	19	{34}
37	\\x00000000020000001200000021000000010000000001	\\xccda6565b9faacdf43543dd0c2cbd67289fdee00cf2b813099dfc0d9e6d0edfa	\N	{18,33}	function	18	{34}
136	\\x0000000003000000070000001200000021000000010001000000000102	\\xe11894e7ec4c6f76487ca351a26e39979931b87e8e6f604e578b31928572c344	\N	{7,18,33}	function	7	{37}
42	\\x000000000100000023000000000000	\\xeb0f156a7cf61b326254127ce9e9225f07c7a9eb27a63df9a98a0c37197b8005	\N	{35}	function	35	{}
81	\\x0000000003000100090000001900000023000000000002000000010200	\\x1fd0c90df2dca8a98112da25ae3bfc09fd602d8daa51bc19567e80da4b237572	\N	{9,25,35}	function	25	{42,1}
190	\\x00000000050000001900000023000000070000001200000021000000020000000100010000000001020304	\\x229531bb3825d3389d895389460ec4f2d3451e2cf92770ca51c292d9c8d0fc5c	\N	{25,35,7,18,33}	function	25	{42,136}
197	\\x0000000003000000070000001300000021000000010001000000000102	\\x450c3934ae25df7e7d21d6d6926a3db7a13ee5aff304d6471e706461b49ce562	\N	{7,19,33}	function	7	{35}
124	\\x00000000040000001b00000013000000210000001200000002000100000001000001020302	\\x0a3de9576b5d9c333abf67baf06ebd4aa563d31b4c02b09e76c4f7c29be7a1e8	\N	{27,19,33,18}	function	27	{35,37}
202	\\x00000000050000001b000000070000001300000021000000120000000200010001000000010000010203010403	\\x0678a02ddc096e7aecad33c3b7dd34f48dcf8dc05faf9e2fa74ea3c38307a8f3	\N	{27,7,19,33,18}	function	27	{197,136}
199	\\x00000000080000001b0000000400000019000000230000002100000007000000130000001200000002000200020000000000010001000100000102030405060401020304050704	\\x0300e64a3263dceff6d9215d2c9788841f656bf41c53b217c48ac17682cfbcda	\N	{27,4,25,35,33,7,19,18}	function	27	{198,137}
129	\\x000000000400000019000000230000001300000021000000020000000100000000010203	\\x83bb95e3f9bb68c41e0526e8eb2799136b3f870945dc084a1410634da2d110bb	\N	{25,35,19,33}	function	25	{42,35}
127	\\x000000000600000019000000230000001b00000013000000210000001200000002000000020001000000010000010203040504	\\x4be70a49589516e044be3177605954ffcdce201dbd1529c3fe634d654d46aacd	\N	{25,35,27,19,33,18}	function	25	{42,124}
12	\\x00000000020001000900000007000000000001000100	\\xed9dae5554a70accaa92a3285e84500169047310a233a67d2402da9763e44a08	-{}_\\text{?}a	{9,7}	function	7	{1}
206	\\x000000000700000004000000240000001b000000070000001300000021000000120000000200000002000100010000000100000102030405030605	\\xf4f772e803f931e7ef4356944b2436c99e19d98728a69810480a0aeff2e0754c	\N	{4,36,27,7,19,33,18}	function	4	{120,202}
207	\\x000000000700000004000000240000001b0000000700000013000000210000001200000002000000020001000100000001000001000102030405030605	\\xd23e63dfb5b69b7bccf26c3d15ecbe719e4673b952da6a3b8f5e3cbe86ffb98e	\N	{4,36,27,7,19,33,18}	function	4	{120,206}
23	\\x000000000300020014000000160000001900000000000100020002000100	\\x3f8ac895dfad545ad6ad91a2ed1c8d0c22a1a238ef3e03997e043406734b1df1	\N	{20,22,25}	function	25	{21,22}
69	\\x0000000003000200090000000a00000019000000000000000200020001	\\xe3180c555144ef918acf93c2dce589ab0873fe7d41b0f35b90b63f16ff5d634c	\N	{9,10,25}	function	25	{1,2}
71	\\x0000000003000200090000000b00000019000000000000000200020001	\\xd82ea24efcbab42e1f4deb23bb4d73254bfb1d39a84a616d14fbcd023241fabc	\N	{9,11,25}	function	25	{1,7}
147	\\x0000000003000000190000002300000024000000020000000000000102	\\x1cfef4e62506739d288dbeb6c3bb337a1dd50b46755a95025cc7ff87b2ee5a79	\N	{25,35,36}	function	25	{42,120}
158	\\x0000000004000200090000000a0000001900000007000000000000000200010002000301	\\xfa3f98d1b65798a85affdb387621eff288d13c5ee374d6f9bb127c63f2386a39	\\frac{\\partial}{\\partial{}_\\text{?}a}\\left(-{}_\\text{?}b\\right)	{9,10,25,7}	function	25	{1,3}
159	\\x0000000004000200090000000a0000000700000019000000000000000100020002030001	\\xcd878068c89355a8dda3a2a8d8a88ba369199fc12d9460a7e406003757166cdf	-\\frac{\\partial}{\\partial{}_\\text{?}a}{}_\\text{?}b	{9,10,7,25}	function	7	{69}
211	\\x0000000002000000040000002400000002000000000101	\\x009b926c5a8b7e053a5c7d4db88267ba9b688d2a45dcc19930b9161a4a73f900	\N	{4,36}	function	4	{120,120}
214	\\x000001000200000002000000060000002400000002000000000102	\\xcf09c347abdb210009c653667c10deedd186c87ac5e535590a012c65ec6db850	\N	{6,36}	function	6	{120,179}
164	\\x0000010002000100ffffffff090000001900000000000200010002	\\x4064347fcdddcd7041fa4c47f0c718ab8de511ef378493c70f4df6a76bacb2ca	\\frac{\\partial}{\\partial{}_\\text{?}a}\\left(-1\\right)	{9,25}	function	25	{1,163}
65	\\x00000000030002000a0000000b0000001b000000000000000200020001	\\xa9e25e97b13f62f0c88e9f22220e721a0b9633545e329eeabd4577f49bd756fe	\N	{10,11,27}	function	27	{2,7}
163	\\x0000010000000000ffffffff00	\\xa9015325dd84a5fe32a973b297d83926289efe354948451371a303d3ee305184	\N	{}	integer	-1	{}
161	\\x000000000400030009000000160000000a00000019000000000001000000020003000102	\\x4b5d88f60a337debd4afd9b4b3f9486cfe29abd6cf9b8c831eeba1d2931bb973	\N	{9,22,10,25}	function	25	{1,160}
174	\\x00000000030001000a0000000700000013000000000001000100010200	\\xef38a6de616ee046cc7335c0f47db3841cf7df27f10a036cd2473e38c361e9c9	\N	{10,7,19}	function	7	{114}
90	\\x000001000200010000000000090000000400000000000200010002	\\x75425810302585f0b3c7dd15433a301a51f546e3b76166f15e16c5cced7a072e	{}_\\text{?}a0	{9,4}	function	4	{1,25}
45	\\x00000000020001001c0000001f000000000001000100	\\xc6f5fe6b7e5be8b67145dee696b13c93de6613ceb1929b9035effed31b7aad2a	\N	{28,31}	function	31	{40}
119	\\x0000000003000000190000002300000021000000020000000000000102	\\x4647318e8d22127c9325f768b4c938ed2e8fa552eac52ea0dd60657a94fd9a29	\N	{25,35,33}	function	25	{42,34}
130	\\x000000000400000019000000230000001200000021000000020000000100000000010203	\\x2bcafaab0b625ab1eab06967b1da03d1d2974233bd58aa503f8eb669f01350d1	\N	{25,35,18,33}	function	25	{42,37}
187	\\x000000000700000019000000230000001b0000000700000012000000210000001300000002000000020001000100000001000001020304050605	\\xa900ab267b29dab46d9e089238ebb36ada275875299345553fd5bd712dac3682	\N	{25,35,27,7,18,33,19}	function	25	{42,140}
140	\\x00000000050000001b0000000700000012000000210000001300000002000100010000000100000102030403	\\x2ad4549312a7ed9217a974aea62c890b4dea876d8d8f9d531851a25d27e7229b	\N	{27,7,18,33,19}	function	27	{136,35}
203	\\x0000000008000000040000001900000023000000210000001b000000070000001300000012000000020002000000000002000100010001000001020304050603050703	\\x78ca1a1fb31fdea1785b02c9c969193b70af9f633ae5bb33b55d6ff3b251f152	\N	{4,25,35,33,27,7,19,18}	function	4	{119,202}
145	\\x0000000003000000040000002200000024000000020000000000000102	\\xc7f0d80d78c4094b5e48e226c6923dd96eda18fb955bdd4fc4d6dcbce8dbce17	\N	{4,34,36}	function	4	{33,120}
204	\\x000000000900000004000000240000001900000023000000210000001b00000007000000130000001200000002000000020000000000020001000100010000010002030405060704060804	\\x033d845d86fe94bd433e57e8b95697db6fab2611f9562cb6a9ee4594da239e41	\N	{4,36,25,35,33,27,7,19,18}	function	4	{120,203}
173	\\x0000000005000200090000000a000000190000000700000012000000000000000200010001000200030401	\\x5243753a58418ee897da579e95e17e29256f43bbbb5949cfba860f67a7875780	\\frac{\\partial}{\\partial{}_\\text{?}a}\\left(-\\sin{}_\\text{?}b\\right)	{9,10,25,7,18}	function	25	{1,117}
6	\\x0000000003000200090000000a00000004000000000000000200020001	\\xa21a2c2ab7610ca971fa03ef17af32bedb693c45c7877bcb7044ebe488983ee5	\N	{9,10,4}	function	4	{1,2}
8	\\x0000000003000200090000000b00000004000000000000000200020001	\\xb663acd854dc781f7c56f92ffc5a13a6ebb33ca51b0290a1933a94d5212c4639	\N	{9,11,4}	function	4	{1,7}
157	\\x00000100030001000100000009000000190000000700000000000200010001000203	\\xd61f08b846b21461be79b905c2ba33f9262dcac75ad1eceb78386ca80373dc08	\N	{9,25,7}	function	25	{1,14}
51	\\x00000000030001000a000000040000000e000000000002000000010002	\\x42ec8b03c8af9c3cb6dd47ae22e58c3affd6a54c8af30060d97ca89bff7c2eb5	\N	{10,4,14}	function	4	{2,50}
55	\\x0000000004000200090000000b000000040000000e00000000000000020000000202000103	\\x24f499b37694a0c357a2c6a728cbab571e894a1c142fe3410a4a9d3254a2fc2a	\N	{9,11,4,14}	function	4	{8,50}
57	\\x00000000030001000b000000040000000e000000000002000000010002	\\x1697193b18280e9c70a949cea53955e67e2a69cf81b605e3e03c120650555724	\N	{11,4,14}	function	4	{7,50}
58	\\x0000000004000200090000000b000000040000000e00000000000000020000000200020103	\\x915675aeb06b009ffb789b01888ff6ae04c286e9731f8ea119d5e36f9e5caa32	\N	{9,11,4,14}	function	4	{1,57}
95	\\x0000010002000100000000000a0000000400000000000200010002	\\x34a40d2fc81f9540e8bb0b0d6772bd0e5cc21cff1189478e51bfcdf2ba9dfeda	\N	{10,4}	function	4	{2,25}
4	\\x0000000004000200090000000a0000000200000007000000000000000200010002000301	\\x06c4317b0d80c1ce50664d8365b0cf06da41d15dbc6038d7f6c18952206908fc	\N	{9,10,2,7}	function	2	{1,3}
185	\\x0000000009000000190000002300000004000000240000001b0000000700000012000000210000001300000002000000020000000200010001000000010000010203040506070807	\\x8b00d25047d7f2322bff4d018cd6716bfb3057c3bc6ed810d7c9dcd570e86fab	\N	{25,35,4,36,27,7,18,33,19}	function	25	{42,143}
98	\\x0000000005000200090000000a00000019000000040000000e000000000000000200020000000200030104	\\xfb99e179143b084df01cefa06906a74881c3557d4cb0b0f05133688b16c55e4e	\\frac{\\partial}{\\partial{}_\\text{?}a}{}_\\text{?}b\\hat{e_2}	{9,10,25,4,14}	function	25	{1,51}
167	\\x0000010004000200ffffffff090000000a000000040000001900000000000000020002000203000401	\\xb3adf28f5eaff7c81ad38d9401a753b659c45692dcc76159ad1e579800c8d122	\N	{9,10,4,25}	function	4	{164,2}
168	\\x0000010004000200ffffffff090000000a000000040000001900000000000000020002000204030001	\\xd4ad397622679fbd5535dc3e0530ef106b77c3990f065e13541df12f32b8e168	\N	{9,10,4,25}	function	4	{163,69}
99	\\x0000000005000200090000000a00000004000000190000000e000000000000000200020000000203000104	\\xc1762481e7f7b0a2a408b7cd8369d1f60fe7813937996bcaabe31d7afe53066a	\\left(\\frac{\\partial}{\\partial{}_\\text{?}a}{}_\\text{?}b\\right)\\hat{e_2}	{9,10,4,25,14}	function	4	{69,50}
192	\\x000000000900000004000000240000001b000000190000002300000007000000120000002100000013000000020000000200020000000100010000000100000102030405060703040807	\\x513c7aad8aba620762e97f9f1c77304fc45a8da2bcf083c77868085382714642	\N	{4,36,27,25,35,7,18,33,19}	function	4	{120,191}
75	\\x000001000200010000000000090000000400000000000200010200	\\x77ca76e6b8c82d47b148ca0b4ada2224dce12fec41fa2a4e2b1b2da36a4fd5a1	0{}_\\text{?}a	{9,4}	function	4	{25,1}
88	\\x000000000300010009000000190000000d000000000002000000010002	\\x3195f1eec3047fdadbac56be5a65f0634075d874083fc990a2e98a9744836233	\\frac{\\partial}{\\partial{}_\\text{?}a}\\hat{e_1}	{9,25,13}	function	25	{1,48}
86	\\x0000000005000300090000000a0000000b0000001900000002000000000000000000020002000300040102	\\xff3dbcce10eeacdb5d9ef6f7378c5613b5a98619967e4f2278d4cef0d7efdc8e	\\frac{\\partial}{\\partial{}_\\text{?}a}\\left({}_\\text{?}b+{}_\\text{?}c\\right)	{9,10,11,25,2}	function	25	{1,10}
115	\\x0000000005000200090000000a00000004000000190000001300000000000000020002000100020300010401	\\xc69b5d07bd175599f3c4f09f2c261279f8a931d95528d70e3883a5952b9f48b5	\\left(\\frac{\\partial}{\\partial{}_\\text{?}a}{}_\\text{?}b\\right)\\cos{}_\\text{?}b	{9,10,4,25,19}	function	4	{69,114}
118	\\x0000000006000200090000000a0000000400000019000000070000001200000000000000020002000100010002030001040501	\\x16a65d1031dac89e1f7ebe256285a2744349ac5a55f7446e595143196dc044d9	\\left(\\frac{\\partial}{\\partial{}_\\text{?}a}{}_\\text{?}b\\right)\\left(-\\sin{}_\\text{?}b\\right)	{9,10,4,25,7,18}	function	4	{69,117}
48	\\x00000000010000000d000000000000	\\xe3ad3e8c134a597c9a8bc2d01896e698815194eeccdac37c9f3983eb2a368a21	\N	{13}	function	13	{}
191	\\x00000000070000001b000000190000002300000007000000120000002100000013000000020002000000010001000000010000010203040501020605	\\x52a17f89e1974aa29263b259f09bb0d14e320224d3dd661aac8a3ee205220f17	\N	{27,25,35,7,18,33,19}	function	27	{190,129}
137	\\x000000000600000004000000190000002300000021000000070000001200000002000200000000000100010000010203040503	\\x094449dbf6b7d691c57fbd10fab67c999b5cbed08582cae53ab9bb8f6b882e04	\N	{4,25,35,33,7,18}	function	4	{119,136}
26	\\x000000000300010014000000020000001700000000000200010001000200	\\xac989ff477bf681528e055ae65e795bca03aa152aa0206bf442cf589a7ac024a	\N	{20,2,23}	function	2	{21,24}
27	\\x00000000040002001600000014000000020000001700000001000000020001000002010301	\\xfadd710643637b7e3c9172b884784111c44b611f1fc2be9bad580c1477ff9666	\N	{22,20,2,23}	generic	22	{26}
28	\\x00000000050002001600000014000000030000000200000017000000010000000200020001000200030104010001	\\xc02fcd98f76ef3854b6c11f1ad0369f6704de620e3a2236e6655d1bf30d13124	\N	{22,20,3,2,23}	function	3	{27,22}
29	\\x00000000060002001600000014000000050000000300000002000000170000000100000002000200020001000203000401050100010501	\\x9a705a3331eec10cdd8b82a01f7833b787395e50064fea1ed1f64c6ad9b122b9	\N	{22,20,5,3,2,23}	function	5	{28,24}
30	\\x000001000700020000000000140000001600000018000000170000000500000003000000020000000000010003000100020002000200020300070405010600030001000300	\\x0c0208b22a214904a0a0c2ded23fba5a80dec90381e229f3d98a6b03c898df4d	\N	{20,22,24,23,5,3,2}	function	24	{24,25,29}
10	\\x00000000030002000a0000000b00000002000000000000000200020001	\\x77b5554abc9aee843fabdb8d710fc6601e1ba533ba6f40d2adc25573ffa87c1b	\N	{10,11,2}	function	2	{2,7}
77	\\x000001000200010000000000090000000200000000000200010200	\\xc1643dedd639c96950f9dc40955b094ee6f7c686847444dbdb5b168e60218586	0+{}_\\text{?}a	{9,2}	function	2	{25,1}
53	\\x0000000005000300090000000a0000000b0000001b000000040000000000000000000200020003040001040002	\\x5ff270dfd4c4eb4bb45dd94633b057f15950855d8f50cb54a683dca5ef841f7d	\\left(\\begin{matrix}{}_\\text{?}a{}_\\text{?}b\\\\{}_\\text{?}a{}_\\text{?}c\\end{matrix}\\right)	{9,10,11,27,4}	function	27	{6,8}
66	\\x0000000005000300090000000a0000000b000000040000001b000000000000000000020002000300040102	\\x6215e710c4135fc8287611ce9638c218eb6e2d3c43c1cfc4cb69c67d3798504a	{}_\\text{?}a\\left(\\begin{matrix}{}_\\text{?}b\\\\{}_\\text{?}c\\end{matrix}\\right)	{9,10,11,4,27}	function	4	{1,65}
149	\\x00000000050001000a00000019000000230000000400000024000000000002000000020000000102030400	\\xa50d34280e719dae14e5bacd487f1ec9214c7f3e01506bcfb05c2e2116e696fa	\N	{10,25,35,4,36}	function	25	{42,148}
9	\\x0000000005000300090000000a0000000b00000002000000040000000000000000000200020003040001040002	\\xda3e94d9a6b49580ebd17ab5ea06b39f39587525854be82bfcfa859de1039c21	{}_\\text{?}a{}_\\text{?}b+{}_\\text{?}a{}_\\text{?}c	{9,10,11,2,4}	function	2	{6,8}
11	\\x0000000005000300090000000a0000000b0000000400000002000000000000000000020002000300040102	\\x0aa7057218958cccb8a12433b953a3057847686b280a2cd275d8a3302272f883	{}_\\text{?}a\\left({}_\\text{?}b+{}_\\text{?}c\\right)	{9,10,11,4,2}	function	4	{1,10}
76	\\x000001000200010000000000090000000200000000000200010002	\\x182374522020321381c4df9d629cb67f7166efb02e48e6810ca7539aedecb71b	{}_\\text{?}a+0	{9,2}	function	2	{1,25}
152	\\x00000000050001000a00000004000000240000001900000023000000000002000000020000000102030400	\\xe1ff55abfbe936058cf6f9c16a8865ec15483467a8d9c7a7255056d5a6111f95	\N	{10,4,36,25,35}	function	4	{120,151}
73	\\x0000000006000300090000000a0000000b0000000200000004000000190000000000000000000200020002000304050001020401050002	\\x2a7e0711c6d0f49dfaacee7badbe06721288157d3d9854c5d41d8243b3b51fa5	\\left(\\frac{\\partial}{\\partial{}_\\text{?}a}{}_\\text{?}b\\right){}_\\text{?}c+{}_\\text{?}b\\frac{\\partial}{\\partial{}_\\text{?}a}{}_\\text{?}c	{9,10,11,2,4,25}	function	2	{70,72}
68	\\x0000000005000300090000000a0000000b0000001900000004000000000000000000020002000300040102	\\x04f553ec95d6e7b8c4fe38a8b1f2449c1ebddc6f7d8360e5f03b8273fed3e7e5	\\frac{\\partial}{\\partial{}_\\text{?}a}{}_\\text{?}b{}_\\text{?}c	{9,10,11,25,4}	function	25	{1,67}
101	\\x0000000006000200090000000a0000000200000004000000190000000e0000000000000002000200020000000203040001050301040005	\\x30bc1d3c6c974de273929af7081eda723cb9a3e51c5fdee81386092f901f4bd6	\\left(\\frac{\\partial}{\\partial{}_\\text{?}a}{}_\\text{?}b\\right)\\hat{e_2}+{}_\\text{?}b\\frac{\\partial}{\\partial{}_\\text{?}a}\\hat{e_2}	{9,10,2,4,25,14}	function	2	{99,100}
102	\\x000001000600020000000000090000000a0000000200000004000000190000000e000000000000000200020002000000020304000105030106	\\x0d96b8ffc0b81169e76eb2fa42680bbc29db806599c7094ecc5987ec1c70eca1	\\left(\\frac{\\partial}{\\partial{}_\\text{?}a}{}_\\text{?}b\\right)\\hat{e_2}+{}_\\text{?}b0	{9,10,2,4,25,14}	function	2	{99,95}
103	\\x000001000600020000000000090000000a0000000200000004000000190000000e00000000000000020002000200000002030400010506	\\xdcebb1dc79f04571e8ffd0a5bdcd725c11d2e6043e958622912c431d490d7da4	\\left(\\frac{\\partial}{\\partial{}_\\text{?}a}{}_\\text{?}b\\right)\\hat{e_2}+0	{9,10,2,4,25,14}	function	2	{99,25}
87	\\x0000000005000300090000000a0000000b00000002000000190000000000000000000200020003040001040002	\\x00b33dca3684e3bf498c458b4122f9077e979bc6b5fc1803999c6d35f0f65d72	\\frac{\\partial}{\\partial{}_\\text{?}a}{}_\\text{?}b+\\frac{\\partial}{\\partial{}_\\text{?}a}{}_\\text{?}c	{9,10,11,2,25}	function	2	{69,71}
172	\\x000001000500020000000000090000000a00000002000000070000001900000000000000020001000200020503040001	\\x11c9bdfb3d3aae878bd92bae577940d7f4ce0fdaf90b308862cf982843ede11e	0+-\\frac{\\partial}{\\partial{}_\\text{?}a}{}_\\text{?}b	{9,10,2,7,25}	function	2	{25,159}
20	\\x0000000005000300090000000a0000000b0000000600000002000000000000000000020002000300040102	\\x0846ec457cce9d4c9ed47441fbff1e93670ad5b8f20e649e86579904ddfe839e	{}_\\text{?}a^{{}_\\text{?}b+{}_\\text{?}c}	{9,10,11,6,2}	function	6	{1,10}
72	\\x00000000050003000a000000090000000b0000000400000019000000000000000000020002000300040102	\\x020e9dfb2a64ac5a1d90f06ec010e2a9b5a66dcf65a0c8c16550a409d1aa4ebb	\N	{10,9,11,4,25}	function	4	{2,71}
176	\\x0000000002000100090000000400000000000200010000	\\x0ae10431daf1fbea1a3744536130d7e98fa9347dcff9278b3d463aa92a355e99	{}_\\text{?}a{}_\\text{?}a	{9,4}	function	4	{1,1}
92	\\x0000000005000200090000000a00000004000000190000000d000000000000000200020000000203000104	\\x83496b398cc5aa6f7dedc25816b97d67fca11ee286aae3b51b5b9dad45d7c490	\\left(\\frac{\\partial}{\\partial{}_\\text{?}a}{}_\\text{?}b\\right)\\hat{e_1}	{9,10,4,25,13}	function	4	{69,48}
91	\\x0000000005000200090000000a00000019000000040000000d000000000000000200020000000200030104	\\xbbd49874a55d4132e4e240036002df53e82fde87a1c8de1f3c2a6549b39b14d7	\\frac{\\partial}{\\partial{}_\\text{?}a}{}_\\text{?}b\\hat{e_1}	{9,10,25,4,13}	function	25	{1,60}
138	\\x00000000080000001b00000004000000190000002300000021000000070000001200000013000000020002000200000000000100010001000001020304050604010203040704	\\xd44bec4754979b1aef91db2d235b87a90179feebfee1872ecdc92a1d90b76858	\N	{27,4,25,35,33,7,18,19}	function	27	{137,133}
141	\\x0000000008000000040000001900000023000000210000001b0000000700000012000000130000000200020000000000020001000100010000010203040506030703	\\xfa491e89afafe0c493ea2bb08885798591f5cbd4d9f0a4ea8dad054fcc4ca563	\N	{4,25,35,33,27,7,18,19}	function	4	{119,140}
59	\\x0000000007000300090000000a0000000b00000002000000040000000d0000000e00000000000000000002000200000000000304040001050400040206	\\xc5ee133a99511504f27b936b3dc5ab5af49bfa70dfcabdbec5ec321932920df9	{}_\\text{?}a{}_\\text{?}b\\hat{e_1}+{}_\\text{?}a\\left({}_\\text{?}c\\hat{e_2}\\right)	{9,10,11,2,4,13,14}	function	2	{54,58}
64	\\x0000000007000300090000000a0000000b00000004000000020000000d0000000e0000000000000000000200020000000000030004030105030206	\\xf36878477e942efa4226507a7c6ffbdc1fe53e64426ad592145c3671670b4bb8	{}_\\text{?}a\\left({}_\\text{?}b\\hat{e_1}+{}_\\text{?}c\\hat{e_2}\\right)	{9,10,11,4,2,13,14}	function	4	{1,63}
52	\\x0000000006000200090000000a00000002000000040000000d0000000e00000000000000020002000000000002030004030105	\\x1928457711ef3003e9f929c2f88de8c57ff8aa78322287f3367823c8d93bf754	{}_\\text{?}a\\hat{e_1}+{}_\\text{?}b\\hat{e_2}	{9,10,2,4,13,14}	function	2	{49,51}
166	\\x0000010004000200ffffffff090000000a000000190000000400000000000000020002000200030401	\\x08a2370ea01595ae798e4800c9e72cf0dea8988db986512044af67e4e168ce2e	\\frac{\\partial}{\\partial{}_\\text{?}a}\\left(-1{}_\\text{?}b\\right)	{9,10,25,4}	function	25	{1,165}
177	\\x0000010003000100010000000900000004000000060000000000020002000100020003	\\x4ec5cfd089fbb50f6e2cac611494fba37d8c929dcdefff42605895513b9e52d3	{}_\\text{?}a{}_\\text{?}a^{1}	{9,4,6}	function	4	{1,16}
178	\\x00000100030001000100000009000000040000000600000000000200020001020003020003	\\xb4a8ec20c55c1f0bdd7564854c0b84b5400c82a7cc067b2a65dd84f7c3b7bc1c	{}_\\text{?}a^{1}{}_\\text{?}a^{1}	{9,4,6}	function	4	{16,16}
195	\\x000000000800000004000000240000001b000000190000002300000007000000120000002100000002000000020002000000010001000000000102030405060700030407050607	\\x991f7ac68830cfa6af40973b92fea2b720b3f15a735750d2f53a386ca2c1a27e	\N	{4,36,27,25,35,7,18,33}	function	4	{120,194}
150	\\x00000000050001000a00000004000000190000002300000024000000000002000200000000000102030400	\\xd9047b711b7d16de3af18dfa55d69697750924918e541b9674afa1421d712496	\N	{10,4,25,35,36}	function	4	{147,2}
100	\\x00000000050002000a0000000900000004000000190000000e000000000000000200020000000200030104	\\x5708b70caa47edc577a88f61173b328797b0d406c306a0a4743666906ddeba71	\N	{10,9,4,25,14}	function	4	{2,89}
106	\\x0000000005000200090000000b00000019000000040000000e000000000000000200020000000200030104	\\xb35346b948ccae923067b36907d98b981bb95912a756413d32971176ee97b1a2	\N	{9,11,25,4,14}	function	25	{1,57}
162	\\x0000000005000300090000000a000000160000000400000019000000000000000100020002000304000104000201	\\x3cbbc12bb39dada06856aa381d024870596f3295bf5cf48aecbe969aa8bb5ef2	\N	{9,10,22,4,25}	function	4	{69,161}
67	\\x00000000030002000a0000000b00000004000000000000000200020001	\\xc204c52c996f4d4d83cdc932766e8597a4358214c127eb3c473c738c586dd0b6	\N	{10,11,4}	function	4	{2,7}
93	\\x00000000050002000a0000000900000004000000190000000d000000000000000200020000000200030104	\\x3b3f878f3d4e573d89de3085f42c77790e7341be1df4628583638ddd8076e28e	\N	{10,9,4,25,13}	function	4	{2,88}
154	\\x0000010002000100000000000a0000000400000000000200010200	\\xd5c8739b3d8ec684ddf6b813a613f0b2a6cef4d3ecf65799a2289549801fe550	\N	{10,4}	function	4	{25,2}
165	\\x0000010002000100ffffffff0a0000000400000000000200010200	\\x23d010def75d57147e50d517d8fb7d845a3b5cfbac38bf96cc3b2ba5b0364864	\N	{10,4}	function	4	{163,2}
108	\\x0000000005000200090000000b00000004000000190000000e000000000000000200020000000203000104	\\x261e3df84f04f931ef50d818442ea050c1de8ffac8344956628e6c69f8f5ef11	\N	{9,11,4,25,14}	function	4	{71,50}
49	\\x000000000300010009000000040000000d000000000002000000010002	\\x19751da471698239217fecc64922a9d552dc19e683c1caa6e595e4677ba70ff6	\N	{9,4,13}	function	4	{1,48}
54	\\x0000000004000200090000000a000000040000000d00000000000000020000000202000103	\\x8ed875991d441d684417f8c6cc9c20a443031f29ac7a9ab31db5583dac340e36	\N	{9,10,4,13}	function	4	{6,48}
60	\\x00000000030001000a000000040000000d000000000002000000010002	\\x9173bff7f1f319b137ff4d06e76b185d7c85f90577d03545659d63f153eb7fca	\N	{10,4,13}	function	4	{2,48}
61	\\x0000000004000200090000000a000000040000000d00000000000000020000000200020103	\\x464474048ba61398451d021ab677821b109f36b42bcb3cc94c926f83c116d0ae	\N	{9,10,4,13}	function	4	{1,60}
148	\\x00000000030001000a0000000400000024000000000002000000010200	\\x7bcaff4c4a4f68a09a70a65da17ce9b48c6090a4ca40b86104699586860a8288	\N	{10,4,36}	function	4	{120,2}
63	\\x00000000060002000a0000000b00000002000000040000000d0000000e00000000000000020002000000000002030004030105	\\xc3198650145c5aa0773524388b4613da5203e15008a8f3266a1ecca1712a278a	\N	{10,11,2,4,13,14}	function	2	{60,57}
56	\\x0000000007000300090000000a0000000b00000002000000040000000d0000000e00000000000000000002000200000000000304040001050404000206	\\x05228e414264114cf16d538d581cea9d826c89ff1bdc096a6460e135cb4815c4	{}_\\text{?}a{}_\\text{?}b\\hat{e_1}+{}_\\text{?}a{}_\\text{?}c\\hat{e_2}	{9,10,11,2,4,13,14}	function	2	{54,55}
62	\\x0000000007000300090000000a0000000b00000002000000040000000d0000000e00000000000000000002000200000000000304000401050400040206	\\xa1000008781bcc20f2debe57279a2e61d4d46e0da6b66d46ed60bf21901ef34d	{}_\\text{?}a\\left({}_\\text{?}b\\hat{e_1}\\right)+{}_\\text{?}a\\left({}_\\text{?}c\\hat{e_2}\\right)	{9,10,11,2,4,13,14}	function	2	{61,58}
97	\\x000001000600020000000000090000000a0000000200000004000000190000000d00000000000000020002000200000002030400010506	\\xfe538279af2e2a4e86f7169fc36fdb1f89d53e237b4184f5f1d3341d80446f96	\\left(\\frac{\\partial}{\\partial{}_\\text{?}a}{}_\\text{?}b\\right)\\hat{e_1}+0	{9,10,2,4,25,13}	function	2	{92,25}
94	\\x0000000006000200090000000a0000000200000004000000190000000d0000000000000002000200020000000203040001050301040005	\\x11db9802ceaddfc4b41574e78b6be5f8bb8fde0003e82da79d1e52a4e45786e3	\\left(\\frac{\\partial}{\\partial{}_\\text{?}a}{}_\\text{?}b\\right)\\hat{e_1}+{}_\\text{?}b\\frac{\\partial}{\\partial{}_\\text{?}a}\\hat{e_1}	{9,10,2,4,25,13}	function	2	{92,93}
105	\\x0000000008000300090000000a0000000b0000001900000002000000040000000d0000000e00000000000000000002000200020000000000030004050106050207	\\xa8ea5f23fbacae50f4f7857a4c0c3f7efb4f860d1f3176e2f9785a52d4db014c	\\frac{\\partial}{\\partial{}_\\text{?}a}\\left({}_\\text{?}b\\hat{e_1}+{}_\\text{?}c\\hat{e_2}\\right)	{9,10,11,25,2,4,13,14}	function	25	{1,63}
109	\\x0000000008000300090000000a0000000b0000000200000019000000040000000d0000000e000000000000000000020002000200000000000304000501060504000207	\\x63ba58677f37afa2b65798b39bf3e579097f7aa1047273a740e858890c050c10	\\frac{\\partial}{\\partial{}_\\text{?}a}{}_\\text{?}b\\hat{e_1}+\\left(\\frac{\\partial}{\\partial{}_\\text{?}a}{}_\\text{?}c\\right)\\hat{e_2}	{9,10,11,2,25,4,13,14}	function	2	{91,108}
78	\\x0000000003000100090000000400000022000000000002000000010200	\\x4b49e9030a1dd8082ff842809882566f9fc3ad93638dd467f93076059cc33f5c	\N	{9,4,34}	function	4	{33,1}
194	\\x00000000070000001b000000190000002300000007000000120000002100000004000000020002000000010001000000020000010203040506010205030405	\\x862adc46b266bd4db926e8d9e6754622965d0c5df12b8928d98d72700d702826	\N	{27,25,35,7,18,33,4}	function	27	{190,137}
110	\\x0000000008000300090000000a0000000b0000000200000004000000190000000d0000000e000000000000000000020002000200000000000304050001060405000207	\\x17093351b1787bfb546481180d0ab8358d38da0f59f824b0507cc5e6138ebf34	\\left(\\frac{\\partial}{\\partial{}_\\text{?}a}{}_\\text{?}b\\right)\\hat{e_1}+\\left(\\frac{\\partial}{\\partial{}_\\text{?}a}{}_\\text{?}c\\right)\\hat{e_2}	{9,10,11,2,4,25,13,14}	function	2	{92,108}
144	\\x00000000080000000400000022000000240000001b000000070000001200000021000000130000000200000000000200010001000000010000010002030405060706	\\x0d31079020b3fb0ccb9d291b07c686d908eee5cf691a53b94e98eaf10d2a1276	\N	{4,34,36,27,7,18,33,19}	function	4	{33,143}
125	\\x000000000600000004000000220000001b00000013000000210000001200000002000000020001000000010000010203040504	\\xee5b9896813ad6811565ec3183e52622655bfb5a22c0ceb4d6a7118ce83f9f1c	\N	{4,34,27,19,33,18}	function	4	{33,124}
216	\\x000001000900000002000000040000002200000006000000240000001b0000000700000013000000210000001200000002000000020000000200010001000000010000000102030904050607050807	\\x912839d0934977207270eb1c55a05fa9edc1e33412b69d10b2649e4e493c58ae	\N	{4,34,6,36,27,7,19,33,18}	function	4	{215,202}
208	\\x00000000080000000400000022000000240000001b000000070000001300000021000000120000000200000000000200010001000000010000010002000203040506040706	\\x7d51fa21796bdd10d2cd12d08966d1aadc06c96700935e99e0f5254ef23ef965	\N	{4,34,36,27,7,19,33,18}	function	4	{33,207}
210	\\x00000000080000000400000022000000240000001b000000070000001300000021000000120000000200000000000200010001000000010000000001020203040506040706	\\xf3d7380aba060521d40b9421fd10a100b7cc377557103ad15c96d2304efca20f	\N	{4,34,36,27,7,19,33,18}	function	4	{209,202}
209	\\x00000000030000000400000022000000240000000200000000000000010202	\\xf4b130c6596da8f3159911bfc53509615a9ad76bf7cab2b713f9617dd752d00b	\N	{4,34,36}	function	4	{145,120}
212	\\x00000000030000000400000022000000240000000200000000000001000202	\\x232d48e8f1a131c12468dd02330767730059d1ed84dba1bc074b05be0248ec7b	\N	{4,34,36}	function	4	{33,211}
215	\\x0000010004000000020000000400000022000000060000002400000002000000020000000001020304	\\x90ffd175c6002631d7b708c3d15110ce35fdcec7d2a0f188273bfdd3bcd911fd	\N	{4,34,6,36}	function	4	{33,214}
38	\\x000000000400000004000000220000001200000021000000020000000100000000010203	\\x04aa6d6594bc935c92622e118c3ea870b7fd1a6985f3343c15fd76e97249e144	\N	{4,34,18,33}	function	4	{33,37}
41	\\x00000000020001001c0000001e000000000001000100	\\xa6d95c43e82eb24c7bbccb0dfc9330f7375f9fe2f4cdb039db3b22a4b7dcfac1	\N	{28,30}	function	30	{40}
121	\\x00000000020000001e00000020000000010000000001	\\x5557a6d3c39577d55531ac7f70527e0e12178d43169a0ccb13685e6e7a6a5480	\N	{30,32}	function	30	{31}
46	\\x00000000040001001c00000019000000230000001e000000000002000000010001020300	\\x55914df5dd971985cf21d46732b8ccccc93cc94e5f3e17d842bda63cdb622e74	\N	{28,25,35,30}	function	25	{42,41}
181	\\x00000000020000001f00000020000000010000000001	\\x53ee880ebf7a6c8cb509b5d6b3045b4690e0c7ebe7c703423fafee200ee6b75d	\N	{31,32}	function	31	{31}
155	\\x0000010006000100000000000a0000000200000004000000240000001900000023000000000002000200000002000000010206000203040500	\\x7cfee65c1941049ae730e22ac9c3852e6dec7921cf4cb7344e4b448112563874	\N	{10,2,4,36,25,35}	function	2	{154,152}
122	\\x000000000400000019000000230000001d00000020000000020000000100000000010203	\\x433e9ebffeb7f3340408fe65e616da62a8e30ec8dec5305e849c5268ad34a0f8	\N	{25,35,29,32}	function	25	{42,32}
74	\\x0000000003000000190000002300000022000000020000000000000102	\\xaa7f80f5c5d16f6ec380f72a5043448365ef978ba5d6e593b93f895198ac4b94	\N	{25,35,34}	function	25	{42,33}
80	\\x00000000050001000900000004000000190000002300000022000000000002000200000000000102030400	\\xd9721e119f541a058a478dfbc6e00e88082b85df3bb67a4b5dddebbb55b4bdfa	\N	{9,4,25,35,34}	function	4	{74,1}
79	\\x00000000050001000900000019000000230000000400000022000000000002000000020000000102030400	\\x814b9f1d81203a03cae3a28ae285ef51a6c7463977edd2332b680088bf3fc1d3	\N	{9,25,35,4,34}	function	25	{42,78}
82	\\x00000000050001000900000004000000220000001900000023000000000002000000020000000102030400	\\xe96a0e7442f64abaf57dbb51ee8d2c303f485ba5e8d6ac8f87933fbc11c2738d	\N	{9,4,34,25,35}	function	4	{33,81}
83	\\x00000000060001000900000002000000040000001900000023000000220000000000020002000200000000000102030405000205030400	\\x8a91079644040a5707a771c3013317fe8bfb7aef26c132504529e19b27f96338	\N	{9,2,4,25,35,34}	function	2	{80,82}
84	\\x000001000600010000000000090000000200000004000000220000001900000023000000000002000200000002000000010206000203040500	\\xc7658b8d1af5ab7601f46bdc8ee94d9284d33f63b37273d28f9345e901e61433	\N	{9,2,4,34,25,35}	function	2	{75,82}
85	\\x00000100060001000000000009000000020000000400000022000000190000002300000000000200020000000200000001060203040500	\\x2e3f063fc5409eb08455612899f87ffc0b607af2adb999b747e4f18b8aae3ead	\N	{9,2,4,34,25,35}	function	2	{25,82}
182	\\x000000000400000019000000230000001e00000020000000020000000100000000010203	\\x8d3fbd9df8042257b06f34f50052cc145a55290cc61621378bbab17c1437a8c1	\N	{25,35,30,32}	function	25	{42,121}
128	\\x0000000008000000040000002200000019000000230000001b00000013000000210000001200000002000000020000000200010000000100000102030405060706	\\xa94e638751d6436607fdff29c8e83dfe7fec67d3a7684b39264579b015447774	\N	{4,34,25,35,27,19,33,18}	function	4	{33,127}
132	\\x000000000800000004000000220000001b0000001900000023000000130000002100000012000000020000000200020000000100000001000001020304050603040706	\\x0fe0144f368ffd8a395a3e137886dcfe8c9851340cc1b10a5edcf5502b73a430	\N	{4,34,27,25,35,19,33,18}	function	4	{33,131}
126	\\x0000000008000000190000002300000004000000220000001b00000013000000210000001200000002000000020000000200010000000100000102030405060706	\\xb723e16791731fd90e1feeec3b762ac393620c6332afa53f13a343c7f4b65f96	\N	{25,35,4,34,27,19,33,18}	function	25	{42,125}
134	\\x00000000060000001b00000019000000230000001300000021000000040000000200020000000100000002000001020304050102040304	\\x8a599eee88709a15dfe4d271a3f7f8c6336ea18778ee349ffcee2a876607a5dd	\N	{27,25,35,19,33,4}	function	27	{129,133}
131	\\x00000000060000001b0000001900000023000000130000002100000012000000020002000000010000000100000102030401020504	\\xcd2e739e24bbab0cdc3567d92e9103af308360f8d8624e8afcfc042fb69791dc	\N	{27,25,35,19,33,18}	function	27	{129,130}
135	\\x000000000700000004000000220000001b00000019000000230000001300000021000000020000000200020000000100000000010203040506000304060506	\\xb9107429e7beb66231ca16e2406b023e1e56eaf3d29dc735a7fba054b969c504	\N	{4,34,27,25,35,19,33}	function	4	{33,134}
36	\\x000000000400000004000000220000001300000021000000020000000100000000010203	\\xa183ba30b0f0b8fbbd7f189332419ee5e0db70e346a7b0062e489f46851a16d3	\N	{4,34,19,33}	function	4	{33,35}
39	\\x00000000060000001b0000000400000022000000130000002100000012000000020002000000010000000100000102030401020504	\\xf2f578577a7f7848945ef252c572db35882024c900ca02758e1f4163e226d66c	\N	{27,4,34,19,33,18}	function	27	{36,38}
142	\\x000000000900000004000000220000001900000023000000210000001b000000070000001200000013000000020000000200000000000200010001000100000100020304050607040804	\\x2ceeff3a0b5f756618d60ad54241d3c7be19815f0ab4a4b5d2e021f366b07730	\N	{4,34,25,35,33,27,7,18,19}	function	4	{33,141}
201	\\x000000000a0000000400000022000000240000001b000000190000002300000021000000070000001300000012000000020000000000020002000000000001000100010000010002030004050607080600040506070906	\\x51b7f2e6df9aef932a20895c480043751db112b819c5659b8cb17accc388fb08	\N	{4,34,36,27,25,35,33,7,19,18}	function	4	{33,200}
205	\\x000000000a0000000400000022000000240000001900000023000000210000001b0000000700000013000000120000000200000000000200000000000200010001000100000100020003040506070805070905	\\xb96c5a30f99478c397fa425d7c26a0856f3bd82031f48a2bfb3134c7fcaf700e	\N	{4,34,36,25,35,33,27,7,19,18}	function	4	{33,204}
186	\\x000000000a00000004000000220000001900000023000000240000001b000000070000001200000021000000130000000200000002000000000002000100010000000100000102030004050607080908	\\x150c2c79b03daeac38ed5583013bad94d4d9a5af875dd660c6ebeafc7a3cb2e9	\N	{4,34,25,35,36,27,7,18,33,19}	function	4	{33,185}
189	\\x000000000a00000004000000220000002400000019000000230000001b000000070000001200000021000000130000000200000000000200000002000100010000000100000100020304050607080908	\\x7ca76bbc9e11a7066792b20c8ee289b5d32b37b78f798ce5181a1b7478cccc16	\N	{4,34,36,25,35,27,7,18,33,19}	function	4	{33,188}
193	\\x000000000a0000000400000022000000240000001b00000019000000230000000700000012000000210000001300000002000000000002000200000001000100000001000001000203040506070804050908	\\x5ce46447745e7849a9273c0e2e2cf9598ea40e3b126ed116d37f591df3c7ee64	\N	{4,34,36,27,25,35,7,18,33,19}	function	4	{33,192}
183	\\x000000000a00000019000000230000000400000022000000240000001b000000070000001200000021000000130000000200000002000000000002000100010000000100000102020304050607080908	\\xf721177df965ad8dcfc1786b094d9535d3727babe9893f678522317e136749ee	\N	{25,35,4,34,36,27,7,18,33,19}	function	25	{42,146}
184	\\x000000000a00000019000000230000000400000022000000240000001b000000070000001200000021000000130000000200000002000000000002000100010000000100000102030204050607080908	\\x3430434ba777e086fc5808600712f26b0b82e68a5de7e04b1362815c8d7bdc16	\N	{25,35,4,34,36,27,7,18,33,19}	function	25	{42,144}
196	\\x00000000090000000400000022000000240000001b00000019000000230000000700000012000000210000000200000000000200020000000100010000000001000203040506070800040508060708	\\x3ed1948d52d788cbfa36160395be27724f482a0072ae09fdb4e700b23e1770f2	\N	{4,34,36,27,25,35,7,18,33}	function	4	{33,195}
146	\\x00000000080000000400000022000000240000001b000000070000001200000021000000130000000200000000000200010001000000010000000102030405060706	\\x33e09cb8a42e5a6ac3e433a398a57df89d146349c80d0c69ee651d29faa9639d	\N	{4,34,36,27,7,18,33,19}	function	4	{145,140}
139	\\x000000000900000004000000220000001b00000019000000230000002100000007000000120000001300000002000000020002000000000001000100010000010200030405060705000304050805	\\xb5a1a443ce41eafbc0aee1655ed2ab60bcbc28d874307f9c34b96233db40b8c4	\N	{4,34,27,25,35,33,7,18,19}	function	4	{33,138}
188	\\x0000000009000000040000002400000019000000230000001b0000000700000012000000210000001300000002000000020000000200010001000000010000010203040506070807	\\xbe24eb0d1dd18cc4a47a514de39db40b1b30116dd792a1c1af6c23f7320cc498	\N	{4,36,25,35,27,7,18,33,19}	function	4	{120,187}
213	\\x00000000080000000400000022000000240000001b000000070000001300000021000000120000000200000000000200010001000000010000000100020203040506040706	\\xadf10d0f22731e29efe3c3363a7e939e4211919457b2fb8f05ff45fc722811b7	\N	{4,34,36,27,7,19,33,18}	function	4	{212,202}
123	\\x000000000800000019000000230000001b0000000400000022000000130000002100000012000000020000000200020000000100000001000001020304050603040706	\\x35510c7baaa8f83db1549d9176ee2211f6f52c34511acb229908b49355b11eae	\N	{25,35,27,4,34,19,33,18}	function	25	{42,39}
\.


--
-- Name: expression_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('expression_id_seq', 216, true);


--
-- Data for Name: function; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY function (id, subject_id, descriptor_id, generic, rearrangeable, argument_count, keyword, keyword_type, latex_template) FROM stdin;
9	1	\N	t	f	0	a	symbol	\N
10	1	\N	t	f	0	b	symbol	\N
11	1	\N	t	f	0	c	symbol	\N
12	1	\N	t	f	0	n	symbol	\N
20	5	\N	t	f	0	x	symbol	\N
21	5	\N	t	f	0	y	symbol	\N
22	5	\N	t	f	1	f	abbreviation	\N
28	6	25	t	f	0	body	word	\N
13	3	\N	f	f	0	e1	symbol	\\hat{e_1}
14	3	\N	f	f	0	e2	symbol	\\hat{e_2}
15	3	\N	f	f	0	e3	symbol	\\hat{e_3}
1	1	6	f	t	2	\N	\N	${.0}=${1.}
2	1	7	f	t	2	\N	\N	${.0}+${1(+).}
3	1	8	f	f	2	\N	\N	${.0}-${1(+).}
4	1	9	f	t	2	\N	\N	${.0(+):}${:1(*).}
5	1	10	f	f	2	frac	latex	\\frac{\\,${0}\\,}{\\,${1}\\,}
6	1	11	f	f	2	\N	\N	${.0(*)}^{${1}}
7	1	12	f	f	1	\N	\N	$!-${0(^).}
8	2	13	f	f	1	\N	\N	${.0(~):}!
18	4	16	f	f	1	sin	latex	\\sin${:0(+).}
19	4	17	f	f	1	cos	latex	\\cos${:0(+).}
23	5	18	f	f	1	d	symbol	\\Delta${:0(+).}
24	5	19	f	f	3	lim	latex	\\lim_{${0}\\to${1}}${:2(+).}
25	5	20	f	f	2	diff	abbreviation	\\frac{\\partial}{\\partial${:0(+)}}${:1(+).}
26	1	21	f	f	1	abs	abbreviation	\\left|${0}\\right|
27	3	22	f	f	2	vec2	abbreviation	\\left(\\begin{matrix}${0}\\\\${1}\\end{matrix}\\right)
31	6	28	f	f	1	a	symbol	\\vec{a_{${0}}}
32	7	29	f	f	0	c	symbol	c
35	6	32	f	f	0	t	symbol	t
34	7	31	f	f	0	r	symbol	r
33	7	30	f	f	0	theta	word	\\theta
30	6	27	f	f	1	v	symbol	\\vec{v_{${0}}}
36	7	33	f	f	0	omega	word	\\omega
29	6	26	f	f	1	p	symbol	\\vec{p_{${0}}}
\.


--
-- Name: function_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('function_id_seq', 36, true);


--
-- Data for Name: language; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY language (id, code) FROM stdin;
1	en_US
2	nl_NL
\.


--
-- Name: language_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('language_id_seq', 2, true);


--
-- Data for Name: operator; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY operator (id, function_id, precedence_level, associativity, operator_type, "character", editor_template) FROM stdin;
1	1	1	ltr	infix	=	{}={}
2	2	2	ltr	infix	+	{}+{}
3	3	2	ltr	infix	-	{}-{}
4	4	3	ltr	infix	*	{}\\cdot{}
5	5	3	ltr	infix	/	{}\\div{}
6	6	4	rtl	infix	^	^{${0}}
7	7	5	ltr	prefix	~	-
8	8	6	rtl	postfix	!	!\\,
\.


--
-- Name: operator_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('operator_id_seq', 8, true);


--
-- Data for Name: proof; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY proof (id, first_step_id, last_step_id) FROM stdin;
1	1	6
2	7	9
3	10	14
4	15	17
5	18	22
6	23	27
7	28	33
8	34	42
9	42	44
10	34	44
11	45	49
12	50	56
13	57	60
14	61	74
\.


--
-- Name: proof_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('proof_id_seq', 14, true);


--
-- Data for Name: rule; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY rule (id, step_id, proof_id, is_definition, left_expression_id, right_expression_id, left_array_data, right_array_data) FROM stdin;
1	\N	\N	t	4	5	{576332304,4,2,2,11,198119638,3,9,251955836,4,7,1,3,358130610,3,10}	{725194104,4,3,2,6,198119638,3,9,358130610,3,10}
2	\N	\N	t	9	11	{755105816,4,2,2,22,507440212,4,4,2,6,198119638,3,9,358130610,3,10,792166020,4,4,2,6,198119638,3,9,971369676,3,11}	{528846700,4,4,2,14,198119638,3,9,416255908,4,2,2,6,358130610,3,10,971369676,3,11}
3	\N	\N	t	12	15	{304733658,4,7,1,3,198119638,3,9}	{691054416,4,4,2,11,205680372,4,7,1,3,5,1,1,198119638,3,9}
4	\N	\N	t	16	1	{510478350,4,6,2,6,198119638,3,9,5,1,1}	{198119638,3,9}
5	\N	\N	t	19	20	{71005026,4,4,2,22,695795496,4,6,2,6,198119638,3,9,358130610,3,10,622151856,4,6,2,6,198119638,3,9,971369676,3,11}	{491848602,4,6,2,14,198119638,3,9,416255908,4,2,2,6,358130610,3,10,971369676,3,11}
6	\N	\N	t	23	30	{518681770,4,25,2,11,801036408,3,20,647388986,5,22,1,3,801036408,3,20}	{259565444,4,24,3,58,10394894,4,23,1,3,801036408,3,20,1,1,0,1070033562,4,5,2,42,609969986,4,3,2,29,177948780,5,22,1,16,241161002,4,2,2,11,801036408,3,20,10394894,4,23,1,3,801036408,3,20,647388986,5,22,1,3,801036408,3,20,10394894,4,23,1,3,801036408,3,20}
7	\N	\N	t	32	39	{677051452,4,29,1,3,339289018,2,32}	{987721868,4,27,2,32,380730976,4,4,2,11,450801924,2,34,605498974,4,19,1,3,935094976,2,33,893790482,4,4,2,11,450801924,2,34,180484444,4,18,1,3,935094976,2,33}
8	\N	\N	t	41	44	{1057511242,4,30,1,3,316448450,3,28}	{440896748,4,25,2,11,1048311870,2,35,1021991398,4,29,1,3,316448450,3,28}
9	\N	\N	t	45	46	{410946662,4,31,1,3,316448450,3,28}	{567539448,4,25,2,11,1048311870,2,35,1057511242,4,30,1,3,316448450,3,28}
10	\N	\N	t	47	52	{806519012,4,27,2,6,198119638,3,9,358130610,3,10}	{88350546,4,2,2,22,352139162,4,4,2,6,198119638,3,9,665602766,2,13,1030378374,4,4,2,6,358130610,3,10,168365960,2,14}
11	\N	1	f	53	66	{201491036,4,27,2,22,507440212,4,4,2,6,198119638,3,9,358130610,3,10,792166020,4,4,2,6,198119638,3,9,971369676,3,11}	{48462890,4,4,2,14,198119638,3,9,29285668,4,27,2,6,358130610,3,10,971369676,3,11}
12	\N	\N	t	68	73	{1033235600,4,25,2,14,198119638,3,9,971491676,4,4,2,6,358130610,3,10,971369676,3,11}	{503257732,4,2,2,38,127372132,4,4,2,14,232795360,4,25,2,6,198119638,3,9,358130610,3,10,971369676,3,11,950309976,4,4,2,14,358130610,3,10,520828540,4,25,2,6,198119638,3,9,971369676,3,11}
13	\N	\N	t	74	25	{1029158494,4,25,2,6,1048311870,2,35,450801924,2,34}	{1,1,0}
14	\N	\N	t	75	25	{99079404,4,4,2,6,1,1,0,198119638,3,9}	{1,1,0}
15	\N	\N	t	76	1	{1020690818,4,2,2,6,198119638,3,9,1,1,0}	{198119638,3,9}
16	\N	2	f	77	1	{670663792,4,2,2,6,1,1,0,198119638,3,9}	{198119638,3,9}
17	\N	3	f	79	82	{431911894,4,25,2,14,1048311870,2,35,123030910,4,4,2,6,450801924,2,34,198119638,3,9}	{630282128,4,4,2,14,450801924,2,34,801765768,4,25,2,6,1048311870,2,35,198119638,3,9}
18	\N	\N	t	86	87	{769626246,4,25,2,14,198119638,3,9,416255908,4,2,2,6,358130610,3,10,971369676,3,11}	{405734452,4,2,2,22,232795360,4,25,2,6,198119638,3,9,358130610,3,10,520828540,4,25,2,6,198119638,3,9,971369676,3,11}
19	\N	\N	t	88	25	{713285464,4,25,2,6,198119638,3,9,665602766,2,13}	{1,1,0}
20	\N	\N	t	89	25	{967405570,4,25,2,6,198119638,3,9,168365960,2,14}	{1,1,0}
21	\N	4	f	90	25	{736551474,4,4,2,6,198119638,3,9,1,1,0}	{1,1,0}
22	\N	5	f	91	92	{671192680,4,25,2,14,198119638,3,9,792675558,4,4,2,6,358130610,3,10,665602766,2,13}	{835575476,4,4,2,14,232795360,4,25,2,6,198119638,3,9,358130610,3,10,665602766,2,13}
23	\N	6	f	98	99	{462013456,4,25,2,14,198119638,3,9,1030378374,4,4,2,6,358130610,3,10,168365960,2,14}	{452012530,4,4,2,14,232795360,4,25,2,6,198119638,3,9,358130610,3,10,168365960,2,14}
24	\N	7	f	104	111	{452238580,4,25,2,14,198119638,3,9,29285668,4,27,2,6,358130610,3,10,971369676,3,11}	{737695824,4,27,2,22,232795360,4,25,2,6,198119638,3,9,358130610,3,10,520828540,4,25,2,6,198119638,3,9,971369676,3,11}
25	\N	\N	t	113	115	{477655354,4,25,2,11,198119638,3,9,395481382,4,18,1,3,358130610,3,10}	{583985556,4,4,2,19,232795360,4,25,2,6,198119638,3,9,358130610,3,10,446175624,4,19,1,3,358130610,3,10}
26	\N	\N	t	116	118	{344052300,4,25,2,11,198119638,3,9,446175624,4,19,1,3,358130610,3,10}	{345837958,4,4,2,24,232795360,4,25,2,6,198119638,3,9,358130610,3,10,505860694,4,7,1,8,395481382,4,18,1,3,358130610,3,10}
27	\N	\N	t	119	120	{265032348,4,25,2,6,1048311870,2,35,935094976,2,33}	{830725708,2,36}
28	\N	10	f	121	146	{354106522,4,30,1,3,339289018,2,32}	{810863728,4,4,2,37,877075364,4,4,2,6,450801924,2,34,830725708,2,36,1046518934,4,27,2,21,870361332,4,7,1,8,180484444,4,18,1,3,935094976,2,33,605498974,4,19,1,3,935094976,2,33}
29	\N	\N	t	147	25	{817167596,4,25,2,6,1048311870,2,35,830725708,2,36}	{1,1,0}
30	\N	11	f	149	152	{80626578,4,25,2,14,1048311870,2,35,506789758,4,4,2,6,830725708,2,36,358130610,3,10}	{909611664,4,4,2,14,830725708,2,36,35316580,4,25,2,6,1048311870,2,35,358130610,3,10}
36	\N	\N	t	164	25	{117147944,4,25,2,6,198119638,3,9,7,1,-1}	{1,1,0}
37	\N	\N	t	173	175	{459804778,4,25,2,16,198119638,3,9,505860694,4,7,1,8,395481382,4,18,1,3,358130610,3,10}	{675482016,4,4,2,24,232795360,4,25,2,6,198119638,3,9,358130610,3,10,39717168,4,7,1,8,446175624,4,19,1,3,358130610,3,10}
38	\N	13	f	176	180	{736185540,4,4,2,6,198119638,3,9,198119638,3,9}	{1068305054,4,6,2,6,198119638,3,9,9,1,2}
39	\N	14	f	181	216	{177161486,4,31,1,3,339289018,2,32}	{855089622,4,4,2,50,592137818,4,4,2,14,450801924,2,34,831389750,4,6,2,6,830725708,2,36,9,1,2,692608924,4,27,2,26,500823386,4,7,1,8,605498974,4,19,1,3,935094976,2,33,870361332,4,7,1,8,180484444,4,18,1,3,935094976,2,33}
\.


--
-- Name: rule_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('rule_id_seq', 39, true);


--
-- Data for Name: step; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY step (id, previous_id, expression_id, "position", step_type, proof_id, rule_id, rearrange) FROM stdin;
1	\N	53	0	set	\N	\N	\N
2	1	56	0	rule_normal	\N	10	\N
3	2	59	6	rearrange	\N	\N	{0,1,2,-1}
4	3	62	1	rearrange	\N	\N	{0,1,2,-1}
5	4	64	0	rule_normal	\N	2	\N
6	5	66	2	rule_invert	\N	10	\N
7	\N	77	0	set	\N	\N	\N
8	7	76	0	rearrange	\N	\N	{1,0}
9	8	1	0	rule_normal	\N	15	\N
10	\N	79	0	set	\N	\N	\N
11	10	83	0	rule_normal	\N	12	\N
12	11	84	2	rule_normal	\N	13	\N
13	12	85	1	rule_normal	\N	14	\N
14	13	82	0	rule_normal	\N	16	\N
15	\N	90	0	set	\N	\N	\N
16	15	75	0	rearrange	\N	\N	{1,0}
17	16	25	0	rule_normal	\N	14	\N
18	\N	91	0	set	\N	\N	\N
19	18	94	0	rule_normal	\N	12	\N
20	19	96	8	rule_normal	\N	19	\N
21	20	97	6	rule_normal	\N	21	\N
22	21	92	0	rule_normal	\N	15	\N
23	\N	98	0	set	\N	\N	\N
24	23	101	0	rule_normal	\N	12	\N
25	24	102	8	rule_normal	\N	20	\N
26	25	103	6	rule_normal	\N	21	\N
27	26	99	0	rule_normal	\N	15	\N
28	\N	104	0	set	\N	\N	\N
29	28	105	2	rule_normal	\N	10	\N
30	29	107	0	rule_normal	\N	18	\N
31	30	109	6	rule_normal	\N	23	\N
32	31	110	1	rule_normal	\N	22	\N
33	32	111	0	rule_invert	\N	10	\N
34	\N	121	0	set	\N	\N	\N
35	34	122	0	rule_normal	\N	8	\N
36	35	123	2	rule_normal	\N	7	\N
37	36	126	2	rule_normal	\N	11	\N
38	37	128	0	rule_normal	\N	17	\N
39	38	132	2	rule_normal	\N	24	\N
40	39	135	7	rule_normal	\N	25	\N
41	40	139	3	rule_normal	\N	26	\N
42	41	142	2	rule_normal	\N	11	\N
43	42	144	3	rule_normal	\N	27	\N
44	43	146	0	rearrange	\N	\N	{0,1,-1,2}
45	\N	149	0	set	\N	\N	\N
46	45	153	0	rule_normal	\N	12	\N
47	46	155	2	rule_normal	\N	29	\N
48	47	156	1	rule_normal	\N	14	\N
49	48	152	0	rule_normal	\N	16	\N
50	\N	158	0	set	\N	\N	\N
51	50	166	2	rule_normal	\N	3	\N
52	51	169	0	rule_normal	\N	12	\N
53	52	170	2	rule_normal	\N	36	\N
54	53	171	4	rule_revert	\N	3	\N
55	54	172	1	rule_normal	\N	14	\N
56	55	159	0	rule_normal	\N	16	\N
57	\N	176	0	set	\N	\N	\N
58	57	177	2	rule_invert	\N	4	\N
59	58	178	1	rule_invert	\N	4	\N
60	59	180	0	rule_normal	\N	5	\N
61	\N	181	0	set	\N	\N	\N
62	61	182	0	rule_normal	\N	9	\N
63	62	183	2	rule_normal	\N	28	\N
64	63	184	2	rearrange	\N	\N	{0,1,2,-1}
65	64	186	0	rule_normal	\N	17	\N
66	65	189	2	rule_normal	\N	30	\N
67	66	193	4	rule_normal	\N	24	\N
68	67	196	10	rule_normal	\N	26	\N
69	68	201	5	rule_normal	\N	37	\N
70	69	205	4	rule_normal	\N	11	\N
71	70	208	5	rule_normal	\N	27	\N
72	71	210	0	rearrange	\N	\N	{0,1,-1,2,-1,3}
73	72	213	1	rearrange	\N	\N	{0,1,2,-1}
74	73	216	3	rule_normal	\N	38	\N
\.


--
-- Name: step_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('step_id_seq', 74, true);


--
-- Data for Name: subject; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY subject (id, descriptor_id) FROM stdin;
1	1
2	2
3	3
4	4
5	5
6	23
7	24
\.


--
-- Name: subject_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('subject_id_seq', 7, true);


--
-- Data for Name: translation; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY translation (id, descriptor_id, language_id, content) FROM stdin;
1	1	1	Basic Algebra
2	2	1	Combinatorics
3	3	1	Vector Algebra
4	4	1	Trigonometry
5	5	1	Calculus
6	6	1	Equality
7	7	1	Add
8	8	1	Subtract
9	9	1	Multiply
10	10	1	Divide
11	11	1	Power
12	12	1	Negate
13	13	1	Factorial
14	14	1	Radius
15	15	1	Theta
16	16	1	Sine
17	17	1	Cosine
18	18	1	Delta
19	19	1	Limit
20	20	1	Differential
21	1	2	Basis algebra
22	2	2	Combinatoriek
23	3	2	Vectoralgebra
24	4	2	Trigonometrie
25	5	2	Calculus
26	6	2	Gelijkheid
27	7	2	Optellen
28	8	2	Aftrekken
29	9	2	Vermenigvuldigen
30	10	2	Delen
31	11	2	Macht
32	12	2	Omkeren
33	13	2	Factorial
34	14	2	Radius
35	15	2	Theta
36	16	2	Sinus
37	17	2	Cosinus
38	18	2	Delta
39	19	2	Limiet
40	20	2	Differentiaal
41	21	1	Absolute Value
42	22	1	2D Vector
43	23	1	Classical Mechanics
44	24	1	Circular Motion
45	25	1	Body
46	26	1	Body position
47	27	1	Velocity
48	28	1	Acceleration
49	29	1	Body with circular path
50	30	1	Angle with circular moving body
51	31	1	Radius of circular path
52	32	1	Time
53	33	1	Angular Speed
\.


--
-- Name: translation_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('translation_id_seq', 53, true);


--
-- Name: descriptor descriptor_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY descriptor
    ADD CONSTRAINT descriptor_pkey PRIMARY KEY (id);


--
-- Name: expression expression_data_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY expression
    ADD CONSTRAINT expression_data_key UNIQUE (data);


--
-- Name: expression expression_hash_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY expression
    ADD CONSTRAINT expression_hash_key UNIQUE (hash);


--
-- Name: expression expression_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY expression
    ADD CONSTRAINT expression_pkey PRIMARY KEY (id);


--
-- Name: function function_descriptor_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY function
    ADD CONSTRAINT function_descriptor_id_key UNIQUE (descriptor_id);


--
-- Name: function function_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY function
    ADD CONSTRAINT function_pkey PRIMARY KEY (id);


--
-- Name: function function_subject_id_latex_template_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY function
    ADD CONSTRAINT function_subject_id_latex_template_key UNIQUE (subject_id, latex_template);


--
-- Name: language language_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY language
    ADD CONSTRAINT language_code_key UNIQUE (code);


--
-- Name: language language_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY language
    ADD CONSTRAINT language_pkey PRIMARY KEY (id);


--
-- Name: operator operator_character_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY operator
    ADD CONSTRAINT operator_character_key UNIQUE ("character");


--
-- Name: operator operator_editor_template_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY operator
    ADD CONSTRAINT operator_editor_template_key UNIQUE (editor_template);


--
-- Name: operator operator_function_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY operator
    ADD CONSTRAINT operator_function_id_key UNIQUE (function_id);


--
-- Name: operator operator_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY operator
    ADD CONSTRAINT operator_pkey PRIMARY KEY (id);


--
-- Name: proof proof_first_step_id_last_step_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY proof
    ADD CONSTRAINT proof_first_step_id_last_step_id_key UNIQUE (first_step_id, last_step_id);


--
-- Name: proof proof_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY proof
    ADD CONSTRAINT proof_pkey PRIMARY KEY (id);


--
-- Name: rule rule_left_expression_id_right_expression_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY rule
    ADD CONSTRAINT rule_left_expression_id_right_expression_id_key UNIQUE (left_expression_id, right_expression_id);


--
-- Name: rule rule_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY rule
    ADD CONSTRAINT rule_pkey PRIMARY KEY (id);


--
-- Name: step step_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY step
    ADD CONSTRAINT step_pkey PRIMARY KEY (id);


--
-- Name: subject subject_descriptor_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY subject
    ADD CONSTRAINT subject_descriptor_id_key UNIQUE (descriptor_id);


--
-- Name: subject subject_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY subject
    ADD CONSTRAINT subject_pkey PRIMARY KEY (id);


--
-- Name: translation translation_language_id_content_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY translation
    ADD CONSTRAINT translation_language_id_content_key UNIQUE (language_id, content);


--
-- Name: translation translation_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY translation
    ADD CONSTRAINT translation_pkey PRIMARY KEY (id);


--
-- Name: expression_functions_index; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX expression_functions_index ON expression USING gin (functions);


--
-- Name: function_keyword_index; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX function_keyword_index ON function USING btree (keyword);


--
-- Name: function function_latex_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER function_latex_update AFTER UPDATE ON function FOR EACH ROW EXECUTE PROCEDURE clear_expression_latex();


--
-- Name: function function_descriptor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY function
    ADD CONSTRAINT function_descriptor_id_fkey FOREIGN KEY (descriptor_id) REFERENCES descriptor(id);


--
-- Name: function function_subject_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY function
    ADD CONSTRAINT function_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES subject(id);


--
-- Name: operator operator_function_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY operator
    ADD CONSTRAINT operator_function_id_fkey FOREIGN KEY (function_id) REFERENCES function(id);


--
-- Name: proof proof_first_step_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY proof
    ADD CONSTRAINT proof_first_step_id_fkey FOREIGN KEY (first_step_id) REFERENCES step(id);


--
-- Name: proof proof_last_step_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY proof
    ADD CONSTRAINT proof_last_step_id_fkey FOREIGN KEY (last_step_id) REFERENCES step(id);


--
-- Name: rule rule_left_expression_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY rule
    ADD CONSTRAINT rule_left_expression_id_fkey FOREIGN KEY (left_expression_id) REFERENCES expression(id);


--
-- Name: rule rule_proof_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY rule
    ADD CONSTRAINT rule_proof_id_fkey FOREIGN KEY (proof_id) REFERENCES proof(id);


--
-- Name: rule rule_right_expression_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY rule
    ADD CONSTRAINT rule_right_expression_id_fkey FOREIGN KEY (right_expression_id) REFERENCES expression(id);


--
-- Name: rule rule_step_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY rule
    ADD CONSTRAINT rule_step_id_fkey FOREIGN KEY (step_id) REFERENCES step(id);


--
-- Name: step step_expression_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY step
    ADD CONSTRAINT step_expression_id_fkey FOREIGN KEY (expression_id) REFERENCES expression(id);


--
-- Name: step step_previous_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY step
    ADD CONSTRAINT step_previous_id_fkey FOREIGN KEY (previous_id) REFERENCES step(id);


--
-- Name: step step_proof_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY step
    ADD CONSTRAINT step_proof_id_fkey FOREIGN KEY (proof_id) REFERENCES proof(id);


--
-- Name: step step_rule_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY step
    ADD CONSTRAINT step_rule_id_fkey FOREIGN KEY (rule_id) REFERENCES rule(id);


--
-- Name: subject subject_descriptor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY subject
    ADD CONSTRAINT subject_descriptor_id_fkey FOREIGN KEY (descriptor_id) REFERENCES descriptor(id);


--
-- Name: translation translation_descriptor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY translation
    ADD CONSTRAINT translation_descriptor_id_fkey FOREIGN KEY (descriptor_id) REFERENCES descriptor(id);


--
-- Name: translation translation_language_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY translation
    ADD CONSTRAINT translation_language_id_fkey FOREIGN KEY (language_id) REFERENCES language(id);


--
-- Name: plperl; Type: ACL; Schema: -; Owner: postgres
--

GRANT ALL ON LANGUAGE plperl TO eqdb;


--
-- Name: descriptor; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT ON TABLE descriptor TO eqdb;


--
-- Name: descriptor_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE descriptor_id_seq TO eqdb;


--
-- Name: expression; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT ON TABLE expression TO eqdb;


--
-- Name: expression.latex; Type: ACL; Schema: public; Owner: postgres
--

GRANT UPDATE(latex) ON TABLE expression TO eqdb;


--
-- Name: expression_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE expression_id_seq TO eqdb;


--
-- Name: function; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT ON TABLE function TO eqdb;


--
-- Name: function.subject_id; Type: ACL; Schema: public; Owner: postgres
--

GRANT UPDATE(subject_id) ON TABLE function TO eqdb;


--
-- Name: function.keyword; Type: ACL; Schema: public; Owner: postgres
--

GRANT UPDATE(keyword) ON TABLE function TO eqdb;


--
-- Name: function.keyword_type; Type: ACL; Schema: public; Owner: postgres
--

GRANT UPDATE(keyword_type) ON TABLE function TO eqdb;


--
-- Name: function.latex_template; Type: ACL; Schema: public; Owner: postgres
--

GRANT UPDATE(latex_template) ON TABLE function TO eqdb;


--
-- Name: function_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE function_id_seq TO eqdb;


--
-- Name: language; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT ON TABLE language TO eqdb;


--
-- Name: language_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE language_id_seq TO eqdb;


--
-- Name: operator; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT ON TABLE operator TO eqdb;


--
-- Name: operator_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE operator_id_seq TO eqdb;


--
-- Name: proof; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT ON TABLE proof TO eqdb;


--
-- Name: proof_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE proof_id_seq TO eqdb;


--
-- Name: rule; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE ON TABLE rule TO eqdb;


--
-- Name: rule_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE rule_id_seq TO eqdb;


--
-- Name: step; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT ON TABLE step TO eqdb;


--
-- Name: step_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE step_id_seq TO eqdb;


--
-- Name: subject; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT ON TABLE subject TO eqdb;


--
-- Name: subject_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE subject_id_seq TO eqdb;


--
-- Name: translation; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT ON TABLE translation TO eqdb;


--
-- Name: translation_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE translation_id_seq TO eqdb;


--
-- PostgreSQL database dump complete
--

\connect postgres

SET default_transaction_read_only = off;

--
-- PostgreSQL database dump
--

-- Dumped from database version 9.6.2
-- Dumped by pg_dump version 9.6.2

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: postgres; Type: COMMENT; Schema: -; Owner: postgres
--

COMMENT ON DATABASE postgres IS 'default administrative connection database';


--
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


--
-- PostgreSQL database dump complete
--

\connect template1

SET default_transaction_read_only = off;

--
-- PostgreSQL database dump
--

-- Dumped from database version 9.6.2
-- Dumped by pg_dump version 9.6.2

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: template1; Type: COMMENT; Schema: -; Owner: postgres
--

COMMENT ON DATABASE template1 IS 'default template for new databases';


--
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


--
-- PostgreSQL database dump complete
--

--
-- PostgreSQL database cluster dump complete
--

