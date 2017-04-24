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
-- Name: definition; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE definition (
    id integer NOT NULL,
    rule_id integer NOT NULL
);


ALTER TABLE definition OWNER TO postgres;

--
-- Name: definition_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE definition_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE definition_id_seq OWNER TO postgres;

--
-- Name: definition_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE definition_id_seq OWNED BY definition.id;


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
    proof_id integer,
    left_expression_id integer NOT NULL,
    right_expression_id integer NOT NULL,
    left_array_data integer[] NOT NULL,
    right_array_data integer[] NOT NULL
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
-- Name: definition id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY definition ALTER COLUMN id SET DEFAULT nextval('definition_id_seq'::regclass);


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
-- Data for Name: definition; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY definition (id, rule_id) FROM stdin;
1	1
2	2
3	3
4	4
5	5
6	6
7	7
8	11
9	16
10	18
11	20
12	22
13	23
14	24
15	25
16	26
17	27
18	28
19	29
20	30
22	32
25	35
26	36
27	40
28	42
29	43
30	45
31	47
32	48
33	49
34	50
35	53
36	54
37	56
38	57
39	59
\.


--
-- Name: definition_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('definition_id_seq', 39, true);


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
34
\.


--
-- Name: descriptor_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('descriptor_id_seq', 34, true);


--
-- Data for Name: expression; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY expression (id, data, hash, latex, functions, node_type, node_value, node_arguments) FROM stdin;
1	\\x000000000100010009000000000000	\\x43015c596372b689f4f4cefecd30ec1668862206980cb58d65afb225d9c9cbe1	{}_\\text{?}a	{9}	generic	9	{}
2	\\x00000000010001000a000000000000	\\x7411a5ca9021c1572527e434ecfc5439b308a4c41d55e3ee2ce343cf960f5eb4	{}_\\text{?}b	{10}	generic	10	{}
5	\\x0000000003000200090000000a00000003000000000000000200020001	\\x8af96fecdd3af832e9be5b6e7e23e27060e194b300e94a93954ac7e2dc1c2ee1	{}_\\text{?}a-{}_\\text{?}b	{9,10,3}	function	3	{1,2}
6	\\x0000000003000200090000000a00000004000000000000000200020001	\\xa21a2c2ab7610ca971fa03ef17af32bedb693c45c7877bcb7044ebe488983ee5	{}_\\text{?}a{}_\\text{?}b	{9,10,4}	function	4	{1,2}
7	\\x00000000010001000b000000000000	\\x81e70705060646c78a583ab14aabcd545598cbcd420c7973aba1675c2e8b705f	{}_\\text{?}c	{11}	generic	11	{}
8	\\x0000000003000200090000000b00000004000000000000000200020001	\\xb663acd854dc781f7c56f92ffc5a13a6ebb33ca51b0290a1933a94d5212c4639	{}_\\text{?}a{}_\\text{?}c	{9,11,4}	function	4	{1,7}
9	\\x0000000005000300090000000a0000000b00000002000000040000000000000000000200020003040001040002	\\xda3e94d9a6b49580ebd17ab5ea06b39f39587525854be82bfcfa859de1039c21	{}_\\text{?}a{}_\\text{?}b+{}_\\text{?}a{}_\\text{?}c	{9,10,11,2,4}	function	2	{6,8}
10	\\x00000000030002000a0000000b00000002000000000000000200020001	\\x77b5554abc9aee843fabdb8d710fc6601e1ba533ba6f40d2adc25573ffa87c1b	{}_\\text{?}b+{}_\\text{?}c	{10,11,2}	function	2	{2,7}
11	\\x0000000005000300090000000a0000000b0000000400000002000000000000000000020002000300040102	\\x0aa7057218958cccb8a12433b953a3057847686b280a2cd275d8a3302272f883	{}_\\text{?}a\\left({}_\\text{?}b+{}_\\text{?}c\\right)	{9,10,11,4,2}	function	4	{1,10}
13	\\x00000100000000000100000000	\\xcb8c6ede8e7aef082d6b7f80058cc9b51caf8daeea698e065be21383c51065fc	1	{}	integer	1	{}
16	\\x000001000200010001000000090000000600000000000200010002	\\x209140cc8cd71d6d036ba4d6b5f19ec77881b6105cfe09185569ee40cc8020c3	{}_\\text{?}a^{1}	{9,6}	function	6	{1,13}
17	\\x0000000003000200090000000a00000006000000000000000200020001	\\x179655ebc9a1bcc8e05debe8a5658f6c6f5a5a339934ca54eb5e2dc0df1ea618	{}_\\text{?}a^{{}_\\text{?}b}	{9,10,6}	function	6	{1,2}
18	\\x0000000003000200090000000b00000006000000000000000200020001	\\x1a68a647472dc53cf6fbab82825d05945bbc1b46a029514b05127173eb68c1d6	{}_\\text{?}a^{{}_\\text{?}c}	{9,11,6}	function	6	{1,7}
19	\\x0000000005000300090000000a0000000b00000004000000060000000000000000000200020003040001040002	\\xf737887c811816a54bb3ad9658d5ea4b07623762a32802bfbe85dbdd536a1618	{}_\\text{?}a^{{}_\\text{?}b}{}_\\text{?}a^{{}_\\text{?}c}	{9,10,11,4,6}	function	4	{17,18}
20	\\x0000000005000300090000000a0000000b0000000600000002000000000000000000020002000300040102	\\x0846ec457cce9d4c9ed47441fbff1e93670ad5b8f20e649e86579904ddfe839e	{}_\\text{?}a^{{}_\\text{?}b+{}_\\text{?}c}	{9,10,11,6,2}	function	6	{1,10}
21	\\x000000000100010014000000000000	\\xa87b85903b7498010c55645a4a6c27c9309925173a6177bdcb37e9f6e4354ef2	{}_\\text{?}x	{20}	generic	20	{}
22	\\x00000000020002001600000014000000010000000001	\\xf7ad21a772c67ff2678b7e83ba90a5b962cc5487adbba18b082688cc387d7ffe	{}_\\text{?}\\text{f}{\\left({}_\\text{?}x\\right)}	{22,20}	generic	22	{21}
24	\\x00000000020001001400000017000000000001000100	\\x60e62d80304fa9ac770f84c9df8a04815c066b13420feb521878eba6e59b7eda	\\Delta{}_\\text{?}x	{20,23}	function	23	{21}
25	\\x00000100000000000000000000	\\xe0afadbd718beefc7b9ec03c368f7f78a9eae4327d59216840678ede42d2fd96	0	{}	integer	0	{}
26	\\x000000000300010014000000020000001700000000000200010001000200	\\xac989ff477bf681528e055ae65e795bca03aa152aa0206bf442cf589a7ac024a	{}_\\text{?}x+\\Delta{}_\\text{?}x	{20,2,23}	function	2	{21,24}
27	\\x00000000040002001600000014000000020000001700000001000000020001000002010301	\\xfadd710643637b7e3c9172b884784111c44b611f1fc2be9bad580c1477ff9666	{}_\\text{?}\\text{f}{\\left({}_\\text{?}x+\\Delta{}_\\text{?}x\\right)}	{22,20,2,23}	generic	22	{26}
28	\\x00000000050002001600000014000000030000000200000017000000010000000200020001000200030104010001	\\xc02fcd98f76ef3854b6c11f1ad0369f6704de620e3a2236e6655d1bf30d13124	{}_\\text{?}\\text{f}{\\left({}_\\text{?}x+\\Delta{}_\\text{?}x\\right)}-{}_\\text{?}\\text{f}{\\left({}_\\text{?}x\\right)}	{22,20,3,2,23}	function	3	{27,22}
29	\\x00000000060002001600000014000000050000000300000002000000170000000100000002000200020001000203000401050100010501	\\x9a705a3331eec10cdd8b82a01f7833b787395e50064fea1ed1f64c6ad9b122b9	\\frac{~{}_\\text{?}\\text{f}{\\left({}_\\text{?}x+\\Delta{}_\\text{?}x\\right)}-{}_\\text{?}\\text{f}{\\left({}_\\text{?}x\\right)}~}{~\\Delta{}_\\text{?}x~}	{22,20,5,3,2,23}	function	5	{28,24}
30	\\x000001000700020000000000140000001600000018000000170000000500000003000000020000000000010003000100020002000200020300070405010600030001000300	\\x0c0208b22a214904a0a0c2ded23fba5a80dec90381e229f3d98a6b03c898df4d	\\lim_{\\Delta{}_\\text{?}x\\to0}\\frac{~{}_\\text{?}\\text{f}{\\left({}_\\text{?}x+\\Delta{}_\\text{?}x\\right)}-{}_\\text{?}\\text{f}{\\left({}_\\text{?}x\\right)}~}{~\\Delta{}_\\text{?}x~}	{20,22,24,23,5,3,2}	function	24	{24,25,29}
31	\\x0000000003000200090000000a00000002000000000000000200020001	\\xbbc12982203caf5c28570b4b7572807cb104402f42592fbf8e89f78b515dc6be	{}_\\text{?}a+{}_\\text{?}b	{9,10,2}	function	2	{1,2}
32	\\x0000000005000300090000000a0000000b0000000100000002000000000000000000020002000304000102	\\x3016de2afffb248f1ea49db18fd6195b302570e3ae88e30f8b76342c10805094	{}_\\text{?}a+{}_\\text{?}b={}_\\text{?}c	{9,10,11,1,2}	function	1	{31,7}
33	\\x00000000030002000b0000000a00000003000000000000000200020001	\\x23285930815435e505a21977f2f204227e504baca69f65c92a12c89fffdbe338	{}_\\text{?}c-{}_\\text{?}b	{11,10,3}	function	3	{7,2}
34	\\x0000000005000300090000000b0000000a0000000100000003000000000000000000020002000300040102	\\xd069cd39c47b53d1aafbf0166e90bf5b6e00b9450a793b22eed278f3525fac3c	{}_\\text{?}a={}_\\text{?}c-{}_\\text{?}b	{9,11,10,1,3}	function	1	{1,33}
35	\\x0000000002000100090000000400000000000200010000	\\x0ae10431daf1fbea1a3744536130d7e98fa9347dcff9278b3d463aa92a355e99	{}_\\text{?}a{}_\\text{?}a	{9,4}	function	4	{1,1}
36	\\x0000010003000100010000000900000004000000060000000000020002000100020003	\\x4ec5cfd089fbb50f6e2cac611494fba37d8c929dcdefff42605895513b9e52d3	{}_\\text{?}a{}_\\text{?}a^{1}	{9,4,6}	function	4	{1,16}
37	\\x00000100030001000100000009000000040000000600000000000200020001020003020003	\\xb4a8ec20c55c1f0bdd7564854c0b84b5400c82a7cc067b2a65dd84f7c3b7bc1c	{}_\\text{?}a^{1}{}_\\text{?}a^{1}	{9,4,6}	function	4	{16,16}
38	\\x00000100000000000200000000	\\xe62115b1b0a0940392fe419abadbc906d524d2f5e005ce2c982949ac518fc3d2	2	{}	integer	2	{}
39	\\x000001000200010002000000090000000600000000000200010002	\\x4d211308d49e14146f22cea3417f83f8fca62aa4a86d2aeb420427cfb73a1a76	{}_\\text{?}a^{2}	{9,6}	function	6	{1,38}
40	\\x00000000030002000a0000000900000002000000000000000200020001	\\x1c0822992da41678b0205742c498897c9eba47acc1d317bd1c36c3b7ecbaa54d	{}_\\text{?}b+{}_\\text{?}a	{10,9,2}	function	2	{2,1}
205	\\x0000000003000100090000000400000010000000000002000000010200	\\x986400b08f6f03a301a67844f07d179a37584bbae97bd1506550b9b159b9fdba	r{}_\\text{?}a	{9,4,16}	function	4	{161,1}
41	\\x00000000050003000a000000090000000b0000000100000002000000000000000000020002000304000102	\\x2a6e5af7d3b037582af6a5d0500341f4691156fa1d845f271665bde426bd57ff	{}_\\text{?}b+{}_\\text{?}a={}_\\text{?}c	{10,9,11,1,2}	function	1	{40,7}
42	\\x00000000030002000b0000000900000003000000000000000200020001	\\xb841f29e36d50117eb657ad10b5213b3d9ebcf9899a134a0c79660d15179bd0c	{}_\\text{?}c-{}_\\text{?}a	{11,9,3}	function	3	{7,1}
43	\\x00000000050003000a0000000b000000090000000100000003000000000000000000020002000300040102	\\x42654eee6a95a16987fd329b3a26f3b6b65762fb0f5be2e5fbf41014e676ee63	{}_\\text{?}b={}_\\text{?}c-{}_\\text{?}a	{10,11,9,1,3}	function	1	{2,42}
44	\\x00000000030002000a0000000900000004000000000000000200020001	\\x5ab22a4e6f77880af3916b063e9d5e84e4b5506e2743a9998d8d966a3211f487	{}_\\text{?}b{}_\\text{?}a	{10,9,4}	function	4	{2,1}
45	\\x00000000030002000b0000000900000004000000000000000200020001	\\xc9f19246a00f2ff5de24694aa5fe9bceece277c795866b24871992c5bf0fd9aa	{}_\\text{?}c{}_\\text{?}a	{11,9,4}	function	4	{7,1}
46	\\x00000000050003000a000000090000000b00000002000000040000000000000000000200020003040001040201	\\x0b483f5d5c667875d4a5c63591958b7af91d144572fcb8d98e07cfbb8a267691	{}_\\text{?}b{}_\\text{?}a+{}_\\text{?}c{}_\\text{?}a	{10,9,11,2,4}	function	2	{44,45}
47	\\x00000000050003000a000000090000000b00000002000000040000000000000000000200020003040001040102	\\x83083f81df6fae38a050ff7e725fcceb6443c40c4b1102c190458e27a73cb40b	{}_\\text{?}b{}_\\text{?}a+{}_\\text{?}a{}_\\text{?}c	{10,9,11,2,4}	function	2	{44,8}
48	\\x000001000200010001000000090000000400000000000200010200	\\xf69e3da77bef6544638d46b6830955372b6998c4df20f1c75737895df6774b60	1{}_\\text{?}a	{9,4}	function	4	{13,1}
49	\\x00000000050003000a0000000b000000090000000400000002000000000000000000020002000304000102	\\x8258c3049688cb400172c5f296bf389d67a5868dc85df11832df355dc9bb23fe	\\left({}_\\text{?}b+{}_\\text{?}c\\right){}_\\text{?}a	{10,11,9,4,2}	function	4	{10,1}
50	\\x0000000002000100090000000200000000000200010000	\\xea3524b07551e5b7330386455760cfe4902f4af00ebd3cf58c59673edd54e569	{}_\\text{?}a+{}_\\text{?}a	{9,2}	function	2	{1,1}
51	\\x0000010003000100010000000900000002000000040000000000020002000100020300	\\xf5a4ccbc4969c20336995c79f3004bd1b0b7eabd6747cbc509695feca3b20bbb	{}_\\text{?}a+1{}_\\text{?}a	{9,2,4}	function	2	{1,48}
52	\\x00000100030001000100000009000000020000000400000000000200020001020300020300	\\xfe23c1b9a154d031192853453aa034ac20fb167f37f276fbfda17dd4c40e634c	1{}_\\text{?}a+1{}_\\text{?}a	{9,2,4}	function	2	{48,48}
53	\\x000001000200010002000000090000000400000000000200010200	\\xc483d6efc03b7e59e8eda204304b6737b0369bf0bc046e8da7653e461f0fca5d	2{}_\\text{?}a	{9,4}	function	4	{38,1}
54	\\x000001000400020002000000090000000a000000060000000200000000000000020002000203000104	\\xd313f6f7ee11b69056ae1c1d658fa344fdbbc21214cb809f5fc385adcffcba9f	\\left({}_\\text{?}a+{}_\\text{?}b\\right)^{2}	{9,10,6,2}	function	6	{31,38}
55	\\x0000000004000200090000000a0000000400000002000000000000000200020002030001030001	\\x2074eb1268de9b79d2324bba90da55d8c90777241361e3af6266264c521ad697	\\left({}_\\text{?}a+{}_\\text{?}b\\right)\\left({}_\\text{?}a+{}_\\text{?}b\\right)	{9,10,4,2}	function	4	{31,31}
56	\\x0000000004000200090000000a000000040000000200000000000000020002000200030001	\\xa4ea8baad251ef6ddd790d3a0dc0784eec70d0ea6eb2d1d0240e0c6f88c649db	{}_\\text{?}a\\left({}_\\text{?}a+{}_\\text{?}b\\right)	{9,10,4,2}	function	4	{1,31}
57	\\x00000000040002000a00000009000000040000000200000000000000020002000200030100	\\xcd170f1ab702d2b70754953773b17866c7ea24331a73fe6c6f5c6fc278f7ecd1	{}_\\text{?}b\\left({}_\\text{?}a+{}_\\text{?}b\\right)	{10,9,4,2}	function	4	{2,31}
58	\\x0000000004000200090000000a000000020000000400000000000000020002000203000200010301020001	\\x8afbfe93a9bceaa76915a83dc8ef9ad7b2b40a32383b1cce59e03fcc6cf4d939	{}_\\text{?}a\\left({}_\\text{?}a+{}_\\text{?}b\\right)+{}_\\text{?}b\\left({}_\\text{?}a+{}_\\text{?}b\\right)	{9,10,2,4}	function	2	{56,57}
59	\\x00000000020001000a0000000400000000000200010000	\\x2a8af03c97229e276d4d5fa76a171cc377aa5b2acdd63f8d7c6a8f38d2f529fe	{}_\\text{?}b{}_\\text{?}b	{10,4}	function	4	{2,2}
60	\\x00000000040002000a000000090000000200000004000000000000000200020002030001030000	\\x06ee2312065ec06e667b3dffda8e9e27841ccea26e620dea82c87367a749c204	{}_\\text{?}b{}_\\text{?}a+{}_\\text{?}b{}_\\text{?}b	{10,9,2,4}	function	2	{44,59}
61	\\x0000000004000200090000000a0000000200000004000000000000000200020002030002000102030100030101	\\xae4bff0f3f4385e10f5aa78618091c28bbfa3468d03949021ea63bfed9d18c54	{}_\\text{?}a\\left({}_\\text{?}a+{}_\\text{?}b\\right)+\\left({}_\\text{?}b{}_\\text{?}a+{}_\\text{?}b{}_\\text{?}b\\right)	{9,10,2,4}	function	2	{56,60}
62	\\x0000000004000200090000000a0000000200000004000000000000000200020002030000030001	\\x71cbe01cc8f7d354ae6f879a6cbf0c90fc2842d1327fa126ef2d8d959fe3e86f	{}_\\text{?}a{}_\\text{?}a+{}_\\text{?}a{}_\\text{?}b	{9,10,2,4}	function	2	{35,6}
63	\\x0000000004000200090000000a00000002000000040000000000000002000200020203000003000102030100030101	\\xe271693f9533856f25ed61e14e3f0779c42cd68ba685bea9b6848b59e3fa91b6	{}_\\text{?}a{}_\\text{?}a+{}_\\text{?}a{}_\\text{?}b+\\left({}_\\text{?}b{}_\\text{?}a+{}_\\text{?}b{}_\\text{?}b\\right)	{9,10,2,4}	function	2	{62,60}
64	\\x0000000004000200090000000a0000000200000004000000000000000200020002030001030100	\\xea1bb62f8fb69468b41fb4fc810d81ae4b604531e1b6bf1840fdc0957613a040	{}_\\text{?}a{}_\\text{?}b+{}_\\text{?}b{}_\\text{?}a	{9,10,2,4}	function	2	{6,44}
65	\\x0000000004000200090000000a000000020000000400000000000000020002000203000002030001030100	\\xe816ece46b40654c8ad0a9153a234029da963d1e5db29e5c08b2550842cd4bdf	{}_\\text{?}a{}_\\text{?}a+\\left({}_\\text{?}a{}_\\text{?}b+{}_\\text{?}b{}_\\text{?}a\\right)	{9,10,2,4}	function	2	{35,64}
66	\\x0000000004000200090000000a00000002000000040000000000000002000200020203000002030001030100030101	\\xb046ec346346771815b2e8efb9c049a0e3872b315b989e4b0a7d82c37a6fef54	{}_\\text{?}a{}_\\text{?}a+\\left({}_\\text{?}a{}_\\text{?}b+{}_\\text{?}b{}_\\text{?}a\\right)+{}_\\text{?}b{}_\\text{?}b	{9,10,2,4}	function	2	{65,59}
67	\\x0000000004000200090000000a0000000200000004000000000000000200020002030001030001	\\xfd3e76a6a346e596e5aa8cdf9a293cf0b92d806893e5b63f471d323855707d6e	{}_\\text{?}a{}_\\text{?}b+{}_\\text{?}a{}_\\text{?}b	{9,10,2,4}	function	2	{6,6}
68	\\x0000000004000200090000000a000000020000000400000000000000020002000203000002030001030001	\\xab02f94d23d66ec33060af3985e4fc57963e0d003f93ad23a7ce6a851b98455f	{}_\\text{?}a{}_\\text{?}a+\\left({}_\\text{?}a{}_\\text{?}b+{}_\\text{?}a{}_\\text{?}b\\right)	{9,10,2,4}	function	2	{35,67}
69	\\x0000000004000200090000000a00000002000000040000000000000002000200020203000002030001030001030101	\\x151ee194319544fce3a02a9e93f0b42b5823093bae446153cbb79e48727b9aa8	{}_\\text{?}a{}_\\text{?}a+\\left({}_\\text{?}a{}_\\text{?}b+{}_\\text{?}a{}_\\text{?}b\\right)+{}_\\text{?}b{}_\\text{?}b	{9,10,2,4}	function	2	{68,59}
70	\\x0000010002000100020000000a0000000600000000000200010002	\\x7e4376c3449ddfadfd4229cd1954411a1b59a1a8d74e30c993b857bf1c8cc6a8	{}_\\text{?}b^{2}	{10,6}	function	6	{2,38}
71	\\x000001000500020002000000090000000a00000002000000040000000600000000000000020002000200020203000002030001030001040105	\\x40eedbba961b2989927596839dfdbdcf01aa17a5305c6159c7373177f129f06b	{}_\\text{?}a{}_\\text{?}a+\\left({}_\\text{?}a{}_\\text{?}b+{}_\\text{?}a{}_\\text{?}b\\right)+{}_\\text{?}b^{2}	{9,10,2,4,6}	function	2	{68,70}
72	\\x000001000300020002000000090000000a000000040000000000000002000203020001	\\x061437dcbcd38a8878bb7ca3ce6eb5c21cbbf11def26ade399e7908464b6cf2f	2\\left({}_\\text{?}a{}_\\text{?}b\\right)	{9,10,4}	function	4	{38,6}
73	\\x000001000400020002000000090000000a00000002000000040000000000000002000200020300000304030001	\\xd117a3ccc4e14bc31191ea4540552440278b55431ba11a78e5c2d2c37b00218a	{}_\\text{?}a{}_\\text{?}a+2\\left({}_\\text{?}a{}_\\text{?}b\\right)	{9,10,2,4}	function	2	{35,72}
74	\\x000001000500020002000000090000000a0000000200000004000000060000000000000002000200020002020300000305030001040105	\\xf11e3a258819b2882bbb3b9b0d6793e1c9719a9a9bf8d51d545abd3089677394	{}_\\text{?}a{}_\\text{?}a+2\\left({}_\\text{?}a{}_\\text{?}b\\right)+{}_\\text{?}b^{2}	{9,10,2,4,6}	function	2	{73,70}
75	\\x000001000500020002000000090000000a00000002000000060000000400000000000000020002000200020300050405040001	\\xd885d6e7c27ea77f527713a27b361f1ce1644399f3df4d839d1c4b406618754a	{}_\\text{?}a^{2}+2\\left({}_\\text{?}a{}_\\text{?}b\\right)	{9,10,2,6,4}	function	2	{39,72}
76	\\x000001000500020002000000090000000a0000000200000006000000040000000000000002000200020002020300050405040001030105	\\x677d41e596887be58bc74465aa0f8de4d6b33473c86b854f52b190273e3bb39e	{}_\\text{?}a^{2}+2\\left({}_\\text{?}a{}_\\text{?}b\\right)+{}_\\text{?}b^{2}	{9,10,2,6,4}	function	2	{75,70}
77	\\x000001000300020002000000090000000a000000040000000000000002000202030001	\\x16a2aa9ed030f0cffd910d289ea46fa10475798b7b2a7cdd7a1a7cf9abf2a959	2{}_\\text{?}a{}_\\text{?}b	{9,10,4}	function	4	{53,2}
78	\\x000001000500020002000000090000000a00000002000000060000000400000000000000020002000200020300050404050001	\\x343c15e0a2fa90b24abf2c531d6ed512d6684b7a8ac30c268004180c82b23e6b	{}_\\text{?}a^{2}+2{}_\\text{?}a{}_\\text{?}b	{9,10,2,6,4}	function	2	{39,77}
79	\\x000001000500020002000000090000000a0000000200000006000000040000000000000002000200020002020300050404050001030105	\\xe86dabb335751acfd48c86437475e903d1924d8a26b32c525792e706a1a7f7a5	{}_\\text{?}a^{2}+2{}_\\text{?}a{}_\\text{?}b+{}_\\text{?}b^{2}	{9,10,2,6,4}	function	2	{78,70}
80	\\x000001000200010000000000090000000400000000000200010200	\\x77ca76e6b8c82d47b148ca0b4ada2224dce12fec41fa2a4e2b1b2da36a4fd5a1	0{}_\\text{?}a	{9,4}	function	4	{25,1}
81	\\x0000000002000100090000000300000000000200010000	\\xb07f2e67b317e0a7480efcc06791dd124780b23f8d64510676e4d2d1bea3b5cc	{}_\\text{?}a-{}_\\text{?}a	{9,3}	function	3	{1,1}
83	\\x0000010000000000ffffffff00	\\xa9015325dd84a5fe32a973b297d83926289efe354948451371a303d3ee305184	-1	{}	integer	-1	{}
84	\\x0000010002000100ffffffff090000000400000000000200010200	\\x053d4fae4c8a0b210c534d9743d824995f79795e073a0adeca8c3c59a126092e	-1{}_\\text{?}a	{9,4}	function	4	{83,1}
85	\\x0000010003000100ffffffff0900000002000000040000000000020002000100020300	\\xaa5abe7aaea2e725fea5a476562ff984766fd24dda32297eee92ef85602d0935	{}_\\text{?}a+-1{}_\\text{?}a	{9,2,4}	function	2	{1,84}
86	\\x000002000300010001000000ffffffff09000000020000000400000000000200020001020300020400	\\x3099c740ea0b4396ffa11c0cf5c6bafa9e81bf028192446cebbe95515ca12167	1{}_\\text{?}a+-1{}_\\text{?}a	{9,2,4}	function	2	{48,84}
87	\\x000001000200010000000000090000000200000000000200010002	\\x182374522020321381c4df9d629cb67f7166efb02e48e6810ca7539aedecb71b	{}_\\text{?}a+0	{9,2}	function	2	{1,25}
88	\\x000001000200010000000000090000000200000000000200010200	\\xc1643dedd639c96950f9dc40955b094ee6f7c686847444dbdb5b168e60218586	0+{}_\\text{?}a	{9,2}	function	2	{25,1}
89	\\x0000000004000200090000000a000000050000000400000000000000020002000203000101	\\xa2c62db2f2d6d6f67dc6c08ae19fd72390fe58dbf84c858ec45deadc5e8953b2	\\frac{~{}_\\text{?}a{}_\\text{?}b~}{~{}_\\text{?}b~}	{9,10,5,4}	function	5	{6,2}
90	\\x00000000040002000a00000009000000050000000400000000000000020002000203000100	\\xb9e626c400d02409898b614499a4dfa4e8b7e3622d85a81476959832767c249b	\\frac{~{}_\\text{?}b{}_\\text{?}a~}{~{}_\\text{?}b~}	{10,9,5,4}	function	5	{44,2}
91	\\x000000000100010015000000000000	\\x90f5e58b9c74fdbc76e008c0f556e88fca176f2c9f8f53474e1edb69caa15cda	{}_\\text{?}y	{21}	generic	21	{}
92	\\x0000000003000200140000001500000002000000000000000200020001	\\xd50ef21beb2ab7f1df2ec2c64c83e36c71b4731cd99ae2feef1c0c1607b47ff5	{}_\\text{?}x+{}_\\text{?}y	{20,21,2}	function	2	{21,91}
93	\\x0000000006000400090000000a00000014000000150000001800000002000000000000000000000003000200040001050203	\\xad31e54dab7cc0ff194c49220bb39573b718e9807813677b16dca85a2ddc9ff6	\\lim_{{}_\\text{?}a\\to{}_\\text{?}b}{}_\\text{?}x+{}_\\text{?}y	{9,10,20,21,24,2}	function	24	{1,2,92}
94	\\x0000000004000300090000000a0000001400000018000000000000000000030003000102	\\xa2d6fedb431cda508340d8a47b38cf8a91ad854264eb25d1e8cc9ef3a0b10b20	\\lim_{{}_\\text{?}a\\to{}_\\text{?}b}{}_\\text{?}x	{9,10,20,24}	function	24	{1,2,21}
95	\\x0000000004000300090000000a0000001500000018000000000000000000030003000102	\\x538389d041f9a918fc7097615b3c56bb12398a35e05767ad96ae50d10c3c2818	\\lim_{{}_\\text{?}a\\to{}_\\text{?}b}{}_\\text{?}y	{9,10,21,24}	function	24	{1,2,91}
96	\\x0000000006000400090000000a00000014000000150000000200000018000000000000000000000002000300040500010205000103	\\x14e403d209228f4b9f9d60ed0b0ae8172be49c94b3eae2bef413f27d94457b89	\\lim_{{}_\\text{?}a\\to{}_\\text{?}b}{}_\\text{?}x+\\lim_{{}_\\text{?}a\\to{}_\\text{?}b}{}_\\text{?}y	{9,10,20,21,2,24}	function	2	{94,95}
97	\\x00000100020001000000000009000000180000000000030001000200	\\x831542a9312e8ad531d8961f240ae37d1c11d946abea2abf2552688a9549fe9a	\\lim_{{}_\\text{?}a\\to0}{}_\\text{?}a	{9,24}	function	24	{1,25,1}
98	\\x0000000004000300090000000a0000000b00000018000000000000000000030003000102	\\x3e53d1602910c3f6bdb4d33a5654feec2993e915ddc23033e8eab0ce184683f1	\\lim_{{}_\\text{?}a\\to{}_\\text{?}b}{}_\\text{?}c	{9,10,11,24}	function	24	{1,2,7}
99	\\x000001000200010002000000140000000600000000000200010002	\\x62f9298814fbef0f07ab742113e462589c79abee85888c323acf0ee16c3c835b	{}_\\text{?}x^{2}	{20,6}	function	6	{21,38}
101	\\x000001000400010002000000140000000600000002000000170000000000020002000100010200030004	\\x9bd492f217b15d49887878b8e8ae6655d74c48fcc20bd333bf5db78a6dcffe99	\\left({}_\\text{?}x+\\Delta{}_\\text{?}x\\right)^{2}	{20,6,2,23}	function	6	{26,38}
102	\\x00000100050001000200000014000000030000000600000002000000170000000000020002000200010001020300040005020005	\\x7ff40cbef836b450e7d7dd14710db2d3c9077b9e968d47d64f83ccdc799e6d21	\\left({}_\\text{?}x+\\Delta{}_\\text{?}x\\right)^{2}-{}_\\text{?}x^{2}	{20,3,6,2,23}	function	3	{101,99}
103	\\x00000100060001000200000014000000050000000300000006000000020000001700000000000200020002000200010001020304000500060300060500	\\xc7bdbafa893b8ac67e6deefffb5458f9466e973f00fb2894906711f4abad9f16	\\frac{~\\left({}_\\text{?}x+\\Delta{}_\\text{?}x\\right)^{2}-{}_\\text{?}x^{2}~}{~\\Delta{}_\\text{?}x~}	{20,5,3,6,2,23}	function	5	{102,24}
104	\\x000002000700010000000000020000001400000018000000170000000500000003000000060000000200000000000300010002000200020002000102000703040506000200080500080200	\\x351ceb2ad9c51cd8e45cd2720ec583fbb024088926f31f4c1869c1f25e770974	\\lim_{\\Delta{}_\\text{?}x\\to0}\\frac{~\\left({}_\\text{?}x+\\Delta{}_\\text{?}x\\right)^{2}-{}_\\text{?}x^{2}~}{~\\Delta{}_\\text{?}x~}	{20,24,23,5,3,6,2}	function	24	{24,25,103}
105	\\x000001000200010002000000140000000400000000000200010200	\\x09d3bdc3f0c9c1619427642cd6e36261bde78ddbc183e3b4cd6bcfd4cc7775a6	2{}_\\text{?}x	{20,4}	function	4	{38,21}
106	\\x000001000300010002000000140000000400000017000000000002000100010103000200	\\xa3997211da42cd177c865dee749ed753152b2706c7bbffe4cd0cdcb565b9dd15	2{}_\\text{?}x\\Delta{}_\\text{?}x	{20,4,23}	function	4	{105,24}
107	\\x00000100050001000200000014000000020000000600000004000000170000000000020002000200010001020005030305000400	\\x087aee94a74e8d96c216dd7de20192e0a2dffbb88a0657a83e603437d21a1e5f	{}_\\text{?}x^{2}+2{}_\\text{?}x\\Delta{}_\\text{?}x	{20,2,6,4,23}	function	2	{99,106}
108	\\x00000100030001000200000014000000060000001700000000000200010001020003	\\x99ea7d6d5b9b5b91993ca47a142a9c6de63f98a3c70b75e96af8d806ab56924a	\\Delta{}_\\text{?}x^{2}	{20,6,23}	function	6	{24,38}
109	\\x000001000500010002000000140000000200000006000000040000001700000000000200020002000100010102000503030500040002040005	\\xca8cc9e7abbce3578344c75b29e0e821f2131de81a3378625fb015f7dba765ef	{}_\\text{?}x^{2}+2{}_\\text{?}x\\Delta{}_\\text{?}x+\\Delta{}_\\text{?}x^{2}	{20,2,6,4,23}	function	2	{107,108}
110	\\x00000100060001000200000014000000030000000200000006000000040000001700000000000200020002000200010001020203000604040600050003050006030006	\\x2cac67207636a99b319b26136644dcada790debb3af306e3a83c4a03fb786e49	{}_\\text{?}x^{2}+2{}_\\text{?}x\\Delta{}_\\text{?}x+\\Delta{}_\\text{?}x^{2}-{}_\\text{?}x^{2}	{20,3,2,6,4,23}	function	3	{109,99}
82	\\x000000000300010009000000020000000700000000000200010001000200	\\x6dbf3c8a1aeeb0bc0579c53b92ddafb8fbd7ac26a0a5a0ac74f0d64aa40f1a4e	\N	{9,2,7}	function	2	{1,12}
111	\\x00000100070001000200000014000000050000000300000002000000060000000400000017000000000002000200020002000200010001020303040007050507000600040600070400070600	\\x467eff6acd76043c81fd91e933923fc0b2ce17295447493ef2878d414be9c8b8	\\frac{~{}_\\text{?}x^{2}+2{}_\\text{?}x\\Delta{}_\\text{?}x+\\Delta{}_\\text{?}x^{2}-{}_\\text{?}x^{2}~}{~\\Delta{}_\\text{?}x~}	{20,5,3,2,6,4,23}	function	5	{110,24}
112	\\x000002000800010000000000020000001400000018000000170000000500000003000000020000000600000004000000000003000100020002000200020002000102000803040505060009070709000200060200090600090200	\\xa1b4275852b515902638977fa8eab85188859d38d785cfbfc86964e1b00b923f	\\lim_{\\Delta{}_\\text{?}x\\to0}\\frac{~{}_\\text{?}x^{2}+2{}_\\text{?}x\\Delta{}_\\text{?}x+\\Delta{}_\\text{?}x^{2}-{}_\\text{?}x^{2}~}{~\\Delta{}_\\text{?}x~}	{20,24,23,5,3,2,6,4}	function	24	{24,25,111}
122	\\x00000000030001001400000004000000170000000000020001000102000200	\\x56804013f2b251de4d803b3f097ae2d7e58e21a50746925bbabd1fbafcbc2ec2	\\Delta{}_\\text{?}x\\Delta{}_\\text{?}x	{20,4,23}	function	4	{24,24}
126	\\x00000100030001000200000014000000030000000600000000000200020001020003020003	\\x7951756a07cb0f2580d1f286ca9ef9e279fb4615d82b3b65756dc83a941ddd3a	{}_\\text{?}x^{2}-{}_\\text{?}x^{2}	{20,3,6}	function	3	{99,99}
127	\\x0000010006000100020000001400000002000000030000000600000004000000170000000000020002000200020001000102030006030006040406000500	\\xc67dd806e469dbade6c9e9aca1eb9f9f9da5ffaab37f5ac16d278671bd11cd73	{}_\\text{?}x^{2}-{}_\\text{?}x^{2}+2{}_\\text{?}x\\Delta{}_\\text{?}x	{20,2,3,6,4,23}	function	2	{126,106}
128	\\x0000010006000100020000001400000002000000030000000600000004000000170000000000020002000200020001000101020300060300060404060005000405000500	\\x44449858767c42dbd6f161dda26698c9d90fff4a303e11347fecb69aa175ec24	{}_\\text{?}x^{2}-{}_\\text{?}x^{2}+2{}_\\text{?}x\\Delta{}_\\text{?}x+\\Delta{}_\\text{?}x\\Delta{}_\\text{?}x	{20,2,3,6,4,23}	function	2	{127,122}
129	\\x0000010007000100020000001400000005000000020000000300000006000000040000001700000000000200020002000200020001000102020304000704000705050700060005060006000600	\\x45936a973cf51349bb8bf87c11a1c7389d6eea748a9f07386a0b49f9a35661d1	\\frac{~{}_\\text{?}x^{2}-{}_\\text{?}x^{2}+2{}_\\text{?}x\\Delta{}_\\text{?}x+\\Delta{}_\\text{?}x\\Delta{}_\\text{?}x~}{~\\Delta{}_\\text{?}x~}	{20,5,2,3,6,4,23}	function	5	{128,24}
130	\\x00000200080001000000000002000000140000001800000017000000050000000200000003000000060000000400000000000300010002000200020002000200010200080304040506000906000907070900020007020002000200	\\xce3d479939f05e03595746bfe35dc3c8d336e1d63101c3a01c13bcc659d779ca	\\lim_{\\Delta{}_\\text{?}x\\to0}\\frac{~{}_\\text{?}x^{2}-{}_\\text{?}x^{2}+2{}_\\text{?}x\\Delta{}_\\text{?}x+\\Delta{}_\\text{?}x\\Delta{}_\\text{?}x~}{~\\Delta{}_\\text{?}x~}	{20,24,23,5,2,3,6,4}	function	24	{24,25,129}
131	\\x000002000400010000000000020000001400000002000000040000001700000000000200020001000104020205000300	\\x9bc5569247c9f95b81ef25e4ce4b533940c056ff2ecbde14d95bf5da611aed88	0+2{}_\\text{?}x\\Delta{}_\\text{?}x	{20,2,4,23}	function	2	{25,106}
132	\\x000002000400010000000000020000001400000002000000040000001700000000000200020001000101040202050003000203000300	\\xf85d35fbd3b59ff39b8bb086d04a41e9eb06c01386ed676d1a261acc55d8533a	0+2{}_\\text{?}x\\Delta{}_\\text{?}x+\\Delta{}_\\text{?}x\\Delta{}_\\text{?}x	{20,2,4,23}	function	2	{131,122}
133	\\x000002000500010000000000020000001400000005000000020000000400000017000000000002000200020001000102020503030600040003040004000400	\\x86c4b9c99e163ccdf5750ca13b0b538746b4d61ccc25dcc94ef19ee02c8e18bd	\\frac{~0+2{}_\\text{?}x\\Delta{}_\\text{?}x+\\Delta{}_\\text{?}x\\Delta{}_\\text{?}x~}{~\\Delta{}_\\text{?}x~}	{20,5,2,4,23}	function	5	{132,24}
134	\\x00000200060001000000000002000000140000001800000017000000050000000200000004000000000003000100020002000200010200060304040605050700020005020002000200	\\xa5a6ef549d77a84c0aa9c6c2dc1cfa4e9952175e7a0453e8336abbd25f27db55	\\lim_{\\Delta{}_\\text{?}x\\to0}\\frac{~0+2{}_\\text{?}x\\Delta{}_\\text{?}x+\\Delta{}_\\text{?}x\\Delta{}_\\text{?}x~}{~\\Delta{}_\\text{?}x~}	{20,24,23,5,2,4}	function	24	{24,25,133}
212	\\x00000000020001000a00000012000000000001000100	\\xa47dac51c4e36a952bfe2a0997aea71e7608d6d8ae93b9be55a2945011a5e202	\N	{10,18}	function	18	{2}
135	\\x000001000400010002000000140000000200000004000000170000000000020002000100010202040003000203000300	\\x7638e064865e8dc2b19098e3b68f8539c09a7630ade80975bfc10d4951785c38	2{}_\\text{?}x\\Delta{}_\\text{?}x+\\Delta{}_\\text{?}x\\Delta{}_\\text{?}x	{20,2,4,23}	function	2	{106,122}
136	\\x000001000500010002000000140000000500000002000000040000001700000000000200020002000100010203030500040003040004000400	\\x5cfea19f3d819017eba3b28ebe9d56394bfeffc4aa70b991588b3110d264ece7	\\frac{~2{}_\\text{?}x\\Delta{}_\\text{?}x+\\Delta{}_\\text{?}x\\Delta{}_\\text{?}x~}{~\\Delta{}_\\text{?}x~}	{20,5,2,4,23}	function	5	{135,24}
137	\\x0000020006000100000000000200000014000000180000001700000005000000020000000400000000000300010002000200020001020006030405050700020005020002000200	\\x97f975f39048799a512d0605cc3c7393dcf9c8fb192519edb0994b6609bdcd1b	\\lim_{\\Delta{}_\\text{?}x\\to0}\\frac{~2{}_\\text{?}x\\Delta{}_\\text{?}x+\\Delta{}_\\text{?}x\\Delta{}_\\text{?}x~}{~\\Delta{}_\\text{?}x~}	{20,24,23,5,2,4}	function	24	{24,25,136}
138	\\x000001000400010002000000140000000200000004000000170000000000020002000100010204000300	\\x2774ff4e892ea728d6a1cd93a023b4234d3ad692479d06a9adb95d53429eff41	2{}_\\text{?}x+\\Delta{}_\\text{?}x	{20,2,4,23}	function	2	{105,24}
139	\\x000001000400010002000000140000000400000017000000020000000000020001000200010200030104000200	\\xdaf09486a3f940cbe1e6d57230e50f6b7b140e185b202ba457544dda4052fd53	\\Delta{}_\\text{?}x\\left(2{}_\\text{?}x+\\Delta{}_\\text{?}x\\right)	{20,4,23,2}	function	4	{24,138}
140	\\x000001000500010002000000140000000500000004000000170000000200000000000200020001000200010203000402050003000300	\\x6cea61c480b4db312f1a8deba0deea106ea75d6d214852294ebdacaf3001d5c4	\\frac{~\\Delta{}_\\text{?}x\\left(2{}_\\text{?}x+\\Delta{}_\\text{?}x\\right)~}{~\\Delta{}_\\text{?}x~}	{20,5,4,23,2}	function	5	{139,24}
141	\\x0000020006000100000000000200000014000000180000001700000005000000040000000200000000000300010002000200020001020006030402000504070002000200	\\xd1b239b6194646971c0fb492b728b1653f74e5be09babc6ccd47f012dc89d234	\\lim_{\\Delta{}_\\text{?}x\\to0}\\frac{~\\Delta{}_\\text{?}x\\left(2{}_\\text{?}x+\\Delta{}_\\text{?}x\\right)~}{~\\Delta{}_\\text{?}x~}	{20,24,23,5,4,2}	function	24	{24,25,140}
142	\\x0000020005000100000000000200000014000000180000001700000002000000040000000000030001000200020001020005030406000200	\\xde4b50707672a9a9b88dbe1996e52c023acc498a4d51d176e7b2cbbbbf60b26e	\\lim_{\\Delta{}_\\text{?}x\\to0}2{}_\\text{?}x+\\Delta{}_\\text{?}x	{20,24,23,2,4}	function	24	{24,25,138}
143	\\x0000020004000100000000000200000014000000180000001700000004000000000003000100020001020004030500	\\x8f608aa1da0c1d683be164402dbd3862f781d95d5fb27e8ba0d9444a2e6d81c8	\\lim_{\\Delta{}_\\text{?}x\\to0}2{}_\\text{?}x	{20,24,23,4}	function	24	{24,25,105}
144	\\x000001000300010000000000140000001800000017000000000003000100010200030200	\\xfeb0863162059a594fe4a202fc28ff687abba4a4defa28dbdcf70626064ea62a	\\lim_{\\Delta{}_\\text{?}x\\to0}\\Delta{}_\\text{?}x	{20,24,23}	function	24	{24,25,24}
145	\\x000002000500010000000000020000001400000002000000180000001700000004000000000002000300010002000102030005040600020300050300	\\xf7f5723c790985d130f6e5dc254e8fa33a2937d3c33ebee065b54d32e272f101	\\lim_{\\Delta{}_\\text{?}x\\to0}2{}_\\text{?}x+\\lim_{\\Delta{}_\\text{?}x\\to0}\\Delta{}_\\text{?}x	{20,2,24,23,4}	function	2	{143,144}
146	\\x00000200050001000000000002000000140000000200000018000000170000000400000000000200030001000200010203000504060005	\\x58ab06ef9d441a1147a9530ba33b977657efa151e11e0fd46e7647a7f945ff21	\\lim_{\\Delta{}_\\text{?}x\\to0}2{}_\\text{?}x+0	{20,2,24,23,4}	function	2	{143,25}
147	\\x000002000300010002000000000000001400000002000000040000000000020002000102030004	\\xbefa230147674ec5c7ecfb400702319f358515ba3828fcde33e502678c2076ae	2{}_\\text{?}x+0	{20,2,4}	function	2	{105,25}
148	\\x00000000010001001b000000000000	\\x85c6cdda47e4d256d3715ae785cbc5aac9fca0ebdc7bdb2d60930002b699c05e	{}_\\text{?}body	{27}	generic	27	{}
149	\\x00000000020001001b0000001d000000000001000100	\\x3aadb6d8df539963e29b7a7699b839d505967f07f8c3ac0442d441a365187140	\\vec{v_{{}_\\text{?}body}}	{27,29}	function	29	{148}
150	\\x000000000100000021000000000000	\\x2e072772572ac8afc626b23eb0a61bbb693c2d7cb868e88d7152856335e1869d	t	{33}	function	33	{}
151	\\x00000000020001001b0000001c000000000001000100	\\x745777fa95b7d147538b91d334c1f23aa00acb27f157674e7dbf2a511d23dc8c	\\vec{p_{{}_\\text{?}body}}	{27,28}	function	28	{148}
153	\\x00000000020001001b0000001e000000000001000100	\\xd717f85ac71de6d40513e31337ae143ed7c5d77b6dde01fe9223d08552ccb3be	\\vec{a_{{}_\\text{?}body}}	{27,30}	function	30	{148}
159	\\x000000000100000022000000000000	\\xbb259b48d2f8f7f4c776208ab4b51d3384f79a876291d7d0bcf001f0ed4bda51	\N	{34}	function	34	{}
155	\\x00000000020001001b0000001f000000000001000100	\\xe93ee218cb5146a91e2df49536f01427e5560bd66917f930d3e4d05030e79627	\\text{v}_{{}_\\text{?}body}	{27,31}	function	31	{148}
156	\\x00000000030001001b0000001a0000001d000000000001000100010200	\\xb3a17c6c3b4b9c8ed335fcdd8465b784bcf7fea44db1b74f2bb5b26f83949910	\\left|\\vec{v_{{}_\\text{?}body}}\\right|	{27,26,29}	function	26	{149}
157	\\x00000000020001001b00000020000000000001000100	\\x8a5510535ffe67185b4d4cc789d5904c037d5097e3cc0110c9d7410b8e647717	\\text{a}_{{}_\\text{?}body}	{27,32}	function	32	{148}
158	\\x00000000030001001b0000001a0000001e000000000001000100010200	\\xd8bb5a6cd27a9c2e3323b92976f6accb5baf46ecb71ad7f6c7b83d6ccba5f90a	\\left|\\vec{a_{{}_\\text{?}body}}\\right|	{27,26,30}	function	26	{153}
161	\\x000000000100000010000000000000	\\xd743c1d4040e71eb30bfc28e924b6628a9e40a4c51b0d104c09405e28da078ca	r	{16}	function	16	{}
162	\\x000000000100000011000000000000	\\x6430be9f08c1bcdbd74e01fec7062adc4422bda3194fbfca6f8cad08f23ab886	\\theta	{17}	function	17	{}
165	\\x00000000010000000d000000000000	\\xe3ad3e8c134a597c9a8bc2d01896e698815194eeccdac37c9f3983eb2a368a21	\\hat{i}	{13}	function	13	{}
169	\\x00000000010000000e000000000000	\\xdb3966066a05fab9fa9f317f9a84d1daf73c5e1fc130ab860d6022ad47947378	\\hat{j}	{14}	function	14	{}
189	\\x000001000200010000000000090000000400000000000200010002	\\x75425810302585f0b3c7dd15433a301a51f546e3b76166f15e16c5cced7a072e	{}_\\text{?}a0	{9,4}	function	4	{1,25}
190	\\x000000000300010009000000040000000d000000000002000000010002	\\x19751da471698239217fecc64922a9d552dc19e683c1caa6e595e4677ba70ff6	{}_\\text{?}a\\hat{i}	{9,4,13}	function	4	{1,165}
197	\\x000000000300010009000000040000000e000000000002000000010002	\\x5598ec16696e1cb7b7a705f1cf423cd5743b93e3d695f6a7b75da32325596ac5	{}_\\text{?}a\\hat{j}	{9,4,14}	function	4	{1,169}
160	\\x00000000020000001c00000022000000010000000001	\\xb61662436f7228e48393bc2e6dfc3327fa1cc907665d608e87f27d8f5b6e04b5	\\vec{p_{c}}	{28,34}	function	28	{159}
167	\\x00000000020000001200000011000000010000000001	\\x0078a0c7640fd5c6105c2799f898732d102bf847985316d257fba20676be05f6	\N	{18,17}	function	18	{162}
163	\\x00000000020000001300000011000000010000000001	\\x890abcff20aaad3eb6abda435cc86ee6588726b3c461349a13106e4b1aa96fb0	\N	{19,17}	function	19	{162}
164	\\x000000000400000004000000100000001300000011000000020000000100000000010203	\\x1c89c6b4d77c98465aafa24f5718d94f9f3278927e59f709089cdaad44120356	\N	{4,16,19,17}	function	4	{161,163}
166	\\x0000000005000000040000001000000013000000110000000d00000002000000010000000000000001020304	\\x8927a780f8e265791222626aaa27c0a6dff0152b2ec24a6a73b71457c490a661	\N	{4,16,19,17,13}	function	4	{164,165}
152	\\x00000000040001001b00000019000000210000001c000000000002000000010001020300	\\xb03a44b86f87ae12eeebb182895f81c69e9a8e217676f985bd7cfc25b6ee8677	\\frac{\\partial}{\\partial t}\\left(\\vec{p_{{}_\\text{?}body}}\\right)	{27,25,33,28}	function	25	{150,151}
188	\\x000000000300010014000000190000000e000000000002000000010002	\\x5b9cc8ff5c762d00d2ea56fd544be7f029901340a885274b32ec9f986b97f605	\\frac{\\partial}{\\partial{}_\\text{?}x}\\left(\\hat{j}\\right)	{20,25,14}	function	25	{21,169}
204	\\x0000000003000000190000002100000010000000020000000000000102	\\xd461dc719844ac94fcb216a511b7a59d7b9af9e0eff13c61387361ae126fdb88	\\frac{\\partial}{\\partial t}\\left(r\\right)	{25,33,16}	function	25	{150,161}
180	\\x0000000005000200090000000a000000040000001900000021000000000000000200020000000200030401	\\x447dd06d72a16dd10d0c9a7e4ec51585babafb0408d80ae50d05111214d19e35	\N	{9,10,4,25,33}	function	4	{1,179}
186	\\x000000000600030014000000090000000a0000000200000004000000190000000000000000000200020002000304050001020401050002	\\xed1cf06a50de02250a0cadb7020fde121b8a567f2de0fbf8e00743131975c98e	\\frac{\\partial}{\\partial{}_\\text{?}x}\\left({}_\\text{?}a\\right){}_\\text{?}b+{}_\\text{?}a\\frac{\\partial}{\\partial{}_\\text{?}x}\\left({}_\\text{?}b\\right)	{20,9,10,2,4,25}	function	2	{183,185}
187	\\x000000000300010014000000190000000d000000000002000000010002	\\x38b781a8e56581265859fae3040ec15885eb6d430f7916e72a0bb32d240db119	\\frac{\\partial}{\\partial{}_\\text{?}x}\\left(\\hat{i}\\right)	{20,25,13}	function	25	{21,165}
173	\\x0000000003000200090000000a00000019000000000000000200020001	\\xe3180c555144ef918acf93c2dce589ab0873fe7d41b0f35b90b63f16ff5d634c	\N	{9,10,25}	function	25	{1,2}
174	\\x0000000003000200090000000b00000019000000000000000200020001	\\xd82ea24efcbab42e1f4deb23bb4d73254bfb1d39a84a616d14fbcd023241fabc	\N	{9,11,25}	function	25	{1,7}
177	\\x0000000003000100090000001900000021000000000002000000010200	\\xc14f91fa8a4556673ce8793cb1fea1bb4f1d93183803c73e597e283127e15724	\N	{9,25,33}	function	25	{150,1}
23	\\x000000000300020014000000160000001900000000000100020002000100	\\x3f8ac895dfad545ad6ad91a2ed1c8d0c22a1a238ef3e03997e043406734b1df1	\\frac{\\partial}{\\partial{}_\\text{?}x}\\left({}_\\text{?}\\text{f}{\\left({}_\\text{?}x\\right)}\\right)	{20,22,25}	function	25	{21,22}
154	\\x00000000040001001b00000019000000210000001d000000000002000000010001020300	\\x51869e0b8dca8f01ae0f494e2b42892f45e607c6e88bfaf27baa1eb14822b3cd	\\frac{\\partial}{\\partial t}\\left(\\vec{v_{{}_\\text{?}body}}\\right)	{27,25,33,29}	function	25	{150,149}
172	\\x0000000005000300090000000a0000000b0000001900000002000000000000000000020002000300040102	\\xff3dbcce10eeacdb5d9ef6f7378c5613b5a98619967e4f2278d4cef0d7efdc8e	\\frac{\\partial}{\\partial{}_\\text{?}a}\\left({}_\\text{?}b+{}_\\text{?}c\\right)	{9,10,11,25,2}	function	25	{1,10}
178	\\x0000000005000200090000000a000000040000001900000021000000000000000200020000000203040001	\\x80b3c8500926571639b27ffe9ad4da8921011e4d197aac762166487d56779cc4	\N	{9,10,4,25,33}	function	4	{177,2}
179	\\x00000000030001000a0000001900000021000000000002000000010200	\\x4c837d6d17f81afe2849b1330bbf03687d4a7951af516304420bb559c68a02aa	\N	{10,25,33}	function	25	{150,2}
181	\\x0000000006000200090000000a000000020000000400000019000000210000000000000002000200020000000203040500010300040501	\\xf827e0999ffdccf2f60ff2f8369befae49cc701172468e7170168974b011dcf8	\N	{9,10,2,4,25,33}	function	2	{178,180}
182	\\x0000000003000200140000000900000019000000000000000200020001	\\xbc5f124244e869207c79424e340b8ff060b750b3d5c1d51d1e0f064a5dfb6585	\N	{20,9,25}	function	25	{21,1}
183	\\x000000000500030014000000090000000a0000000400000019000000000000000000020002000304000102	\\x1d57b64b1427bd7f4ab5c635fd1588f1b9cde0c516b4cdb325b7c011d5ed257f	\N	{20,9,10,4,25}	function	4	{182,2}
184	\\x0000000003000200140000000a00000019000000000000000200020001	\\x1cbd80f8162ea8c1a62f1eb0133cae5a988e328c6409009e7eb9b2a50d3b7dba	\N	{20,10,25}	function	25	{21,2}
211	\\x00000100060001000000000009000000020000000400000010000000190000002100000000000200020000000200000001060203040500	\\xc4f78e91cb768a436ac22b3456de0add88b9148a3e18d9f457e8ee97fb00ec05	0+r\\frac{\\partial}{\\partial t}\\left({}_\\text{?}a\\right)	{9,2,4,16,25,33}	function	2	{25,208}
220	\\x000000000400000019000000210000001c00000022000000020000000100000000010203	\\xd1d12b58bfac892fd6a5410c5d724367a01d18685a5f1ff172fad0334f3bbc87	\\frac{\\partial}{\\partial t}\\left(\\vec{p_{c}}\\right)	{25,33,28,34}	function	25	{150,160}
213	\\x0000000004000200090000000a0000001900000012000000000000000200010002000301	\\x0167e768741cf78d393f83c157745a2f0693c3218648490205f0a012a50c5754	\\frac{\\partial}{\\partial{}_\\text{?}a}\\left(\\sin\\left({}_\\text{?}b\\right)\\right)	{9,10,25,18}	function	25	{1,212}
214	\\x00000000020001000a00000013000000000001000100	\\x6d95778091df64e397c3b748855ed155a76c6080bcf9c2a6cd38a289ad6ce5d5	\N	{10,19}	function	19	{2}
250	\\x00000000040000000400000013000000110000000e000000020001000000000000010203	\\x1570b4fead99a695942a61495616829f3eefa43b06dc4d99384908de0ba12448	\N	{4,19,17,14}	function	4	{163,169}
235	\\x000000000400000019000000210000001300000011000000020000000100000000010203	\\x3d9e11a56b7731d15829d351fe5d28b6fda0c141c70ac03f9649a8ffe5cec45d	\N	{25,33,19,17}	function	25	{150,163}
215	\\x0000000005000200090000000a00000004000000190000001300000000000000020002000100020300010401	\\xc69b5d07bd175599f3c4f09f2c261279f8a931d95528d70e3883a5952b9f48b5	\\frac{\\partial}{\\partial{}_\\text{?}a}\\left({}_\\text{?}b\\right)\\cos\\left({}_\\text{?}b\\right)	{9,10,4,25,19}	function	4	{173,214}
217	\\x00000000030001000a0000000700000012000000000001000100010200	\\xb9a2396340aeed290af2dd97b10f5d14d6717f19dff6bbd2446eb20676650cac	\N	{10,7,18}	function	7	{212}
244	\\x0000000003000000070000001200000011000000010001000000000102	\\x87b7172beec938b1bc003bd006c844481953cc0a66a7848acfa3c9bea0af1464	\N	{7,18,17}	function	7	{167}
253	\\x0000000005000000040000000700000012000000110000000d000000020001000100000000000001020304	\\xa61d32fc421b0d0c6f0e47a9ed8551104a3d7e80c0695255aabdbee5924fade0	\N	{4,7,18,17,13}	function	4	{244,165}
216	\\x0000000004000200090000000a0000001900000013000000000000000200010002000301	\\x95e4edaada590f46e50e69bd7db733749be901882b3c9ca0c6138460642c8968	\\frac{\\partial}{\\partial{}_\\text{?}a}\\left(\\cos\\left({}_\\text{?}b\\right)\\right)	{9,10,25,19}	function	25	{1,214}
256	\\x000000000800000002000000040000000700000012000000110000000d000000130000000e0000000200020001000100000000000100000000010203040501060407	\\xfdc65e61fb23b5d64ae181b2876f1c20c0c85d346d1c664de2659de34cdc1878	\N	{2,4,7,18,17,13,19,14}	function	2	{253,250}
185	\\x000000000500030009000000140000000a0000000400000019000000000000000000020002000300040102	\\x1778a0854df90b3047cabb7fa4e3a4561664dea287758ff0060a85fbee8f31a2	\N	{9,20,10,4,25}	function	4	{1,184}
193	\\x0000000005000200090000001400000004000000190000000d000000000000000200020000000200030104	\\x58ea4920211ca78041adf02ef4a04f48fe093233cf4e62be694aa22f3053394d	\N	{9,20,4,25,13}	function	4	{1,187}
200	\\x0000000005000200090000001400000004000000190000000e000000000000000200020000000200030104	\\x76b63e8b418188f5135d4baad16691d6f6a2513f3c6f510ecfe34b623b1719f0	\N	{9,20,4,25,14}	function	4	{1,188}
207	\\x00000000050001000900000004000000190000002100000010000000000002000200000000000102030400	\\x8a94e8550fa950e9d5e85825ebd427693f9885f48ace8cdedc966965853bace3	\N	{9,4,25,33,16}	function	4	{204,1}
249	\\x00000000050000000400000010000000190000002100000011000000020000000200000000000001020304	\\x97e54b6151b72745729b47ea7fed25bfc841d5c0d451a739f45fa28096acf1cb	\N	{4,16,25,33,17}	function	4	{161,239}
194	\\x000000000600020014000000090000000200000004000000190000000d0000000000000002000200020000000203040001050301040005	\\xc3fa1a105eec31ee3be4542e861a53e49d46025768635ccb9ba0253fb75c09ce	\\frac{\\partial}{\\partial{}_\\text{?}x}\\left({}_\\text{?}a\\right)\\hat{i}+{}_\\text{?}a\\frac{\\partial}{\\partial{}_\\text{?}x}\\left(\\hat{i}\\right)	{20,9,2,4,25,13}	function	2	{192,193}
201	\\x000000000600020014000000090000000200000004000000190000000e0000000000000002000200020000000203040001050301040005	\\xd7a717fa362d318134bf4a93d655623493400e0bb1c00a9df6f6898edae95569	\\frac{\\partial}{\\partial{}_\\text{?}x}\\left({}_\\text{?}a\\right)\\hat{j}+{}_\\text{?}a\\frac{\\partial}{\\partial{}_\\text{?}x}\\left(\\hat{j}\\right)	{20,9,2,4,25,14}	function	2	{199,200}
202	\\x00000100060002000000000014000000090000000200000004000000190000000e000000000000000200020002000000020304000105030106	\\x4bea6bb34a99657070457b20a2ed4736d25d4bb3b98595bd40332bc503105542	\\frac{\\partial}{\\partial{}_\\text{?}x}\\left({}_\\text{?}a\\right)\\hat{j}+{}_\\text{?}a0	{20,9,2,4,25,14}	function	2	{199,189}
209	\\x00000000060001000900000002000000040000001900000021000000100000000000020002000200000000000102030405000205030400	\\xc5310a0457ab65515dd6e3e11da0e5e433ba9d35dc4842afd0ed588ae34ed6cf	\\frac{\\partial}{\\partial t}\\left(r\\right){}_\\text{?}a+r\\frac{\\partial}{\\partial t}\\left({}_\\text{?}a\\right)	{9,2,4,25,33,16}	function	2	{207,208}
239	\\x0000000003000000190000002100000011000000020000000000000102	\\xcc44fe472424a5ba1e8ceaeea307e1da99358a7d13c665eca006d0d462c9691e	\\frac{\\partial}{\\partial t}\\left(\\theta\\right)	{25,33,17}	function	25	{150,162}
218	\\x0000000006000200090000000a0000000400000019000000070000001200000000000000020002000100010002030001040501	\\x16a65d1031dac89e1f7ebe256285a2744349ac5a55f7446e595143196dc044d9	\\frac{\\partial}{\\partial{}_\\text{?}a}\\left({}_\\text{?}b\\right)\\left(-\\sin\\left({}_\\text{?}b\\right)\\right)	{9,10,4,25,7,18}	function	4	{173,217}
222	\\x00000000070000001900000021000000040000001000000013000000110000000d00000002000000020000000100000000000001020203040506	\\x668e33e0f6143d56ac35016568bb1bea84a33319a4635ad4d40fe6da7483c4e3	\N	{25,33,4,16,19,17,13}	function	25	{150,166}
228	\\x0000000006000000190000002100000004000000100000001300000011000000020000000200000001000000000102030405	\\x48172d536641ffa8ee41c86de3dbdd023220facee7731c0b4e7ba4b99ecee472	\N	{25,33,4,16,19,17}	function	25	{150,164}
229	\\x00000000070000000400000019000000210000001000000013000000110000000d00000002000200000000000100000000000001020003040506	\\x1ad95754c72e0765fe5af1e119d37874e23102f737dad3e352f02d10b96b2d36	\N	{4,25,33,16,19,17,13}	function	4	{228,165}
168	\\x000000000400000004000000100000001200000011000000020000000100000000010203	\\x0d3cbcc5ed181b842320af0fbc3f66287acee573a3c0a5c12b4961655be11ad3	\N	{4,16,18,17}	function	4	{161,167}
170	\\x0000000005000000040000001000000012000000110000000e00000002000000010000000000000001020304	\\x3d60ccfd5bd81116ca73fc3db5e1546ab097755e24290f67de18e0fc811b8555	\N	{4,16,18,17,14}	function	4	{168,169}
236	\\x0000000006000000040000001000000019000000210000001300000011000000020000000200000001000000000102030405	\\x690e5d8936bc774c6d76b629fbbae28e3856dda812b9aeb678f65255a8f27434	\N	{4,16,25,33,19,17}	function	4	{161,235}
237	\\x00000000070000000400000010000000190000002100000013000000110000000d00000002000000020000000100000000000000010203040506	\\xffa444d39a7b4112b95fdecd95e78ac51f59e9c76a8b2e757162cbad9f448967	\N	{4,16,25,33,19,17,13}	function	4	{236,165}
240	\\x0000000005000000040000001900000021000000110000001300000002000200000000000100000102030403	\\x4b51c937bed55de6c2bcfbdf487d01c4b0f5ec7c89a94305864e5891e12ca7c3	\N	{4,25,33,17,19}	function	4	{239,163}
241	\\x00000000060000000400000010000000190000002100000011000000130000000200000002000000000001000001000203040504	\\x19b2e097afdaf213f33e4d5d1b2648f6022efeade3aee35ec1626e3bc287f500	\N	{4,16,25,33,17,19}	function	4	{161,240}
242	\\x00000000070000000400000010000000190000002100000011000000130000000e000000020000000200000000000100000000000100020304050406	\\x688af7ea247a3f8ddd2d830764870d9672689baa61ef185545fa4f7014036f5e	\N	{4,16,25,33,17,19,14}	function	4	{241,169}
251	\\x00000000070000000400000010000000190000002100000011000000130000000e000000020000000200000000000100000000000102030400050406	\\xf9bb78d2edcf74db1e04ce5c0206bc06ba46d75a9ce42353c564b8afb43d58dd	\N	{4,16,25,33,17,19,14}	function	4	{249,250}
276	\\x00000100030001000200000009000000060000001300000000000200010001020003	\\x39b44915b594feff797378f8c5c7c3c622b71d86f878296bb3867fe693f5840b	\N	{9,6,19}	function	6	{275,38}
175	\\x0000000005000300090000000a0000000b00000002000000190000000000000000000200020003040001040002	\\x00b33dca3684e3bf498c458b4122f9077e979bc6b5fc1803999c6d35f0f65d72	\\frac{\\partial}{\\partial{}_\\text{?}a}\\left({}_\\text{?}b\\right)+\\frac{\\partial}{\\partial{}_\\text{?}a}\\left({}_\\text{?}c\\right)	{9,10,11,2,25}	function	2	{173,174}
176	\\x000000000500030014000000090000000a0000001900000004000000000000000000020002000300040102	\\x3600b39c3fe58f6fc442252a3a0c1617843cee3e2b083fd63bb704b41292ef06	\\frac{\\partial}{\\partial{}_\\text{?}x}\\left({}_\\text{?}a{}_\\text{?}b\\right)	{20,9,10,25,4}	function	25	{21,6}
219	\\x00000000020000001d00000022000000010000000001	\\x5e6a728f480ec3c315e4c7d0ef973b0ce67cdceacec669bcec7d8401bc651b49	\\vec{v_{c}}	{29,34}	function	29	{159}
100	\\x0000010003000100020000001400000019000000060000000000020002000100020003	\\x5261ca0a13eaec8fd19130ccc719ca3bb58fb7763dcb174219b5405d33ef2a4c	\\frac{\\partial}{\\partial{}_\\text{?}x}\\left({}_\\text{?}x^{2}\\right)	{20,25,6}	function	25	{21,99}
191	\\x0000000005000200140000000900000019000000040000000d000000000000000200020000000200030104	\\x4aa2c1ccac2451b736feabc31ee6e9cdfbbb25313ca18dff9df340719bf61f34	\\frac{\\partial}{\\partial{}_\\text{?}x}\\left({}_\\text{?}a\\hat{i}\\right)	{20,9,25,4,13}	function	25	{21,190}
192	\\x0000000005000200140000000900000004000000190000000d000000000000000200020000000203000104	\\xec95b6ef370494af318b0369a3626fcd91f197cbeeabf3ebc2952a1732175b74	\\frac{\\partial}{\\partial{}_\\text{?}x}\\left({}_\\text{?}a\\right)\\hat{i}	{20,9,4,25,13}	function	4	{182,165}
198	\\x0000000005000200140000000900000019000000040000000e000000000000000200020000000200030104	\\xc65b7edc276589ef88fed0d1ebeda0c07695a40f332490c8cfe3e3cdcc0b98b8	\\frac{\\partial}{\\partial{}_\\text{?}x}\\left({}_\\text{?}a\\hat{j}\\right)	{20,9,25,4,14}	function	25	{21,197}
199	\\x0000000005000200140000000900000004000000190000000e000000000000000200020000000203000104	\\x50e495207e316b19ac2cb08fdec10f2cc681d75abd10aad41610e92890f9ad49	\\frac{\\partial}{\\partial{}_\\text{?}x}\\left({}_\\text{?}a\\right)\\hat{j}	{20,9,4,25,14}	function	4	{182,169}
206	\\x00000000050001000900000019000000210000000400000010000000000002000000020000000102030400	\\x32f028b500b4e5e329943f52272e4ec5183101469c3c67e564baffc8ae02db70	\\frac{\\partial}{\\partial t}\\left(r{}_\\text{?}a\\right)	{9,25,33,4,16}	function	25	{150,205}
208	\\x00000000050001000900000004000000100000001900000021000000000002000000020000000102030400	\\x6274e04bd714077152ea37bb29bd4e4610adb08cbf86f598b1bd0eab651d0e7c	r\\frac{\\partial}{\\partial t}\\left({}_\\text{?}a\\right)	{9,4,16,25,33}	function	4	{161,177}
195	\\x00000100060002000000000014000000090000000200000004000000190000000d000000000000000200020002000000020304000105030106	\\x82c392d6b3463708f3abf51647d86ddc8a090b0e8a924a3d63f3d3ab79a6c106	\\frac{\\partial}{\\partial{}_\\text{?}x}\\left({}_\\text{?}a\\right)\\hat{i}+{}_\\text{?}a0	{20,9,2,4,25,13}	function	2	{192,189}
196	\\x00000100060002000000000014000000090000000200000004000000190000000d00000000000000020002000200000002030400010506	\\x7d0d1056cdefdd6a2c668b4e6c3c158dc395762a238b12f664de94740381b32f	\\frac{\\partial}{\\partial{}_\\text{?}x}\\left({}_\\text{?}a\\right)\\hat{i}+0	{20,9,2,4,25,13}	function	2	{192,25}
203	\\x00000100060002000000000014000000090000000200000004000000190000000e00000000000000020002000200000002030400010506	\\x0d1cc03531ad1298d6c65d6b2ac8f15e7760193442643b903a7f403cc9dcf2e0	\\frac{\\partial}{\\partial{}_\\text{?}x}\\left({}_\\text{?}a\\right)\\hat{j}+0	{20,9,2,4,25,14}	function	2	{199,25}
210	\\x000001000600010000000000090000000200000004000000100000001900000021000000000002000200000002000000010206000203040500	\\x1101d39c0d2f550c77bb110334adec6e8cc6064a8dbdb35783aed918149a9101	0{}_\\text{?}a+r\\frac{\\partial}{\\partial t}\\left({}_\\text{?}a\\right)	{9,2,4,16,25,33}	function	2	{80,208}
223	\\x00000000070000001900000021000000040000001000000012000000110000000e00000002000000020000000100000000000001020203040506	\\x1524aabefc2cf58d1e07e7ded1eaa9b248d1605e8daa7286b41428765b5c164c	\N	{25,33,4,16,18,17,14}	function	25	{150,170}
224	\\x000000000a000000020000001900000021000000040000001000000013000000110000000d000000120000000e00000002000200000002000000010000000000010000000001020303040506070102030304080609	\\xf98e5c56e6327cd768c279620265f2049327c677d58cb516dd220beb565fd41e	\\frac{\\partial}{\\partial t}\\left(r\\cos\\left(\\theta\\right)\\hat{i}\\right)+\\frac{\\partial}{\\partial t}\\left(r\\sin\\left(\\theta\\right)\\hat{j}\\right)	{2,25,33,4,16,19,17,13,18,14}	function	2	{222,223}
225	\\x0000000006000000190000002100000004000000100000001200000011000000020000000200000001000000000102030405	\\xec8c9d69be3959485d10c5eb650bb35d49a193d79c1cf758e05484db980b68b2	\N	{25,33,4,16,18,17}	function	25	{150,168}
226	\\x00000000070000000400000019000000210000001000000012000000110000000e00000002000200000000000100000000000001020003040506	\\xbfd1ffac69e4b21d28f8996fc4c2322bcfab3593f050124c9cf015abe026e59a	\N	{4,25,33,16,18,17,14}	function	4	{225,169}
231	\\x000000000400000019000000210000001200000011000000020000000100000000010203	\\x001f946bdf9b38340d9da5b59c700e70f5a7c9a922452e495b6e5469f91220c6	\N	{25,33,18,17}	function	25	{150,167}
232	\\x0000000006000000040000001000000019000000210000001200000011000000020000000200000001000000000102030405	\\xbab3b22e3acc9b329871e57056f360be9a104186b83934356d3c9a927f32602d	\N	{4,16,25,33,18,17}	function	4	{161,231}
233	\\x00000000070000000400000010000000190000002100000012000000110000000e00000002000000020000000100000000000000010203040506	\\xa442c38b54d40209d0828a317816c4f255255c605d2de8552d22b50d950706f5	\N	{4,16,25,33,18,17,14}	function	4	{232,169}
258	\\x0000000004000200090000000a0000001a00000004000000000000000100020002030001	\\x63cc5e844fcce12a33973e484c328d78f85fc55f70e33ed0d61fb8417422a5da	\\left|{}_\\text{?}a{}_\\text{?}b\\right|	{9,10,26,4}	function	26	{6}
259	\\x0000000002000100090000001a000000000001000100	\\xf469eda1f7df424b6941f64a3e239a38f5993ef5ede251f05a20cf3fd57cf578	\\left|{}_\\text{?}a\\right|	{9,26}	function	26	{1}
260	\\x00000000020001000a0000001a000000000001000100	\\x648cf9f050c6bcbfb0677011319bba63568c66ace367ee88d56b259169545b2b	\\left|{}_\\text{?}b\\right|	{10,26}	function	26	{2}
261	\\x0000000004000200090000000a000000040000001a00000000000000020001000203000301	\\x15beea23e0ebd5ad55b25272025da1b96041175fe5dad7a214afa22d0bba0990	\\left|{}_\\text{?}a\\right|\\left|{}_\\text{?}b\\right|	{9,10,4,26}	function	4	{259,260}
265	\\x0000010002000100ffffffff09000000040000000000020001010200010200	\\x7f3b2705e0188e75565424c1203cce67f364b0999ceba61ffb1d33b3cda497ca	-1{}_\\text{?}a\\left(-1{}_\\text{?}a\\right)	{9,4}	function	4	{84,84}
266	\\x0000010002000100010000000900000004000000000002000101020000	\\x3cde1865622f2c37fcccacda977c998f62bd3a324c7c1e14a2250bd105067a3f	1{}_\\text{?}a{}_\\text{?}a	{9,4}	function	4	{48,1}
3	\\x00000000020001000a00000007000000000001000100	\\xd419c9a79fedb89dd8fe433025dd1b7eae46f975b3982323e3eccea316b34423	\N	{10,7}	function	7	{2}
14	\\x0000010001000000010000000700000001000001	\\x67c383bff6469fd3ef635e7f21fbec2e7a4fb5a5108bdbed69d982793074a848	\N	{7}	function	7	{13}
113	\\x00000100030001000200000014000000070000000600000000000100020001020003	\\xa1b35aff4c69d746b7f4d179343502063bf46aefa47825fc70e6918cbef3d54f	\N	{20,7,6}	function	7	{99}
114	\\x0000010006000100020000001400000002000000060000000400000017000000070000000000020002000200010001000101010200060303060004000204000605020006	\\xa1f74f529a1e22a5962f6475e8bc4854d6fd2af0948edd956ad9acec996c8065	\N	{20,2,6,4,23,7}	function	2	{109,113}
115	\\x0000010007000100020000001400000005000000020000000600000004000000170000000700000000000200020002000200010001000102020203000704040700050003050007060300070500	\\x6104aa62571c6822dc97921130a8be5cf27da818a728bcc45fbb4b791697f15d	\N	{20,5,2,6,4,23,7}	function	5	{114,24}
116	\\x00000200080001000000000002000000140000001800000017000000050000000200000006000000040000000700000000000300010002000200020002000100010200080304040405000906060900020005020009070500090200	\\x1e7c2fa4e08c3284455b6e268e202b32a8a5872c2021ff4925ed05919186a06d	\N	{20,24,23,5,2,6,4,7}	function	24	{24,25,115}
117	\\x0000010004000100020000001400000002000000060000000700000000000200020001000102000403020004	\\xcbfbc1051d034874f6e3ee2352f5ad571fc02c95142fb24e1e8d9bfe81df9ede	\N	{20,2,6,7}	function	2	{99,113}
118	\\x000001000600010002000000140000000200000006000000070000000400000017000000000002000200010002000100010102000603020006040406000500	\\x87e68f1e2bcebd9796ebebe245e5fa21f0f09638156f32a2b200567a4593bb01	\N	{20,2,6,7,4,23}	function	2	{117,106}
119	\\x0000010006000100020000001400000002000000060000000700000004000000170000000000020002000100020001000101010200060302000604040600050002050006	\\xf6019e8d28022c3ce6fc4bae02a298e11853509e096066e4244a7f667d908e5f	\N	{20,2,6,7,4,23}	function	2	{118,108}
120	\\x0000010007000100020000001400000005000000020000000600000007000000040000001700000000000200020002000100020001000102020203000704030007050507000600030600070600	\\x8028254686c803b193720e11d8df854e197e872ecb92974d9bdd6b7a974e45a7	\N	{20,5,2,6,7,4,23}	function	5	{119,24}
121	\\x00000200080001000000000002000000140000001800000017000000050000000200000006000000070000000400000000000300010002000200020001000200010200080304040405000906050009070709000200050200090200	\\xb8b8980b868afa0d3052e190f235fb4ea77ec9413ae8499ef6a8d56e3448bd99	\N	{20,24,23,5,2,6,7,4}	function	24	{24,25,120}
123	\\x000001000600010002000000140000000200000006000000070000000400000017000000000002000200010002000100010101020006030200060404060005000405000500	\\x0c5a5199aacaeaefa352aedca8cc55c82851cf2dd7bd3dc9187d7fb856994580	\N	{20,2,6,7,4,23}	function	2	{118,122}
124	\\x000001000700010002000000140000000500000002000000060000000700000004000000170000000000020002000200010002000100010202020300070403000705050700060005060006000600	\\x662e33f7e420e86971f6081503d956e09987a2722c0e537eb3b47dd05df4cdcf	\N	{20,5,2,6,7,4,23}	function	5	{123,24}
125	\\x0000020008000100000000000200000014000000180000001700000005000000020000000600000007000000040000000000030001000200020002000100020001020008030404040500090605000907070900020007020002000200	\\xeb89ac23669f8087b97622f305d95d6f7796d0147f198a24640b45f98841a4a3	\N	{20,24,23,5,2,6,7,4}	function	24	{24,25,124}
268	\\x00000000030001000a000000040000000e000000000002000000010002	\\x42ec8b03c8af9c3cb6dd47ae22e58c3affd6a54c8af30060d97ca89bff7c2eb5	{}_\\text{?}b\\hat{j}	{10,4,14}	function	4	{2,169}
269	\\x0000000006000200090000000a00000002000000040000000d0000000e00000000000000020002000000000002030004030105	\\x1928457711ef3003e9f929c2f88de8c57ff8aa78322287f3367823c8d93bf754	{}_\\text{?}a\\hat{i}+{}_\\text{?}b\\hat{j}	{9,10,2,4,13,14}	function	2	{190,268}
270	\\x0000000007000200090000000a0000001a00000002000000040000000d0000000e00000000000000010002000200000000000203040005040106	\\xc3498c2366c42cf639f52fe5d8d4d487b0e85df1c02ccdab2c9a92aa8b20dd10	\\left|{}_\\text{?}a\\hat{i}+{}_\\text{?}b\\hat{j}\\right|	{9,10,26,2,4,13,14}	function	26	{269}
4	\\x0000000004000200090000000a0000000200000007000000000000000200010002000301	\\x06c4317b0d80c1ce50664d8365b0cf06da41d15dbc6038d7f6c18952206908fc	{}_\\text{?}a+\\left(-{}_\\text{?}b\\right)	{9,10,2,7}	function	2	{1,3}
12	\\x00000000020001000900000007000000000001000100	\\xed9dae5554a70accaa92a3285e84500169047310a233a67d2402da9763e44a08	\\left(-{}_\\text{?}a\\right)	{9,7}	function	7	{1}
15	\\x00000100030001000100000009000000040000000700000000000200010001020300	\\x7868708f462030521b1f3b26b9818bac00b5429f492f4a5a295135be1c9c34f4	\\left(-1\\right){}_\\text{?}a	{9,4,7}	function	4	{14,1}
262	\\x00000100030001000200000009000000060000000700000000000200010001020003	\\xec9a04432575dd3fbb4f1404383217d1d737cd28b9ed4620a842f835deb38b64	\\left(-{}_\\text{?}a\\right)^{2}	{9,6,7}	function	6	{12,38}
263	\\x00000000030001000900000004000000070000000000020001000102000200	\\x43089d2ee2de54f86bb595582516b9c201d123769a5a6839ceb9352c2b518eb4	\\left(-{}_\\text{?}a\\right)\\left(-{}_\\text{?}a\\right)	{9,4,7}	function	4	{12,12}
264	\\x0000010003000100ffffffff090000000400000007000000000002000100010200010300	\\x93ffd9c30873b064a3c9aee31d19886476adfdfaac77161cedfb0d82dc1bf451	\\left(-{}_\\text{?}a\\right)\\left(-1{}_\\text{?}a\\right)	{9,4,7}	function	4	{12,84}
267	\\x00000100030001000200000009000000240000000600000000000100020001020003	\\xb658b15314eea2eb94ce861bddff3171eb853e16d55b7051e2b404ffd9967c52	\\sqrt{{}_\\text{?}a^{2}}	{9,36,6}	function	36	{39}
271	\\x000001000400020002000000090000000a0000000200000006000000000000000200020002030004030104	\\x9d1ac72f5d137f09403a7c39451831873d26ff9cb6f5248b18947bbc8f2272a8	{}_\\text{?}a^{2}+{}_\\text{?}b^{2}	{9,10,2,6}	function	2	{39,70}
272	\\x000001000500020002000000090000000a000000240000000200000006000000000000000100020002000203040005040105	\\x5b3f91e9338390dd805e55abb6a33dd9313be7b10f79d4471aa8bb83f9c10449	\\sqrt{{}_\\text{?}a^{2}+{}_\\text{?}b^{2}}	{9,10,36,2,6}	function	36	{271}
275	\\x00000000020001000900000013000000000001000100	\\x2869efb62ea8c83a50729e27bd5a873d1d9eee0f88781e1724134215dbabc1c1	\N	{9,19}	function	19	{1}
243	\\x0000000009000000020000000400000010000000190000002100000013000000110000000d0000000e00000002000200000002000000010000000000000000010102030405060701010201030406050608	\\x999c57520a3b5714c6da898c91e409899cbb515c93bfccd267a4e4d601ff69d0	r\\frac{\\partial}{\\partial t}\\left(\\cos\\left(\\theta\\right)\\right)\\hat{i}+r\\left(\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\cos\\left(\\theta\\right)\\right)\\hat{j}	{2,4,16,25,33,19,17,13,14}	function	2	{237,242}
245	\\x000000000600000004000000190000002100000011000000070000001200000002000200000000000100010000010203040503	\\xe7970118fd648462635e842ebdffd5071aab1a35f99b5e3fa7e403c3948a14ce	\N	{4,25,33,17,7,18}	function	4	{239,244}
246	\\x0000000007000000040000001000000019000000210000001100000007000000120000000200000002000000000001000100000100020304050604	\\x4a5c5725808725f85df456bb2698c3c9bf4774f3394cab5063e20d87de96a90d	\N	{4,16,25,33,17,7,18}	function	4	{161,245}
247	\\x0000000008000000040000001000000019000000210000001100000007000000120000000d000000020000000200000000000100010000000000010002030405060407	\\x41a7b2ee34486efb3e6ac53e03e46a374801cd5eb8359c97b61a310a0489e27a	\N	{4,16,25,33,17,7,18,13}	function	4	{246,165}
254	\\x0000000008000000040000001000000019000000210000001100000007000000120000000d000000020000000200000000000100010000000000010203040005060407	\\x843965b0347b8fe5725767434de9c9ed0d3620f3a6b28b6540c959bee8a53d75	\N	{4,16,25,33,17,7,18,13}	function	4	{249,253}
273	\\x00000000020001000900000012000000000001000100	\\x1e5ba2c6e4628dbc235b222563d9b386a5284003fbfc93ef56709807b164f803	\N	{9,18}	function	18	{1}
274	\\x00000100030001000200000009000000060000001200000000000200010001020003	\\x277ebd874a87fd7ecf6b6f8a3fee8ab49e161f153e8e409de3afc7e2d8af0c9d	\N	{9,6,18}	function	6	{273,38}
279	\\x0000000003000100090000000700000012000000000001000100010200	\\x3d2e9177114dbb359471eff37d886b0016673a61d25e529a0c8c13adc6cef61a	\\left(-\\sin\\left({}_\\text{?}a\\right)\\right)	{9,7,18}	function	7	{273}
386	\\x00000000020000002000000022000000010000000001	\\x2c6ebb99e93d11a68eb8e91dd7dfa4efaca7582cda8bbf08c3d07b21e52b9795	\\text{a}_{c}	{32,34}	function	32	{159}
387	\\x00000000030000001a0000001e00000022000000010001000000000102	\\xafbcd3f0d3bb92d6c0158cca5478a63ee332496d8046eea9f6af445a0fae285c	\\left|\\vec{a_{c}}\\right|	{26,30,34}	function	26	{306}
388	\\x000001000d000000020000001a0000000400000010000000060000001900000021000000110000000200000007000000130000000d000000120000000e000000010002000000020002000000000002000100010000000100000000010201030405060d07010809060a01080b060c	\\x82f1c00cb40349e2a7ab9a887afe27fdbc8aa0a176670819007d06472d7fbaff	\\left|r\\left(\\frac{\\partial}{\\partial t}\\left(\\theta\\right)^{2}\\left(\\left(-\\cos\\left(\\theta\\right)\\right)\\hat{i}+\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{j}\\right)\\right)\\right|	{26,4,16,6,25,33,17,2,7,19,13,18,14}	function	26	{383}
389	\\x000001000c000000020000001a00000004000000060000001900000021000000110000000200000007000000130000000d000000120000000e0000000100020002000200000000000200010001000000010000000001020304050c06010708050901070a050b	\\xa1278ea231f0747be46bc7d42f0fc2ecbafa816295554311b4cdf0718e795257	\\left|\\frac{\\partial}{\\partial t}\\left(\\theta\\right)^{2}\\left(\\left(-\\cos\\left(\\theta\\right)\\right)\\hat{i}+\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{j}\\right)\\right|	{26,4,6,25,33,17,2,7,19,13,18,14}	function	26	{382}
390	\\x000001000d00000002000000040000001a00000010000000060000001900000021000000110000000200000007000000130000000d000000120000000e00000002000100000002000200000000000200010001000000010000000001020100030405060d07000809060a00080b060c	\\x68ee69d0ecd3ed8dcb6683a534680d29cd036e3e9e11d5d5e2debb829dc2d6cc	\\left|r\\right|\\left|\\frac{\\partial}{\\partial t}\\left(\\theta\\right)^{2}\\left(\\left(-\\cos\\left(\\theta\\right)\\right)\\hat{i}+\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{j}\\right)\\right|	{4,26,16,6,25,33,17,2,7,19,13,18,14}	function	4	{296,389}
290	\\x000000000c0000001a00000004000000100000001900000021000000110000000200000007000000120000000d000000130000000e00000001000200000002000000000002000100010000000100000000010102030405060107080509010a050b	\\xaaf9c92833c583b8a34363d0bafd96459b0febdeccb8b6860f2c3fb2f621a147	\\left|r\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{i}+\\cos\\left(\\theta\\right)\\hat{j}\\right)\\right|	{26,4,16,25,33,17,2,7,18,13,19,14}	function	26	{257}
391	\\x0000010005000000020000001a0000000600000019000000210000001100000001000200020000000000000102030405	\\x4ce3dd49a5732a8d3942aa6dd313ee0cb76669ec934cb3e5a39d8b9ee8759a8f	\\left|\\frac{\\partial}{\\partial t}\\left(\\theta\\right)^{2}\\right|	{26,6,25,33,17}	function	26	{381}
280	\\x0000000005000100090000000400000007000000120000000d000000000002000100010000000102030004	\\xce030cb2d67c4aa8f1487feb3a21576df8201128d0982bed38861e54d97f1ea4	\\left(-\\sin\\left({}_\\text{?}a\\right)\\right)\\hat{i}	{9,4,7,18,13}	function	4	{279,165}
277	\\x000001000500010002000000090000000200000006000000120000001300000000000200020001000100010203000502040005	\\x80835f46d28ccf693c9cd532ea9ed7f903555d01f34259e75441a30572288e11	\\sin\\left({}_\\text{?}a\\right)^{2}+\\cos\\left({}_\\text{?}a\\right)^{2}	{9,2,6,18,19}	function	2	{274,276}
171	\\x000000000800000002000000040000001000000013000000110000000d000000120000000e0000000200020000000100000000000100000000010102030405010102060407	\\x26236484645cbb5e4e7e463f103f13eae1304a9a89d349c8cdb9698f35b1b8d5	r\\cos\\left(\\theta\\right)\\hat{i}+r\\sin\\left(\\theta\\right)\\hat{j}	{2,4,16,19,17,13,18,14}	function	2	{166,170}
278	\\x0000010001000000010000002400000001000001	\\xefad7b3f18a04f66665c76cf24692eef59e3c0862d88d054fb6e72ad39ea87bf	\\sqrt{1}	{36}	function	36	{13}
281	\\x00000000040001000900000004000000130000000e000000000002000100000001020003	\\x7d6d142bbc836c00929a8cb8c40d46818535434a876a8dcfb1ba00daa47e4b67	\\cos\\left({}_\\text{?}a\\right)\\hat{j}	{9,4,19,14}	function	4	{275,169}
282	\\x000000000800010009000000020000000400000007000000120000000d000000130000000e0000000000020002000100010000000100000001020304000502060007	\\x1c3bc956c13d4b9ca09de49f370260a1f8a047bdb721259970c72fa57696a7d9	\\left(-\\sin\\left({}_\\text{?}a\\right)\\right)\\hat{i}+\\cos\\left({}_\\text{?}a\\right)\\hat{j}	{9,2,4,7,18,13,19,14}	function	2	{280,281}
283	\\x0000000009000100090000001a000000020000000400000007000000120000000d000000130000000e0000000000010002000200010001000000010000000102030405000603070008	\\xe83fd1ea11f60c79249c110946d566bbe4a9c3e022a045346ba9ce9f38c3c504	\\left|\\left(-\\sin\\left({}_\\text{?}a\\right)\\right)\\hat{i}+\\cos\\left({}_\\text{?}a\\right)\\hat{j}\\right|	{9,26,2,4,7,18,13,19,14}	function	26	{282}
284	\\x0000010004000100020000000900000006000000070000001200000000000200010001000102030004	\\xb51b5397c66704a3e5e654ada6dba320a6470d91b5704679996f6f0994a0099b	\\left(-\\sin\\left({}_\\text{?}a\\right)\\right)^{2}	{9,6,7,18}	function	6	{279,38}
285	\\x00000100060001000200000009000000020000000600000007000000120000001300000000000200020001000100010001020304000602050006	\\x88e3133e0c6bb2b389d446fd73fd148e43347e9df4210fde356ee3e25c1bf726	\\left(-\\sin\\left({}_\\text{?}a\\right)\\right)^{2}+\\cos\\left({}_\\text{?}a\\right)^{2}	{9,2,6,7,18,19}	function	2	{284,276}
286	\\x0000010007000100020000000900000024000000020000000600000007000000120000001300000000000100020002000100010001000102030405000703060007	\\x4fd7072dd0c7225184b7c0b36c2d4b632459ec40ef4cecbab3f920866f51da0b	\\sqrt{\\left(-\\sin\\left({}_\\text{?}a\\right)\\right)^{2}+\\cos\\left({}_\\text{?}a\\right)^{2}}	{9,36,2,6,7,18,19}	function	36	{285}
287	\\x00000100060001000200000009000000240000000200000006000000120000001300000000000100020002000100010001020304000603050006	\\xc8ad7487d0e982d532a33af11da366e85253b9cf0d0d143c40c6303e652b9da1	\\sqrt{\\sin\\left({}_\\text{?}a\\right)^{2}+\\cos\\left({}_\\text{?}a\\right)^{2}}	{9,36,2,6,18,19}	function	36	{277}
257	\\x000000000b00000004000000100000001900000021000000110000000200000007000000120000000d000000130000000e000000020000000200000000000200010001000000010000000000010203040500060704080009040a	\\x551ccee4c5738de7fa2a8958b3ec04685c3f67afa11cdf87b42c2b598ce4a4c0	r\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{i}+\\cos\\left(\\theta\\right)\\hat{j}\\right)	{4,16,25,33,17,2,7,18,13,19,14}	function	4	{249,256}
288	\\x00000000020000001f00000022000000010000000001	\\xc69605d5252e0c27493bbb8bb8ccf82c31157b946c98b64d3438cd362a0baa8c	\\text{v}_{c}	{31,34}	function	31	{159}
289	\\x00000000030000001a0000001d00000022000000010001000000000102	\\x6ce66d33dfd1be8353c2180dfa2761ea07063b95be5c6305b0f9e4b1fab191c4	\\left|\\vec{v_{c}}\\right|	{26,29,34}	function	26	{219}
291	\\x00000000060000001a0000000400000010000000190000002100000011000000010002000000020000000000000102030405	\\x1df1071fa95f8246e61e0855d88c80d007e177ea22662a5d84bb758903a2d39f	\\left|r\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\right|	{26,4,16,25,33,17}	function	26	{249}
292	\\x00000000090000001a00000002000000040000000700000012000000110000000d000000130000000e0000000100020002000100010000000000010000000001020304050602070508	\\x548cd46ce4d3859d17c401e119bb80491c1a8c58e74f303b833a8a2338816bf5	\\left|\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{i}+\\cos\\left(\\theta\\right)\\hat{j}\\right|	{26,2,4,7,18,17,13,19,14}	function	26	{256}
293	\\x000000000c000000040000001a000000100000001900000021000000110000000200000007000000120000000d000000130000000e0000000200010000000200000000000200010001000000010000000001000203040501060007080509000a050b	\\x1ee97505341720d1278377ea72adad5af9b837544a62f59efc7a59043f4cb466	\\left|r\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\right|\\left|\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{i}+\\cos\\left(\\theta\\right)\\hat{j}\\right|	{4,26,16,25,33,17,2,7,18,13,19,14}	function	4	{291,292}
294	\\x000001000600000001000000040000001a000000100000001900000021000000110000000200010000000200000000000001000203040506	\\xbf2f12d315bc3d7ee42ca4ef12741c82e586612ef9098208a4a8a366d14b85ba	\\left|r\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\right|1	{4,26,16,25,33,17}	function	4	{291,13}
295	\\x000001000600000001000000040000001a000000100000001900000021000000110000000200010000000200000000000006010002030405	\\x93205b2fb9bb81bbfe445ec88367efb2e8169658e277d6baac03753aca9ff319	1\\left|r\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\right|	{4,26,16,25,33,17}	function	4	{13,291}
296	\\x00000000020000001a00000010000000010000000001	\\x710cd62ee5a8a47ece63c5257bc214d98d0178d352910e3cd03a512754594ddf	\\left|r\\right|	{26,16}	function	26	{161}
297	\\x00000000040000001a000000190000002100000011000000010002000000000000010203	\\x0ea56f27f544d378c36228b12e6c745e722a9380d505845ade1d2dda5844496d	\\left|\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\right|	{26,25,33,17}	function	26	{239}
298	\\x0000000006000000040000001a0000001000000019000000210000001100000002000100000002000000000000010201030405	\\xc6ac8721f7bb3e1d72520f89002847d115a944cee18cb250ab26b5bec3d23990	\\left|r\\right|\\left|\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\right|	{4,26,16,25,33,17}	function	4	{296,297}
299	\\x000000000100000025000000000000	\\x45de2038c8fe097d72ecaa4306d04e6c1fc0eadf6923bc283d4647b661147115	\\omega	{37}	function	37	{}
300	\\x0000000003000000190000002100000025000000020000000000000102	\\x51b9345711d2a7514909b5306e6772161b09bbd85a5ee3687170f5ca62346dfb	\\frac{\\partial}{\\partial t}\\left(\\omega\\right)	{25,33,37}	function	25	{150,299}
301	\\x00000000030000001900000021000000110000000200000000000001000102	\\xc5f12eed5d9cc10274fbde2445ad5caa678a6a8120a72f18f7065725097c7072	\\frac{\\partial}{\\partial t}\\left(\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\right)	{25,33,17}	function	25	{150,239}
221	\\x000000000a000000190000002100000002000000040000001000000013000000110000000d000000120000000e0000000200000002000200000001000000000001000000000102030304050607030304080609	\\x02fca970aeca6e074ccdb526abd97b96f3d811a8c16dbd351fb02c47bb60f1af	\\frac{\\partial}{\\partial t}\\left(r\\cos\\left(\\theta\\right)\\hat{i}+r\\sin\\left(\\theta\\right)\\hat{j}\\right)	{25,33,2,4,16,19,17,13,18,14}	function	25	{150,171}
227	\\x000000000a000000020000001900000021000000040000001000000013000000110000000d000000120000000e00000002000200000002000000010000000000010000000001020303040506070301020304080609	\\x843be09685030ceb8eec9e8ca035a37d863aa1fab6b054afb055bb588ade34fe	\\frac{\\partial}{\\partial t}\\left(r\\cos\\left(\\theta\\right)\\hat{i}\\right)+\\frac{\\partial}{\\partial t}\\left(r\\sin\\left(\\theta\\right)\\right)\\hat{j}	{2,25,33,4,16,19,17,13,18,14}	function	2	{222,226}
230	\\x000000000a000000020000000400000019000000210000001000000013000000110000000d000000120000000e00000002000200020000000000010000000000010000000001020301040506070102030104080609	\\x4721133f6b2ad3ada63adda76796bf63f09a06907be8a40e582c29ada5cc6b42	\\frac{\\partial}{\\partial t}\\left(r\\cos\\left(\\theta\\right)\\right)\\hat{i}+\\frac{\\partial}{\\partial t}\\left(r\\sin\\left(\\theta\\right)\\right)\\hat{j}	{2,4,25,33,16,19,17,13,18,14}	function	2	{229,226}
234	\\x000000000a000000020000000400000019000000210000001000000013000000110000000d000000120000000e00000002000200020000000000010000000000010000000001020301040506070101040203080609	\\x259497c451c9dd424886c47e5aa8e9f09667a0f9d713d68cdf85a9ea2948aa35	\\frac{\\partial}{\\partial t}\\left(r\\cos\\left(\\theta\\right)\\right)\\hat{i}+r\\frac{\\partial}{\\partial t}\\left(\\sin\\left(\\theta\\right)\\right)\\hat{j}	{2,4,25,33,16,19,17,13,18,14}	function	2	{229,233}
238	\\x000000000a000000020000000400000010000000190000002100000013000000110000000d000000120000000e00000002000200000002000000010000000000010000000001010203040506070101020304080609	\\x4dd7252e256cce0b72f53450012ddbc8e98816e17185ce53c2fdea5405356ac6	r\\frac{\\partial}{\\partial t}\\left(\\cos\\left(\\theta\\right)\\right)\\hat{i}+r\\frac{\\partial}{\\partial t}\\left(\\sin\\left(\\theta\\right)\\right)\\hat{j}	{2,4,16,25,33,19,17,13,18,14}	function	2	{237,233}
252	\\x000000000b00000002000000040000001000000019000000210000001100000007000000120000000d000000130000000e000000020002000000020000000000010001000000010000000001010201030405060705080101020304050109050a	\\x9638b3f35837f0f46e3389686256d0466889d0baf27cbe34d203896b1465a391	r\\left(\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(-\\sin\\left(\\theta\\right)\\right)\\right)\\hat{i}+r\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(\\cos\\left(\\theta\\right)\\hat{j}\\right)	{2,4,16,25,33,17,7,18,13,19,14}	function	2	{247,251}
255	\\x000000000b00000002000000040000001000000019000000210000001100000007000000120000000d000000130000000e000000020002000000020000000000010001000000010000000001010203040501060705080101020304050109050a	\\xd756f4adc8361fe9ccebac8d4d70bb8189e33910ec04ee1f1b0bf7a062eaf7f8	r\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{i}\\right)+r\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(\\cos\\left(\\theta\\right)\\hat{j}\\right)	{2,4,16,25,33,17,7,18,13,19,14}	function	2	{254,251}
248	\\x000000000b00000002000000040000001000000019000000210000001100000007000000120000000d000000130000000e000000020002000000020000000000010001000000010000000001010201030405060705080101020103040509050a	\\x0aff7ae3946e667cc220f917ac23005ab99699d996f4855e533fd6b04cac4ba7	r\\left(\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(-\\sin\\left(\\theta\\right)\\right)\\right)\\hat{i}+r\\left(\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\cos\\left(\\theta\\right)\\right)\\hat{j}	{2,4,16,25,33,17,7,18,13,19,14}	function	2	{247,242}
302	\\x000000000400020014000000090000001900000007000000000000000200010002000301	\\xb08adf47e3ebb5a4e76193cafa40e5afa5272d33bdaa01d9442e6aad22133a16	\\frac{\\partial}{\\partial{}_\\text{?}x}\\left(\\left(-{}_\\text{?}a\\right)\\right)	{20,9,25,7}	function	25	{21,12}
303	\\x000000000400020014000000090000000700000019000000000000000100020002030001	\\xa1579022e4ad1904adf6ffda46c3bec67c1c1251e619549458d2ee0c3f9c8a92	\\left(-\\frac{\\partial}{\\partial{}_\\text{?}x}\\left({}_\\text{?}a\\right)\\right)	{20,9,7,25}	function	7	{182}
304	\\x0000000004000200090000000a0000000700000004000000000000000100020002030001	\\x826d50e5094401ecfd21fe28546cc01d0aa32a15a4777df3e63929bf542e1598	\\left(-{}_\\text{?}a{}_\\text{?}b\\right)	{9,10,7,4}	function	7	{6}
305	\\x0000000004000200090000000a0000000400000007000000000000000200010002000301	\\x14c81fcb67f6218b58bb701bf1533460727faaa1fb167f8c5f54e13c7b545ef7	{}_\\text{?}a\\left(-{}_\\text{?}b\\right)	{9,10,4,7}	function	4	{1,3}
306	\\x00000000020000001e00000022000000010000000001	\\x1aa8f3340facea8191838a8df16d0c7500ee7b5c523f30456375b49f965881cf	\\vec{a_{c}}	{30,34}	function	30	{159}
307	\\x000000000400000019000000210000001d00000022000000020000000100000000010203	\\x7e7759cb1c46ab236377951b39d8583a04ee3e6e6ebb0b2515190256e973fa17	\\frac{\\partial}{\\partial t}\\left(\\vec{v_{c}}\\right)	{25,33,29,34}	function	25	{150,219}
308	\\x000000000b00000019000000210000000400000010000000110000000200000007000000120000000d000000130000000e0000000200000002000000000002000100010000000100000000010202030001040502060704080209040a	\\x41f0c25aaad6626c8e289b464f828c6b82eaa8a64e36919c695f8b95db1e59d1	\\frac{\\partial}{\\partial t}\\left(r\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{i}+\\cos\\left(\\theta\\right)\\hat{j}\\right)\\right)	{25,33,4,16,17,2,7,18,13,19,14}	function	25	{150,257}
392	\\x00000000090000001a00000002000000040000000700000013000000110000000d000000120000000e000000010002000200010001000000000001000000000102030405060203070508	\\x82e8dec492dbcbdec14c06dafc4b4d808df8bd4a8954a2c9e6a444c2a0083487	\\left|\\left(-\\cos\\left(\\theta\\right)\\right)\\hat{i}+\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{j}\\right|	{26,2,4,7,19,17,13,18,14}	function	26	{374}
309	\\x000000000a000000040000001900000021000000110000000200000007000000120000000d000000130000000e00000002000200000000000200010001000000010000000001020304000506030700080309	\\xab86fadacca415566109cb6f3279f01cdcfb4c48fb7bb5a52fc1dcfde1c13f11	\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{i}+\\cos\\left(\\theta\\right)\\hat{j}\\right)	{4,25,33,17,2,7,18,13,19,14}	function	4	{239,256}
310	\\x000000000b00000004000000100000001900000021000000110000000200000007000000120000000d000000130000000e000000020000000200000000000200010001000000010000000001000203040500060704080009040a	\\xf52c9118de799964d7d28e3c8ca8bac3aa7863c3f3b5f0ddeadd87325bcaa891	r\\left(\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{i}+\\cos\\left(\\theta\\right)\\hat{j}\\right)\\right)	{4,16,25,33,17,2,7,18,13,19,14}	function	4	{161,309}
311	\\x000000000b00000019000000210000000400000010000000110000000200000007000000120000000d000000130000000e0000000200000002000000000002000100010000000100000000010203020001040502060704080209040a	\\x56674d7fffbd959bd62923fe8a33cf165ba5e610e45e8182051d195ac7668baf	\\frac{\\partial}{\\partial t}\\left(r\\left(\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{i}+\\cos\\left(\\theta\\right)\\hat{j}\\right)\\right)\\right)	{25,33,4,16,17,2,7,18,13,19,14}	function	25	{150,310}
312	\\x000000000b00000004000000190000002100000010000000110000000200000007000000120000000d000000130000000e0000000200020000000000000002000100010000000100000000010203000102040500060704080009040a	\\xbc73c1c329c1830caccace92e05d6b15de669c7b76bce1c9d3edbd04c3afcddd	\\frac{\\partial}{\\partial t}\\left(r\\right)\\left(\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{i}+\\cos\\left(\\theta\\right)\\hat{j}\\right)\\right)	{4,25,33,16,17,2,7,18,13,19,14}	function	4	{204,309}
313	\\x000000000a000000190000002100000004000000110000000200000007000000120000000d000000130000000e000000020000000200000002000100010000000100000000010200010304020506030702080309	\\xd7daaa021aa6530eea502ddc54fb028d23fd7baab30897e21e9b24364f8852de	\\frac{\\partial}{\\partial t}\\left(\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{i}+\\cos\\left(\\theta\\right)\\hat{j}\\right)\\right)	{25,33,4,17,2,7,18,13,19,14}	function	25	{150,309}
314	\\x000000000b00000004000000100000001900000021000000110000000200000007000000120000000d000000130000000e0000000200000002000000000002000100010000000100000000010203000203040500060704080009040a	\\x84a37ed53a720c081511a31e846358f50e419e25648c0c8323442d6657a34154	r\\frac{\\partial}{\\partial t}\\left(\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{i}+\\cos\\left(\\theta\\right)\\hat{j}\\right)\\right)	{4,16,25,33,17,2,7,18,13,19,14}	function	4	{161,313}
315	\\x000000000b00000002000000040000001900000021000000100000001100000007000000120000000d000000130000000e000000020002000200000000000000010001000000010000000001020304010203050001060705080109050a01040203010203050001060705080109050a	\\xdbf6dab682861a304baa19364d4f1bf0efed68b455e0a447f93f64f5db716193	\\frac{\\partial}{\\partial t}\\left(r\\right)\\left(\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{i}+\\cos\\left(\\theta\\right)\\hat{j}\\right)\\right)+r\\frac{\\partial}{\\partial t}\\left(\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{i}+\\cos\\left(\\theta\\right)\\hat{j}\\right)\\right)	{2,4,25,33,16,17,7,18,13,19,14}	function	2	{312,314}
316	\\x000001000a00000000000000040000001900000021000000110000000200000007000000120000000d000000130000000e0000000200020000000000020001000100000001000000000a0001020304000506030700080309	\\x54fff71fc2b0bdddb75eb3506cc4e32eaab62db9311a917235659c987d76a24b	0\\left(\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{i}+\\cos\\left(\\theta\\right)\\hat{j}\\right)\\right)	{4,25,33,17,2,7,18,13,19,14}	function	4	{25,309}
317	\\x000001000b00000000000000020000000400000019000000210000001100000007000000120000000d000000130000000e000000100000000200020002000000000001000100000001000000000000010b0102030400010506040701080409010a02030102030400010506040701080409	\\xf8c7937658a04d975e5f66ad6c4586e3f90d60a7c88b8f16eab0bbc2d4470f48	0\\left(\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{i}+\\cos\\left(\\theta\\right)\\hat{j}\\right)\\right)+r\\frac{\\partial}{\\partial t}\\left(\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{i}+\\cos\\left(\\theta\\right)\\hat{j}\\right)\\right)	{2,4,25,33,17,7,18,13,19,14,16}	function	2	{316,314}
318	\\x000001000b0000000000000002000000040000001000000019000000210000001100000007000000120000000d000000130000000e00000002000200000002000000000001000100000001000000000b01020304010304050001060705080109050a	\\x3eafb8f9949ff6b34ef1ed3e77bbeeb9c60aecfaf00f6ffa16b58b89e85b16cc	0+r\\frac{\\partial}{\\partial t}\\left(\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{i}+\\cos\\left(\\theta\\right)\\hat{j}\\right)\\right)	{2,4,16,25,33,17,7,18,13,19,14}	function	2	{25,314}
319	\\x000000000a000000040000001900000021000000110000000200000007000000120000000d000000130000000e000000020002000000000002000100010000000100000000010201020304000506030700080309	\\x2886ccd585b7a7e6ee674d3353249179ce7ded28233b63de6a9f7a82f4aca1e5	\\frac{\\partial}{\\partial t}\\left(\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\right)\\left(\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{i}+\\cos\\left(\\theta\\right)\\hat{j}\\right)	{4,25,33,17,2,7,18,13,19,14}	function	4	{301,256}
320	\\x000000000a000000190000002100000002000000040000000700000012000000110000000d000000130000000e0000000200000002000200010001000000000001000000000102030405060703080609	\\xcc19d48f1b9d696eeb5b99ed6cc9f5b6f4a9a27865e70e13340bb1aebb5355fd	\\frac{\\partial}{\\partial t}\\left(\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{i}+\\cos\\left(\\theta\\right)\\hat{j}\\right)	{25,33,2,4,7,18,17,13,19,14}	function	25	{150,256}
321	\\x000000000a000000040000001900000021000000110000000200000007000000120000000d000000130000000e000000020002000000000002000100010000000100000000010203010204000506030700080309	\\xcc049bad4cf75edc403807bc0fac67df196a268e989528b83fd0b1606436d126	\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\frac{\\partial}{\\partial t}\\left(\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{i}+\\cos\\left(\\theta\\right)\\hat{j}\\right)	{4,25,33,17,2,7,18,13,19,14}	function	4	{239,320}
322	\\x000000000a000000020000000400000019000000210000001100000007000000120000000d000000130000000e0000000200020002000000000001000100000001000000000102030203040001050604070108040901020304020300010506040701080409	\\xbbc9aef5a42735601a1ef000b90ff1e4afdc4d51659ec248bb7381babc0737a7	\\frac{\\partial}{\\partial t}\\left(\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\right)\\left(\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{i}+\\cos\\left(\\theta\\right)\\hat{j}\\right)+\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\frac{\\partial}{\\partial t}\\left(\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{i}+\\cos\\left(\\theta\\right)\\hat{j}\\right)	{2,4,25,33,17,7,18,13,19,14}	function	2	{319,321}
323	\\x000000000b00000004000000100000000200000019000000210000001100000007000000120000000d000000130000000e000000020000000200020000000000010001000000010000000001020003040304050200060705080009050a0003040503040200060705080009050a	\\x5cf8673cea67bad20e084743d1d04e22122661b8d127800a79d08aa59de7d717	r\\left(\\frac{\\partial}{\\partial t}\\left(\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\right)\\left(\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{i}+\\cos\\left(\\theta\\right)\\hat{j}\\right)+\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\frac{\\partial}{\\partial t}\\left(\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{i}+\\cos\\left(\\theta\\right)\\hat{j}\\right)\\right)	{4,16,2,25,33,17,7,18,13,19,14}	function	4	{161,322}
324	\\x00000100080000000000000004000000020000000700000012000000110000000d000000130000000e00000002000200010001000000000001000000000801000203040500060407	\\x56223fe13a0b87ff7e0a747179b154b8db2d2f237480f98412860308b7b3e3ab	0\\left(\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{i}+\\cos\\left(\\theta\\right)\\hat{j}\\right)	{4,2,7,18,17,13,19,14}	function	4	{25,256}
325	\\x000001000a0000000000000002000000040000000700000012000000110000000d000000130000000e0000001900000021000000020002000100010000000000010000000200000000010a0001020304050106040701080904080900010203040501060407	\\x705756f41b976de5299acd115da60d9693f9ec62825b8c2580565cf610c7f3ae	0\\left(\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{i}+\\cos\\left(\\theta\\right)\\hat{j}\\right)+\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\frac{\\partial}{\\partial t}\\left(\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{i}+\\cos\\left(\\theta\\right)\\hat{j}\\right)	{2,4,7,18,17,13,19,14,25,33}	function	2	{324,321}
326	\\x000001000b000000000000000400000010000000020000000700000012000000110000000d000000130000000e000000190000002100000002000000020001000100000000000100000002000000000102000b0200030405060007050800090a05090a02000304050600070508	\\x24d1bdcabc08c646acef7b8254e900fc2189e9d4b7ff02636421163466833271	r\\left(0\\left(\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{i}+\\cos\\left(\\theta\\right)\\hat{j}\\right)+\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\frac{\\partial}{\\partial t}\\left(\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{i}+\\cos\\left(\\theta\\right)\\hat{j}\\right)\\right)	{4,16,2,7,18,17,13,19,14,25,33}	function	4	{161,325}
327	\\x000001000a00000000000000020000000400000019000000210000001100000007000000120000000d000000130000000e0000000200020002000000000001000100000001000000000a01020304020300010506040701080409	\\x292b420061f011fae6efdeb4cde22a2028ebbd1ec8c703e2bf410d20d8e06da2	0+\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\frac{\\partial}{\\partial t}\\left(\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{i}+\\cos\\left(\\theta\\right)\\hat{j}\\right)	{2,4,25,33,17,7,18,13,19,14}	function	2	{25,321}
328	\\x000001000b0000000000000004000000100000000200000019000000210000001100000007000000120000000d000000130000000e000000020000000200020000000000010001000000010000000001020b0003040503040200060705080009050a	\\xaf4d9bfa4c1417f6832e97d6879e252bbbcea3e4d1c36886fc912c4e2bbf2ac5	r\\left(0+\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\frac{\\partial}{\\partial t}\\left(\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{i}+\\cos\\left(\\theta\\right)\\hat{j}\\right)\\right)	{4,16,2,25,33,17,7,18,13,19,14}	function	4	{161,327}
329	\\x000000000b00000004000000100000001900000021000000110000000200000007000000120000000d000000130000000e0000000200000002000000000002000100010000000100000000010002030402030500060704080009040a	\\x10e33c73beef52fea5bf1772366b1b83a92c7677f26a73b586bec8796c15dd55	r\\left(\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\frac{\\partial}{\\partial t}\\left(\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{i}+\\cos\\left(\\theta\\right)\\hat{j}\\right)\\right)	{4,16,25,33,17,2,7,18,13,19,14}	function	4	{161,321}
330	\\x00000000070000001900000021000000040000000700000012000000110000000d000000020000000200010001000000000000010203040506	\\xa042f952fea2709bcce1c64079b2754e57a42a3ae6879452f714afe1fee01904	\\frac{\\partial}{\\partial t}\\left(\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{i}\\right)	{25,33,4,7,18,17,13}	function	25	{150,253}
331	\\x000000000600000019000000210000000400000013000000110000000e000000020000000200010000000000000102030405	\\x684f78d624adc37d36cfb8862bb20dcb29ecce04bfd5dbef1f4524eb0672ceb5	\\frac{\\partial}{\\partial t}\\left(\\cos\\left(\\theta\\right)\\hat{j}\\right)	{25,33,4,19,17,14}	function	25	{150,250}
332	\\x000000000a000000020000001900000021000000040000000700000012000000110000000d000000130000000e00000002000200000002000100010000000000010000000001020304050607010203080609	\\xe2bd35184fcf7de49e0d1aab9cd05c65290e064bb7084557c60a1b2d7a72bd22	\\frac{\\partial}{\\partial t}\\left(\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{i}\\right)+\\frac{\\partial}{\\partial t}\\left(\\cos\\left(\\theta\\right)\\hat{j}\\right)	{2,25,33,4,7,18,17,13,19,14}	function	2	{330,331}
333	\\x000000000a000000040000001900000021000000110000000200000007000000120000000d000000130000000e0000000200020000000000020001000100000001000000000102030401020005060307010200080309	\\xdafa0f35240b31b9b3dfc36c879503dee4a108cfe4f42be87653d4be28b7c752	\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(\\frac{\\partial}{\\partial t}\\left(\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{i}\\right)+\\frac{\\partial}{\\partial t}\\left(\\cos\\left(\\theta\\right)\\hat{j}\\right)\\right)	{4,25,33,17,2,7,18,13,19,14}	function	4	{239,332}
334	\\x000000000b00000004000000100000001900000021000000110000000200000007000000120000000d000000130000000e00000002000000020000000000020001000100000001000000000100020304050203000607040802030009040a	\\x228b60b46a1820916387a1f51be26f90b818c9aed7b1115b43fa3819665255f0	r\\left(\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(\\frac{\\partial}{\\partial t}\\left(\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{i}\\right)+\\frac{\\partial}{\\partial t}\\left(\\cos\\left(\\theta\\right)\\hat{j}\\right)\\right)\\right)	{4,16,25,33,17,2,7,18,13,19,14}	function	4	{161,333}
335	\\x000000000600000004000000190000002100000013000000110000000e000000020002000000010000000000000102030405	\\x50512a8e5a8ca1db6d7ce2954d350354932002f10065f2d8d4a6c13fb307c056	\\frac{\\partial}{\\partial t}\\left(\\cos\\left(\\theta\\right)\\right)\\hat{j}	{4,25,33,19,17,14}	function	4	{235,169}
336	\\x000000000a000000020000001900000021000000040000000700000012000000110000000d000000130000000e00000002000200000002000100010000000000010000000001020304050607030102080609	\\x5b8845ee2c603ef6b800f3c9cd441de76d4efc91613af88c7de91258bb9a8805	\\frac{\\partial}{\\partial t}\\left(\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{i}\\right)+\\frac{\\partial}{\\partial t}\\left(\\cos\\left(\\theta\\right)\\right)\\hat{j}	{2,25,33,4,7,18,17,13,19,14}	function	2	{330,335}
337	\\x000000000a000000040000001900000021000000110000000200000007000000120000000d000000130000000e0000000200020000000000020001000100000001000000000102030401020005060307000102080309	\\x535a36dda0884638dac5afe4abd0b8fff713ca948203d3ab7eb0bbc446d8a48b	\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(\\frac{\\partial}{\\partial t}\\left(\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{i}\\right)+\\frac{\\partial}{\\partial t}\\left(\\cos\\left(\\theta\\right)\\right)\\hat{j}\\right)	{4,25,33,17,2,7,18,13,19,14}	function	4	{239,336}
338	\\x000000000b00000004000000100000001900000021000000110000000200000007000000120000000d000000130000000e00000002000000020000000000020001000100000001000000000100020304050203000607040800020309040a	\\xad28cb666af9dbab8611f9dfb781e1dc2bca57c980fe688e0f836de7d08782dc	r\\left(\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(\\frac{\\partial}{\\partial t}\\left(\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{i}\\right)+\\frac{\\partial}{\\partial t}\\left(\\cos\\left(\\theta\\right)\\right)\\hat{j}\\right)\\right)	{4,16,25,33,17,2,7,18,13,19,14}	function	4	{161,337}
339	\\x00000000050000001900000021000000070000001200000011000000020000000100010000000001020304	\\x63491cfee56e4b4a2c536b5d71cb2e601ebe7a53fe5a58376c20a95d93bb9062	\\frac{\\partial}{\\partial t}\\left(\\left(-\\sin\\left(\\theta\\right)\\right)\\right)	{25,33,7,18,17}	function	25	{150,244}
340	\\x00000000070000000400000019000000210000000700000012000000110000000d000000020002000000010001000000000000010203040506	\\xcd7455d14e3af830f166f0b8db4f8239574d1785c4811a7b9fbc8d811b45b4aa	\\frac{\\partial}{\\partial t}\\left(\\left(-\\sin\\left(\\theta\\right)\\right)\\right)\\hat{i}	{4,25,33,7,18,17,13}	function	4	{339,165}
341	\\x000000000a000000020000000400000019000000210000000700000012000000110000000d000000130000000e00000002000200020000000100010000000000010000000001020304050607010203080609	\\xa9f91ce60099a9a29fb883a70d3876ff92ca47afe8366a4e309c51632cc4e673	\\frac{\\partial}{\\partial t}\\left(\\left(-\\sin\\left(\\theta\\right)\\right)\\right)\\hat{i}+\\frac{\\partial}{\\partial t}\\left(\\cos\\left(\\theta\\right)\\right)\\hat{j}	{2,4,25,33,7,18,17,13,19,14}	function	2	{340,335}
342	\\x000000000a000000040000001900000021000000110000000200000007000000120000000d000000130000000e0000000200020000000000020001000100000001000000000102030400010205060307000102080309	\\x03440106927a6ac4f1f9785bc34b4c847e786967e7cdf84865385156bc987c0b	\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(\\frac{\\partial}{\\partial t}\\left(\\left(-\\sin\\left(\\theta\\right)\\right)\\right)\\hat{i}+\\frac{\\partial}{\\partial t}\\left(\\cos\\left(\\theta\\right)\\right)\\hat{j}\\right)	{4,25,33,17,2,7,18,13,19,14}	function	4	{239,341}
343	\\x000000000b00000004000000100000001900000021000000110000000200000007000000120000000d000000130000000e00000002000000020000000000020001000100000001000000000100020304050002030607040800020309040a	\\xebd2da7552182c916180b5a787fa26ae0b3facd751b232085d152504a95f9e85	r\\left(\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(\\frac{\\partial}{\\partial t}\\left(\\left(-\\sin\\left(\\theta\\right)\\right)\\right)\\hat{i}+\\frac{\\partial}{\\partial t}\\left(\\cos\\left(\\theta\\right)\\right)\\hat{j}\\right)\\right)	{4,16,25,33,17,2,7,18,13,19,14}	function	4	{161,342}
344	\\x00000000050000000700000019000000210000001200000011000000010002000000010000000001020304	\\x9cee4a7f87b0b3cd71076e67c294ba0534be2e92d44e79fddb805aac6a0b5426	\\left(-\\frac{\\partial}{\\partial t}\\left(\\sin\\left(\\theta\\right)\\right)\\right)	{7,25,33,18,17}	function	7	{231}
345	\\x00000000070000000400000007000000190000002100000012000000110000000d000000020001000200000001000000000000010203040506	\\x8200f91ae3ff16f5c515a11ccf0fbff04328203c500eb04357cb36e628041341	\\left(-\\frac{\\partial}{\\partial t}\\left(\\sin\\left(\\theta\\right)\\right)\\right)\\hat{i}	{4,7,25,33,18,17,13}	function	4	{344,165}
346	\\x000000000a000000020000000400000007000000190000002100000012000000110000000d000000130000000e00000002000200010002000000010000000000010000000001020304050607010304080609	\\xc4c471ce8f8ed3a31bc731bc31a8fddff663bd7881b2e108762527d14cd2b015	\\left(-\\frac{\\partial}{\\partial t}\\left(\\sin\\left(\\theta\\right)\\right)\\right)\\hat{i}+\\frac{\\partial}{\\partial t}\\left(\\cos\\left(\\theta\\right)\\right)\\hat{j}	{2,4,7,25,33,18,17,13,19,14}	function	2	{345,335}
347	\\x000000000a000000040000001900000021000000110000000200000007000000120000000d000000130000000e0000000200020000000000020001000100000001000000000102030400050102060307000102080309	\\x95bc1762c90947cc63709e21809bf2a5ec6b23ebc9e21887a9191c21c03c5999	\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(\\left(-\\frac{\\partial}{\\partial t}\\left(\\sin\\left(\\theta\\right)\\right)\\right)\\hat{i}+\\frac{\\partial}{\\partial t}\\left(\\cos\\left(\\theta\\right)\\right)\\hat{j}\\right)	{4,25,33,17,2,7,18,13,19,14}	function	4	{239,346}
348	\\x000000000b00000004000000100000001900000021000000110000000200000007000000120000000d000000130000000e00000002000000020000000000020001000100000001000000000100020304050006020307040800020309040a	\\x4a83ff18aedb92a81dc0059a445ddb3e8770ebb591bc6cdafe832d0a466df646	r\\left(\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(\\left(-\\frac{\\partial}{\\partial t}\\left(\\sin\\left(\\theta\\right)\\right)\\right)\\hat{i}+\\frac{\\partial}{\\partial t}\\left(\\cos\\left(\\theta\\right)\\right)\\hat{j}\\right)\\right)	{4,16,25,33,17,2,7,18,13,19,14}	function	4	{161,347}
349	\\x00000000070000000400000019000000210000001100000007000000120000000e0000000200020000000000010001000000000001020304050306	\\xb3ef934c627f0c516481e96dbad73e4b7a730ab75f582fa3235999c0d91d22a9	\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{j}	{4,25,33,17,7,18,14}	function	4	{245,169}
350	\\x0000000009000000020000000400000007000000190000002100000012000000110000000d0000000e0000000200020001000200000001000000000000000001020304050607010103040602050608	\\x59124b3e414f148ddee1ba4cc6dc35ffc20da7285c13343cc0cbb9e24881e161	\\left(-\\frac{\\partial}{\\partial t}\\left(\\sin\\left(\\theta\\right)\\right)\\right)\\hat{i}+\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{j}	{2,4,7,25,33,18,17,13,14}	function	2	{345,349}
351	\\x0000000009000000040000001900000021000000110000000200000007000000120000000d0000000e000000020002000000000002000100010000000000000102030400050102060307000001020305060308	\\x491825b2568bad3743312a5f7be7a1e66abdb9ad9cfa2af9757593e334d4aded	\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(\\left(-\\frac{\\partial}{\\partial t}\\left(\\sin\\left(\\theta\\right)\\right)\\right)\\hat{i}+\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{j}\\right)	{4,25,33,17,2,7,18,13,14}	function	4	{239,350}
352	\\x000000000a00000004000000100000001900000021000000110000000200000007000000120000000d0000000e00000002000000020000000000020001000100000000000001000203040500060203070408000002030406070409	\\x3bd9e50c35e5cc851d584ca215839cc80fc61df272355082975f38312e613da3	r\\left(\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(\\left(-\\frac{\\partial}{\\partial t}\\left(\\sin\\left(\\theta\\right)\\right)\\right)\\hat{i}+\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{j}\\right)\\right)	{4,16,25,33,17,2,7,18,13,14}	function	4	{161,351}
353	\\x000000000600000007000000040000001900000021000000110000001300000001000200020000000000010000010203040504	\\x1614a6966bc1745b90d11d887c29babdc8a9ba3830ba891a4a1f04039a1ce54d	\\left(-\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\cos\\left(\\theta\\right)\\right)	{7,4,25,33,17,19}	function	7	{240}
354	\\x00000000070000000400000007000000190000002100000011000000130000000d0000000200010002000000000001000000000100020304050406	\\x8997963638cd531676f0b89e0abb1cf4c1e7067c9f28eb8940125175cb2fa960	\\left(-\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\cos\\left(\\theta\\right)\\right)\\hat{i}	{4,7,25,33,17,19,13}	function	4	{353,165}
355	\\x000000000a000000020000000400000007000000190000002100000011000000130000000d000000120000000e000000020002000100020000000000010000000100000000010201030405060507010103040502080509	\\xf87414059201938a8251c6aaf6ee8804c975e527c14850b2274472b6500f15da	\\left(-\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\cos\\left(\\theta\\right)\\right)\\hat{i}+\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{j}	{2,4,7,25,33,17,19,13,18,14}	function	2	{354,349}
356	\\x000000000a000000040000001900000021000000110000000200000007000000130000000d000000120000000e00000002000200000000000200010001000000010000000001020304000500010203060307000001020305080309	\\x1f0ea0edd15d6892e18d6b5c4b3eea9ee334248290332ee2ac91c5164d3e53fe	\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(\\left(-\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\cos\\left(\\theta\\right)\\right)\\hat{i}+\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{j}\\right)	{4,25,33,17,2,7,19,13,18,14}	function	4	{239,355}
357	\\x000000000b00000004000000100000001900000021000000110000000200000007000000130000000d000000120000000e000000020000000200000000000200010001000000010000000001000203040500060002030407040800000203040609040a	\\x9ec33f855c828f4215fb26b115220a69fdab4376659332057c71a782b9f87d25	r\\left(\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(\\left(-\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\cos\\left(\\theta\\right)\\right)\\hat{i}+\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{j}\\right)\\right)	{4,16,25,33,17,2,7,19,13,18,14}	function	4	{161,356}
358	\\x0000000003000000070000001300000011000000010001000000000102	\\xb9f9a325a30a76747dbc84a5a9204e527c9e64b6d2b3aa67b1435ffe5dcdfe31	\\left(-\\cos\\left(\\theta\\right)\\right)	{7,19,17}	function	7	{163}
359	\\x000000000600000004000000190000002100000011000000070000001300000002000200000000000100010000010203040503	\\xda5cbae55946c8fdc37b0c674da91b98a2440c9a76cdf05c41471e8045c3ca93	\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(-\\cos\\left(\\theta\\right)\\right)	{4,25,33,17,7,19}	function	4	{239,358}
360	\\x00000000070000000400000019000000210000001100000007000000130000000d0000000200020000000000010001000000000001020304050306	\\xbf0d57407baf12459d3b4b2a144c2cc416f1849a7b936d60a3f0752bf65c2ec8	\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(-\\cos\\left(\\theta\\right)\\right)\\hat{i}	{4,25,33,17,7,19,13}	function	4	{359,165}
361	\\x000000000a000000020000000400000019000000210000001100000007000000130000000d000000120000000e000000020002000200000000000100010000000100000000010102030405060407010102030405080409	\\x7ffb62cf9e9254dd20593534199c143c089b2d56b8ef885a03385c9af590ebe9	\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(-\\cos\\left(\\theta\\right)\\right)\\hat{i}+\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{j}	{2,4,25,33,17,7,19,13,18,14}	function	2	{360,349}
362	\\x000000000a000000040000001900000021000000110000000200000007000000130000000d000000120000000e00000002000200000000000200010001000000010000000001020304000001020305060307000001020305080309	\\x2cccee3c891629694cd821fd207170c5f7ee518220b0cf8167b2d23bfd2f83db	\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(-\\cos\\left(\\theta\\right)\\right)\\hat{i}+\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{j}\\right)	{4,25,33,17,2,7,19,13,18,14}	function	4	{239,361}
363	\\x000000000b00000004000000100000001900000021000000110000000200000007000000130000000d000000120000000e000000020000000200000000000200010001000000010000000001000203040500000203040607040800000203040609040a	\\x3d5ed9fe6e47e17dcba64431902019012ccdae863f4ed6eed36521409923bb50	r\\left(\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(-\\cos\\left(\\theta\\right)\\right)\\hat{i}+\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{j}\\right)\\right)	{4,16,25,33,17,2,7,19,13,18,14}	function	4	{161,362}
364	\\x0000000005000000040000000700000012000000110000000e000000020001000100000000000001020304	\\x3f31080d2d9adb81323807be124faa622d0ee2dbde94e13c8c6830e83e7bf14e	\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{j}	{4,7,18,17,14}	function	4	{244,169}
365	\\x00000000070000000400000019000000210000001100000007000000120000000e0000000200020000000000010001000000000102030004050306	\\xddec052613f7a7588a9ba766f338a8f74e18539c012a7e2f3e0861cc159a0c6b	\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{j}\\right)	{4,25,33,17,7,18,14}	function	4	{239,364}
366	\\x000000000a000000020000000400000019000000210000001100000007000000130000000d000000120000000e000000020002000200000000000100010000000100000000010102030405060407010203040105080409	\\xf86d5cc9940d75a0ccaf393702b40fb1b38bed5e63e86c7121800d4685b026ba	\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(-\\cos\\left(\\theta\\right)\\right)\\hat{i}+\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{j}\\right)	{2,4,25,33,17,7,19,13,18,14}	function	2	{360,365}
367	\\x000000000a000000040000001900000021000000110000000200000007000000130000000d000000120000000e00000002000200000000000200010001000000010000000001020304000001020305060307000102030005080309	\\x1fb024fa8f90e361ec6496a510a7807cbefacb9e048c4c013fd44c4ec414c1e4	\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(-\\cos\\left(\\theta\\right)\\right)\\hat{i}+\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{j}\\right)\\right)	{4,25,33,17,2,7,19,13,18,14}	function	4	{239,366}
368	\\x000000000b00000004000000100000001900000021000000110000000200000007000000130000000d000000120000000e000000020000000200000000000200010001000000010000000001000203040500000203040607040800020304000609040a	\\xa541e28100efa27d4de9e6f1499f7a749a9382fae4c3f89dc84ee8fb8662be29	r\\left(\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(-\\cos\\left(\\theta\\right)\\right)\\hat{i}+\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{j}\\right)\\right)\\right)	{4,16,25,33,17,2,7,19,13,18,14}	function	4	{161,367}
369	\\x0000000005000000040000000700000013000000110000000d000000020001000100000000000001020304	\\xaaa269047af96af1e382389b43e0231f8489a4566e5323c929ae219ad247d86b	\\left(-\\cos\\left(\\theta\\right)\\right)\\hat{i}	{4,7,19,17,13}	function	4	{358,165}
370	\\x00000000070000000400000019000000210000001100000007000000130000000d0000000200020000000000010001000000000102030004050306	\\xd84fb295766f5c4192b38f24326d50f2268cf45f02e3e44cebab685cf81cf610	\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(\\left(-\\cos\\left(\\theta\\right)\\right)\\hat{i}\\right)	{4,25,33,17,7,19,13}	function	4	{239,369}
371	\\x000000000a000000020000000400000019000000210000001100000007000000130000000d000000120000000e000000020002000200000000000100010000000100000000010203040105060407010203040105080409	\\xe21e7ed89edd5fd17822c4086966b83f41380d401fb58237b94beafbaddb3cdc	\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(\\left(-\\cos\\left(\\theta\\right)\\right)\\hat{i}\\right)+\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{j}\\right)	{2,4,25,33,17,7,19,13,18,14}	function	2	{370,365}
372	\\x000000000a000000040000001900000021000000110000000200000007000000130000000d000000120000000e00000002000200000000000200010001000000010000000001020304000102030005060307000102030005080309	\\x58b905edd907f8ae5068227fd1f2bd44e3161ca198c994e679dc578edbd5e516	\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(\\left(-\\cos\\left(\\theta\\right)\\right)\\hat{i}\\right)+\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{j}\\right)\\right)	{4,25,33,17,2,7,19,13,18,14}	function	4	{239,371}
373	\\x000000000b00000004000000100000001900000021000000110000000200000007000000130000000d000000120000000e000000020000000200000000000200010001000000010000000001000203040500020304000607040800020304000609040a	\\x3508c98373890873c303353cb1f23bb67d4b48fadd667c26942d42bd523dfc8d	r\\left(\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(\\left(-\\cos\\left(\\theta\\right)\\right)\\hat{i}\\right)+\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{j}\\right)\\right)\\right)	{4,16,25,33,17,2,7,19,13,18,14}	function	4	{161,372}
374	\\x000000000800000002000000040000000700000013000000110000000d000000120000000e000000020002000100010000000000010000000001020304050102060407	\\xc140e53aeb16ba9b24c365ae9195ec84d7dddeb5c1b0869473aa3ab6358712d3	\\left(-\\cos\\left(\\theta\\right)\\right)\\hat{i}+\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{j}	{2,4,7,19,17,13,18,14}	function	2	{369,364}
375	\\x000000000a000000040000001900000021000000110000000200000007000000130000000d000000120000000e0000000200020000000000020001000100000001000000000102030400050603070005080309	\\x704eac5e0ff769cbf284d416844b0527a5a1217f45a24e2b05b725d604e49d83	\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(\\left(-\\cos\\left(\\theta\\right)\\right)\\hat{i}+\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{j}\\right)	{4,25,33,17,2,7,19,13,18,14}	function	4	{239,374}
376	\\x000000000a000000040000001900000021000000110000000200000007000000130000000d000000120000000e000000020002000000000002000100010000000100000000010203000102030400050603070005080309	\\x9ad20aeeb8029260edc99d9ef4acc79eb25d82d5b1ff543b5fe2b8f7bb4b552f	\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(\\left(-\\cos\\left(\\theta\\right)\\right)\\hat{i}+\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{j}\\right)\\right)	{4,25,33,17,2,7,19,13,18,14}	function	4	{239,375}
377	\\x000000000b00000004000000100000001900000021000000110000000200000007000000130000000d000000120000000e0000000200000002000000000002000100010000000100000000010002030400020304050006070408000609040a	\\xf7de721980b33d1c4c0d3e3da775ed077bcdfbce7c9bad6d1be23cfa419ac5b9	r\\left(\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(\\left(-\\cos\\left(\\theta\\right)\\right)\\hat{i}+\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{j}\\right)\\right)\\right)	{4,16,25,33,17,2,7,19,13,18,14}	function	4	{161,376}
378	\\x000000000400000004000000190000002100000011000000020002000000000000010203010203	\\x647a2711d74b1fb26be246ef792d33b77c37bf47784ed918ff19b1032b1aec41	\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\frac{\\partial}{\\partial t}\\left(\\theta\\right)	{4,25,33,17}	function	4	{239,239}
379	\\x000000000a000000040000001900000021000000110000000200000007000000130000000d000000120000000e000000020002000000000002000100010000000100000000000102030102030400050603070005080309	\\xef155cad80f5ae049870476fcc8f728dc1e24843484e972e3c0cfbd39a6b61ad	\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(\\left(-\\cos\\left(\\theta\\right)\\right)\\hat{i}+\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{j}\\right)	{4,25,33,17,2,7,19,13,18,14}	function	4	{378,374}
380	\\x000000000b00000004000000100000001900000021000000110000000200000007000000130000000d000000120000000e0000000200000002000000000002000100010000000100000000010000020304020304050006070408000609040a	\\x771ce1bd3a8d061baae06ee833299ad85d09140bbd6f80d1484f2ba38c7232ae	r\\left(\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\left(\\left(-\\cos\\left(\\theta\\right)\\right)\\hat{i}+\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{j}\\right)\\right)	{4,16,25,33,17,2,7,19,13,18,14}	function	4	{161,379}
381	\\x0000010004000000020000000600000019000000210000001100000002000200000000000001020304	\\x40aac8e26b5edcd3301e53fb9f6429121d7954702981b23980cb7c0c8a13f0a0	\\frac{\\partial}{\\partial t}\\left(\\theta\\right)^{2}	{6,25,33,17}	function	6	{239,38}
382	\\x000001000b0000000200000004000000060000001900000021000000110000000200000007000000130000000d000000120000000e0000000200020002000000000002000100010000000100000000010203040b050006070408000609040a	\\x0ff86c8c805c56327047553b0c15c22b7584ecae8355ff8091adef186e504610	\\frac{\\partial}{\\partial t}\\left(\\theta\\right)^{2}\\left(\\left(-\\cos\\left(\\theta\\right)\\right)\\hat{i}+\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{j}\\right)	{4,6,25,33,17,2,7,19,13,18,14}	function	4	{381,374}
383	\\x000001000c000000020000000400000010000000060000001900000021000000110000000200000007000000130000000d000000120000000e000000020000000200020000000000020001000100000001000000000100020304050c06000708050900070a050b	\\x42557f18b4472b8db7135408884767c3df411dc900aea4cdb5f80eabe1a1d846	r\\left(\\frac{\\partial}{\\partial t}\\left(\\theta\\right)^{2}\\left(\\left(-\\cos\\left(\\theta\\right)\\right)\\hat{i}+\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{j}\\right)\\right)	{4,16,6,25,33,17,2,7,19,13,18,14}	function	4	{161,382}
384	\\x000001000300010002000000090000001a0000000600000000000100020001020003	\\x4885dbd20a05b665879af2b119a2864fa7fcee40d5d85f7ff0b95062be2c01f0	\\left|{}_\\text{?}a^{2}\\right|	{9,26,6}	function	26	{39}
385	\\x00000100030001000200000009000000060000001a00000000000200010001020003	\\x6843a4f268c97df166589484691681a12289f09b4ca49d2c0975dea1bf83c975	\\left|{}_\\text{?}a\\right|^{2}	{9,6,26}	function	6	{259,38}
393	\\x000001000c00000002000000040000001a000000060000001900000021000000110000000200000007000000130000000d000000120000000e0000000200010002000200000000000200010001000000010000000001020304050c0106000708050900070a050b	\\x5177ae687404960921b54dd6e6906a5e49b30e6227f12540fec68e373c401593	\\left|\\frac{\\partial}{\\partial t}\\left(\\theta\\right)^{2}\\right|\\left|\\left(-\\cos\\left(\\theta\\right)\\right)\\hat{i}+\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{j}\\right|	{4,26,6,25,33,17,2,7,19,13,18,14}	function	4	{391,392}
394	\\x000001000d00000002000000040000001a00000010000000060000001900000021000000110000000200000007000000130000000d000000120000000e00000002000100000002000200000000000200010001000000010000000001020001030405060d0107000809060a00080b060c	\\x843ebca300ea59f6575263df4269a2e874a52712cba82a409355ef1e9c08f34f	\\left|r\\right|\\left(\\left|\\frac{\\partial}{\\partial t}\\left(\\theta\\right)^{2}\\right|\\left|\\left(-\\cos\\left(\\theta\\right)\\right)\\hat{i}+\\left(-\\sin\\left(\\theta\\right)\\right)\\hat{j}\\right|\\right)	{4,26,16,6,25,33,17,2,7,19,13,18,14}	function	4	{296,393}
395	\\x0000010004000000020000000600000007000000130000001100000002000100010000000001020304	\\xf05422844a5b35f06a47b49cb52719bd1bf49409b4e40fbccb0f1c35a7c280f5	\\left(-\\cos\\left(\\theta\\right)\\right)^{2}	{6,7,19,17}	function	6	{358,38}
396	\\x0000010004000000020000000600000007000000120000001100000002000100010000000001020304	\\xaddafa277568ac87db2cc57f5948c4a855e2db87c9605b7aafd3193fda83ad73	\\left(-\\sin\\left(\\theta\\right)\\right)^{2}	{6,7,18,17}	function	6	{244,38}
397	\\x0000010006000000020000000200000006000000070000001300000011000000120000000200020001000100000001000001020304060102050406	\\x3431b9b669a2967d1839efdd7ef06b292bae088388c65a0e05627430b3ee916c	\\left(-\\cos\\left(\\theta\\right)\\right)^{2}+\\left(-\\sin\\left(\\theta\\right)\\right)^{2}	{2,6,7,19,17,18}	function	2	{395,396}
398	\\x000001000700000002000000240000000200000006000000070000001300000011000000120000000100020002000100010000000100000102030405070203060507	\\x992c79aeb4f7baae12462a710e823e71a19c6ca07f6ae86c39834a4c490a3d05	\\sqrt{\\left(-\\cos\\left(\\theta\\right)\\right)^{2}+\\left(-\\sin\\left(\\theta\\right)\\right)^{2}}	{36,2,6,7,19,17,18}	function	36	{397}
399	\\x000001000b00000002000000040000001a000000060000001900000021000000110000002400000002000000070000001300000012000000020001000200020000000000010002000100010001000001020304050b0607020809050b02080a050b	\\xdf7f81331e4dbdc2add4632fe234609530bf63a81714a0b69184f89d96951a35	\\left|\\frac{\\partial}{\\partial t}\\left(\\theta\\right)^{2}\\right|\\sqrt{\\left(-\\cos\\left(\\theta\\right)\\right)^{2}+\\left(-\\sin\\left(\\theta\\right)\\right)^{2}}	{4,26,6,25,33,17,36,2,7,19,18}	function	4	{391,398}
400	\\x000001000c00000002000000040000001a000000100000000600000019000000210000001100000024000000020000000700000013000000120000000200010000000200020000000000010002000100010001000001020001030405060c070803090a060c03090b060c	\\x85ade0d4cfa143e5ff6768b2e6ace4d16d1a6cb09d0917101f1e11fe94bc3b8c	\\left|r\\right|\\left(\\left|\\frac{\\partial}{\\partial t}\\left(\\theta\\right)^{2}\\right|\\sqrt{\\left(-\\cos\\left(\\theta\\right)\\right)^{2}+\\left(-\\sin\\left(\\theta\\right)\\right)^{2}}\\right)	{4,26,16,6,25,33,17,36,2,7,19,18}	function	4	{296,399}
401	\\x00000100030000000200000006000000120000001100000002000100000000010203	\\x0e2dee4b316209234da46524dadccb2e61cdf8c86b3186b2acd954189ba08930	\\sin\\left(\\theta\\right)^{2}	{6,18,17}	function	6	{167,38}
402	\\x00000100060000000200000002000000060000000700000013000000110000001200000002000200010001000000010000010203040601050406	\\x9b4cb5dee664ba7a5866b38247243d687756a5e53e7f5aa4cde8558376f1bcde	\\left(-\\cos\\left(\\theta\\right)\\right)^{2}+\\sin\\left(\\theta\\right)^{2}	{2,6,7,19,17,18}	function	2	{395,401}
403	\\x0000010007000000020000002400000002000000060000000700000013000000110000001200000001000200020001000100000001000001020304050702060507	\\x538a7d7fdfaa0dc5a4aeb88906d73bdf64b62b6c5b09160e1cad495fffe75b17	\\sqrt{\\left(-\\cos\\left(\\theta\\right)\\right)^{2}+\\sin\\left(\\theta\\right)^{2}}	{36,2,6,7,19,17,18}	function	36	{402}
404	\\x000001000b00000002000000040000001a000000060000001900000021000000110000002400000002000000070000001300000012000000020001000200020000000000010002000100010001000001020304050b0607020809050b020a050b	\\x09227b3e2d067fa48cbe61e73ae45602840c0b6bc5fd307ce02fc8a54cef59aa	\\left|\\frac{\\partial}{\\partial t}\\left(\\theta\\right)^{2}\\right|\\sqrt{\\left(-\\cos\\left(\\theta\\right)\\right)^{2}+\\sin\\left(\\theta\\right)^{2}}	{4,26,6,25,33,17,36,2,7,19,18}	function	4	{391,403}
405	\\x000001000c00000002000000040000001a000000100000000600000019000000210000001100000024000000020000000700000013000000120000000200010000000200020000000000010002000100010001000001020001030405060c070803090a060c030b060c	\\x8521bc99eef2eeb34e55fb00f5fd3f497d57853d304461e776dee09f05edd9f7	\\left|r\\right|\\left(\\left|\\frac{\\partial}{\\partial t}\\left(\\theta\\right)^{2}\\right|\\sqrt{\\left(-\\cos\\left(\\theta\\right)\\right)^{2}+\\sin\\left(\\theta\\right)^{2}}\\right)	{4,26,16,6,25,33,17,36,2,7,19,18}	function	4	{296,404}
406	\\x00000100030000000200000006000000130000001100000002000100000000010203	\\xc8cad15b5bab13b38b5268af16791c39fa104f18d5b9c9376d642a5f2d66c3f8	\\cos\\left(\\theta\\right)^{2}	{6,19,17}	function	6	{163,38}
407	\\x000001000500000002000000020000000600000013000000110000001200000002000200010000000100000102030501040305	\\xa0927faa3116d28fb894df923d3d1f7936b514b2c2089a898314fbda897bdee3	\\cos\\left(\\theta\\right)^{2}+\\sin\\left(\\theta\\right)^{2}	{2,6,19,17,18}	function	2	{406,401}
408	\\x00000100060000000200000024000000020000000600000013000000110000001200000001000200020001000000010000010203040602050406	\\xeba9525126760dae97361a9310abc97797890595ea60e55b4d94db7a0e9fc2fb	\\sqrt{\\cos\\left(\\theta\\right)^{2}+\\sin\\left(\\theta\\right)^{2}}	{36,2,6,19,17,18}	function	36	{407}
409	\\x000001000a00000002000000040000001a000000060000001900000021000000110000002400000002000000130000001200000002000100020002000000000001000200010001000001020304050a06070208050a0209050a	\\xf7ef260dfb7eda55da6569bb8e446ebfc0321c48d411b6f84cd2f36dd93f92f1	\\left|\\frac{\\partial}{\\partial t}\\left(\\theta\\right)^{2}\\right|\\sqrt{\\cos\\left(\\theta\\right)^{2}+\\sin\\left(\\theta\\right)^{2}}	{4,26,6,25,33,17,36,2,19,18}	function	4	{391,408}
410	\\x000001000b00000002000000040000001a000000100000000600000019000000210000001100000024000000020000001300000012000000020001000000020002000000000001000200010001000001020001030405060b07080309060b030a060b	\\x687e7d0dce161c0b914eac5104bc20a807b4df5c791cf5e1218c8cf54c258ee1	\\left|r\\right|\\left(\\left|\\frac{\\partial}{\\partial t}\\left(\\theta\\right)^{2}\\right|\\sqrt{\\cos\\left(\\theta\\right)^{2}+\\sin\\left(\\theta\\right)^{2}}\\right)	{4,26,16,6,25,33,17,36,2,19,18}	function	4	{296,409}
411	\\x000001000500000002000000020000000600000012000000110000001300000002000200010000000100000102030501040305	\\x4d0031f43e137c85f5e9b60033d69aea54164ab068d693462b3ad404f4d7685d	\\sin\\left(\\theta\\right)^{2}+\\cos\\left(\\theta\\right)^{2}	{2,6,18,17,19}	function	2	{401,406}
412	\\x00000100060000000200000024000000020000000600000012000000110000001300000001000200020001000000010000010203040602050406	\\xb592691722065b17c88c6c3ec1435c9e0ac54a5a5b13197809e3e43f7fe48e09	\\sqrt{\\sin\\left(\\theta\\right)^{2}+\\cos\\left(\\theta\\right)^{2}}	{36,2,6,18,17,19}	function	36	{411}
413	\\x000001000a00000002000000040000001a000000060000001900000021000000110000002400000002000000120000001300000002000100020002000000000001000200010001000001020304050a06070208050a0209050a	\\x24986fb90a90ca389bb358d2f3d79bbc816673b55b99733dad26b1a888c08bc9	\\left|\\frac{\\partial}{\\partial t}\\left(\\theta\\right)^{2}\\right|\\sqrt{\\sin\\left(\\theta\\right)^{2}+\\cos\\left(\\theta\\right)^{2}}	{4,26,6,25,33,17,36,2,18,19}	function	4	{391,412}
414	\\x000001000b00000002000000040000001a000000100000000600000019000000210000001100000024000000020000001200000013000000020001000000020002000000000001000200010001000001020001030405060b07080309060b030a060b	\\x6c58905fa5eea5c8b411ed1f066cebc768a91356b022e52fd22985c7bb349268	\\left|r\\right|\\left(\\left|\\frac{\\partial}{\\partial t}\\left(\\theta\\right)^{2}\\right|\\sqrt{\\sin\\left(\\theta\\right)^{2}+\\cos\\left(\\theta\\right)^{2}}\\right)	{4,26,16,6,25,33,17,36,2,18,19}	function	4	{296,413}
415	\\x00000200070000000200000001000000040000001a00000006000000190000002100000011000000240000000200010002000200000000000100000102030405070608	\\xba5a6195ad9f88d5758e5207985bf3a9dd97acd8cf67685007d57ca1a314ca16	\\left|\\frac{\\partial}{\\partial t}\\left(\\theta\\right)^{2}\\right|\\sqrt{1}	{4,26,6,25,33,17,36}	function	4	{391,278}
416	\\x00000200080000000200000001000000040000001a00000010000000060000001900000021000000110000002400000002000100000002000200000000000100000102000103040506080709	\\x8cacc90cc218f9d860c61bd1e937863a8106345d616a082616c17d1dc2122789	\\left|r\\right|\\left(\\left|\\frac{\\partial}{\\partial t}\\left(\\theta\\right)^{2}\\right|\\sqrt{1}\\right)	{4,26,16,6,25,33,17,36}	function	4	{296,415}
417	\\x00000200060000000200000001000000040000001a000000060000001900000021000000110000000200010002000200000000000001020304050607	\\x27b87b66fe3459de4fec8801b3d515054f910aa293c787a0807d1adbdfaa83aa	\\left|\\frac{\\partial}{\\partial t}\\left(\\theta\\right)^{2}\\right|1	{4,26,6,25,33,17}	function	4	{391,13}
418	\\x00000200070000000200000001000000040000001a000000100000000600000019000000210000001100000002000100000002000200000000000001020001030405060708	\\x44bd81cc8377e5effca13a557b38183dd66188b58a653ad0e9efcfde961bcfea	\\left|r\\right|\\left(\\left|\\frac{\\partial}{\\partial t}\\left(\\theta\\right)^{2}\\right|1\\right)	{4,26,16,6,25,33,17}	function	4	{296,417}
419	\\x00000200060000000100000002000000040000001a000000060000001900000021000000110000000200010002000200000000000006010203040507	\\xfc4c9dc50cc9331c8bbcf51d371f536cf120e879895e592d16fca48103243cf0	1\\left|\\frac{\\partial}{\\partial t}\\left(\\theta\\right)^{2}\\right|	{4,26,6,25,33,17}	function	4	{13,391}
420	\\x00000200070000000100000002000000040000001a000000100000000600000019000000210000001100000002000100000002000200000000000001020007010304050608	\\x941c61184fb361df4a4b4e2982649a62d097b0e4e4ca14626876f53c000129cb	\\left|r\\right|\\left(1\\left|\\frac{\\partial}{\\partial t}\\left(\\theta\\right)^{2}\\right|\\right)	{4,26,16,6,25,33,17}	function	4	{296,419}
421	\\x000001000700000002000000040000001a00000010000000060000001900000021000000110000000200010000000200020000000000000102010304050607	\\x207cd8cde9bac95ec60fece27d29d4f14505d3a23146598321f82bf83ee4d1be	\\left|r\\right|\\left|\\frac{\\partial}{\\partial t}\\left(\\theta\\right)^{2}\\right|	{4,26,16,6,25,33,17}	function	4	{296,391}
422	\\x000001000500000002000000060000001a00000019000000210000001100000002000100020000000000000102030405	\\xd4378367122ec0ccfe160165f587a57a0f076c3e705b119cd7eb3f61843af58c	\\left|\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\right|^{2}	{6,26,25,33,17}	function	6	{297,38}
423	\\x000001000700000002000000040000001a00000010000000060000001900000021000000110000000200010000000200020000000000000102030104050607	\\xe100b3c0f84192c2aa275c38ffd792443944eff259c65b3e76a0b6fcbdc3ce24	\\left|r\\right|\\left|\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\right|^{2}	{4,26,16,6,25,33,17}	function	4	{296,422}
424	\\x000001000300000002000000060000001f0000002200000002000100000000010203	\\x029954ca9383cf3cad844b2379bb7d76252e9d7e9082febffefe958c3098b3a3	\\text{v}_{c}^{2}	{6,31,34}	function	6	{288,38}
425	\\x00000100060000000200000005000000060000001f000000220000001a0000001000000002000200010000000100000000010203060405	\\x2cc9514081f7fecdd86f7ae291283f5d5d0ee348cd3023e2fcc21ebab2ada64c	\\frac{~\\text{v}_{c}^{2}~}{~\\left|r\\right|~}	{5,6,31,34,26,16}	function	5	{424,296}
426	\\x00000100070000000200000006000000040000001a000000100000001900000021000000110000000200020001000000020000000000000102030204050607	\\xb720b813375309a68254db879efa60ea3b1a51bf479305ccda29997e7ebf6c86	\\left(\\left|r\\right|\\left|\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\right|\\right)^{2}	{6,4,26,16,25,33,17}	function	6	{298,38}
427	\\x0000010008000000020000000500000006000000040000001a0000001000000019000000210000001100000002000200020001000000020000000000000102030403050607080304	\\x85a3fd6128be0fc822c33816da9c9e1e3adeb4cde84811eccee1bf624451fbdc	\\frac{~\\left(\\left|r\\right|\\left|\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\right|\\right)^{2}~}{~\\left|r\\right|~}	{5,6,4,26,16,25,33,17}	function	5	{426,296}
428	\\x0000000006000000040000001a00000010000000190000002100000011000000020001000000020000000000000001020103040500010201030405	\\x96a4560f775e9aeaba1232552f21bfb434d227698f22ce489508a71eeb5cd93b	\\left|r\\right|\\left|\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\right|\\left(\\left|r\\right|\\left|\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\right|\\right)	{4,26,16,25,33,17}	function	4	{298,298}
429	\\x000000000700000005000000040000001a000000100000001900000021000000110000000200020001000000020000000000000101020302040506010203020405060203	\\xa0e80889b2a69908d7965ac52f85cfd34da28ac130a18b14438755746d001cea	\\frac{~\\left|r\\right|\\left|\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\right|\\left(\\left|r\\right|\\left|\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\right|\\right)~}{~\\left|r\\right|~}	{5,4,26,16,25,33,17}	function	5	{428,296}
430	\\x0000000006000000040000001a00000010000000190000002100000011000000020001000000020000000000000001020103040501030405	\\x889acc44a3e9f2efcb37f6c2b63802eaba3140f45fb7e2204b00e1a0157d814c	\\left|r\\right|\\left|\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\right|\\left|\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\right|	{4,26,16,25,33,17}	function	4	{298,297}
431	\\x0000000006000000040000001a00000010000000190000002100000011000000020001000000020000000000000000010201030405010304050102	\\xb7b5cf3d57bff62d143e2135f6912fa43acf9b20bb78a995569a5a57a1e212f3	\\left|r\\right|\\left|\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\right|\\left|\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\right|\\left|r\\right|	{4,26,16,25,33,17}	function	4	{430,296}
432	\\x000000000700000005000000040000001a000000100000001900000021000000110000000200020001000000020000000000000101010203020405060204050602030203	\\xf5a81563a761bfecd5b8a7eb1d8cd09430fe3950028e3186e9c22ced4f2a5990	\\frac{~\\left|r\\right|\\left|\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\right|\\left|\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\right|\\left|r\\right|~}{~\\left|r\\right|~}	{5,4,26,16,25,33,17}	function	5	{431,296}
433	\\x0000000005000000040000001a00000019000000210000001100000002000100020000000000000102030401020304	\\x163f9d0ebaee2a7f72e4743c90e32000c7a1e03c0a36da619bc114bab11348eb	\\left|\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\right|\\left|\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\right|	{4,26,25,33,17}	function	4	{297,297}
434	\\x0000000006000000040000001a00000010000000190000002100000011000000020001000000020000000000000102000103040501030405	\\x57d5f7101d838d4b6120cda5310ae47e9ce46f8eb8120bd51ad29c27e79c9119	\\left|r\\right|\\left(\\left|\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\right|\\left|\\frac{\\partial}{\\partial t}\\left(\\theta\\right)\\right|\\right)	{4,26,16,25,33,17}	function	4	{296,433}
\.


--
-- Name: expression_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('expression_id_seq', 434, true);


--
-- Data for Name: function; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY function (id, subject_id, descriptor_id, generic, rearrangeable, argument_count, keyword, keyword_type, latex_template) FROM stdin;
1	1	6	f	f	2	\N	\N	$0=$1
2	1	7	f	t	2	\N	\N	$0+$1
3	1	8	f	f	2	\N	\N	$0-$1
4	1	9	f	t	2	\N	\N	$0$1
5	1	10	f	f	2	frac	latex	\\frac{~$0~}{~$1~}
6	1	11	f	f	2	\N	\N	$0^{$1}
8	2	13	f	f	1	\N	\N	$0!
9	1	\N	t	f	0	a	symbol	\N
10	1	\N	t	f	0	b	symbol	\N
11	1	\N	t	f	0	c	symbol	\N
12	1	\N	t	f	0	n	symbol	\N
13	3	\N	f	f	0	e1	symbol	\\hat{i}
14	3	\N	f	f	0	e2	symbol	\\hat{j}
15	3	\N	f	f	0	e3	symbol	\\hat{k}
16	4	14	f	f	0	r	symbol	\N
17	4	15	f	f	0	theta	latex	\\theta
20	5	\N	t	f	0	x	symbol	\N
21	5	\N	t	f	0	y	symbol	\N
22	5	\N	t	f	1	f	abbreviation	\N
23	5	18	f	f	1	d	symbol	\\Delta$0
24	5	19	f	f	3	lim	latex	\\lim_{$0\\to$1}$2
26	1	22	f	f	1	abs	abbreviation	\\left|$0\\right|
27	1	23	t	f	0	body	word	\N
30	6	26	f	f	1	accel	abbreviation	\\vec{a_{$0}}
31	6	27	f	f	1	speed	word	\\text{v}_{$0}
29	6	25	f	f	1	vel	abbreviation	\\vec{v_{$0}}
32	6	28	f	f	1	accelm	abbreviation	\\text{a}_{$0}
33	6	29	f	f	0	time	word	t
28	6	24	f	f	1	pos	abbreviation	\\vec{p_{$0}}
35	1	32	f	f	1	uvec	abbreviation	e_{$0}
25	5	20	f	f	2	diff	abbreviation	\\frac{\\partial}{\\partial$0}\\left($1\\right)
34	1	31	f	f	0	cbody	abbreviation	c
7	1	12	f	f	1	\N	\N	\\left(-$0\\right)
36	1	33	f	f	1	sqrt	abbreviation	\\sqrt{$0}
18	4	16	f	f	1	sin	latex	\\sin\\left($0\\right)
19	4	17	f	f	1	cos	latex	\\cos\\left($0\\right)
37	4	34	f	f	0	omega	word	\\omega
\.


--
-- Name: function_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('function_id_seq', 37, true);


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
6	6	4	rtl	infix	^	^{$0}
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
1	1	4
2	5	7
3	8	11
4	12	14
5	15	17
6	18	21
7	22	32
8	33	38
9	39	41
10	42	44
11	45	59
12	60	62
13	63	67
14	68	72
15	73	77
16	78	90
17	91	97
18	98	102
19	103	110
20	111	113
21	114	137
22	138	151
23	152	159
\.


--
-- Name: proof_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('proof_id_seq', 23, true);


--
-- Data for Name: rule; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY rule (id, proof_id, left_expression_id, right_expression_id, left_array_data, right_array_data) FROM stdin;
1	\N	4	5	{576332304,4,2,2,11,198119638,3,9,251955836,4,7,1,3,358130610,3,10}	{725194104,4,3,2,6,198119638,3,9,358130610,3,10}
2	\N	9	11	{755105816,4,2,2,22,507440212,4,4,2,6,198119638,3,9,358130610,3,10,792166020,4,4,2,6,198119638,3,9,971369676,3,11}	{528846700,4,4,2,14,198119638,3,9,416255908,4,2,2,6,358130610,3,10,971369676,3,11}
3	\N	12	15	{304733658,4,7,1,3,198119638,3,9}	{691054416,4,4,2,11,205680372,4,7,1,3,5,1,1,198119638,3,9}
4	\N	16	1	{510478350,4,6,2,6,198119638,3,9,5,1,1}	{198119638,3,9}
5	\N	19	20	{71005026,4,4,2,22,695795496,4,6,2,6,198119638,3,9,358130610,3,10,622151856,4,6,2,6,198119638,3,9,971369676,3,11}	{491848602,4,6,2,14,198119638,3,9,416255908,4,2,2,6,358130610,3,10,971369676,3,11}
6	\N	23	30	{518681770,4,25,2,11,801036408,3,20,647388986,5,22,1,3,801036408,3,20}	{259565444,4,24,3,58,10394894,4,23,1,3,801036408,3,20,1,1,0,1070033562,4,5,2,42,609969986,4,3,2,29,177948780,5,22,1,16,241161002,4,2,2,11,801036408,3,20,10394894,4,23,1,3,801036408,3,20,647388986,5,22,1,3,801036408,3,20,10394894,4,23,1,3,801036408,3,20}
7	\N	32	34	{696138698,4,1,2,14,767099948,4,2,2,6,198119638,3,9,358130610,3,10,971369676,3,11}	{136942074,4,1,2,14,198119638,3,9,270562032,4,3,2,6,971369676,3,11,358130610,3,10}
8	2	32	43	{696138698,4,1,2,14,767099948,4,2,2,6,198119638,3,9,358130610,3,10,971369676,3,11}	{473198860,4,1,2,14,358130610,3,10,328348816,4,3,2,6,971369676,3,11,198119638,3,9}
9	1	35	39	{736185540,4,4,2,6,198119638,3,9,198119638,3,9}	{1068305054,4,6,2,6,198119638,3,9,9,1,2}
10	3	46	11	{16837742,4,2,2,22,646841570,4,4,2,6,358130610,3,10,198119638,3,9,448454688,4,4,2,6,971369676,3,11,198119638,3,9}	{528846700,4,4,2,14,198119638,3,9,416255908,4,2,2,6,358130610,3,10,971369676,3,11}
11	\N	1	48	{198119638,3,9}	{955462542,4,4,2,6,5,1,1,198119638,3,9}
12	4	9	49	{755105816,4,2,2,22,507440212,4,4,2,6,198119638,3,9,358130610,3,10,792166020,4,4,2,6,198119638,3,9,971369676,3,11}	{369792538,4,4,2,14,416255908,4,2,2,6,358130610,3,10,971369676,3,11,198119638,3,9}
13	5	46	49	{16837742,4,2,2,22,646841570,4,4,2,6,358130610,3,10,198119638,3,9,448454688,4,4,2,6,971369676,3,11,198119638,3,9}	{369792538,4,4,2,14,416255908,4,2,2,6,358130610,3,10,971369676,3,11,198119638,3,9}
14	6	50	53	{798769316,4,2,2,6,198119638,3,9,198119638,3,9}	{87245626,4,4,2,6,9,1,2,198119638,3,9}
15	7	54	79	{618267248,4,6,2,14,767099948,4,2,2,6,198119638,3,9,358130610,3,10,9,1,2}	{337764186,4,2,2,46,30927278,4,2,2,30,1068305054,4,6,2,6,198119638,3,9,9,1,2,947390454,4,4,2,14,87245626,4,4,2,6,9,1,2,198119638,3,9,358130610,3,10,1061973566,4,6,2,6,358130610,3,10,9,1,2}
16	\N	80	25	{99079404,4,4,2,6,1,1,0,198119638,3,9}	{1,1,0}
17	8	81	25	{631223668,4,3,2,6,198119638,3,9,198119638,3,9}	{1,1,0}
18	\N	87	1	{1020690818,4,2,2,6,198119638,3,9,1,1,0}	{198119638,3,9}
19	9	88	1	{670663792,4,2,2,6,1,1,0,198119638,3,9}	{198119638,3,9}
20	\N	89	1	{701243338,4,5,2,14,507440212,4,4,2,6,198119638,3,9,358130610,3,10,358130610,3,10}	{198119638,3,9}
21	10	90	1	{529660182,4,5,2,14,646841570,4,4,2,6,358130610,3,10,198119638,3,9,358130610,3,10}	{198119638,3,9}
22	\N	93	96	{566635098,4,24,3,17,198119638,3,9,358130610,3,10,237948570,4,2,2,6,801036408,3,20,208212430,3,21}	{671542814,4,2,2,28,480104780,4,24,3,9,198119638,3,9,358130610,3,10,801036408,3,20,270136248,4,24,3,9,198119638,3,9,358130610,3,10,208212430,3,21}
23	\N	97	25	{870341676,4,24,3,9,198119638,3,9,1,1,0,198119638,3,9}	{1,1,0}
24	\N	98	7	{838931994,4,24,3,9,198119638,3,9,358130610,3,10,971369676,3,11}	{971369676,3,11}
25	\N	149	152	{744767124,4,29,1,3,1063352268,3,27}	{273211608,4,25,2,11,935094976,2,33,758628994,4,28,1,3,1063352268,3,27}
26	\N	153	154	{159151750,4,30,1,3,1063352268,3,27}	{17029168,4,25,2,11,935094976,2,33,744767124,4,29,1,3,1063352268,3,27}
27	\N	155	156	{713209448,4,31,1,3,1063352268,3,27}	{739632324,4,26,1,8,744767124,4,29,1,3,1063352268,3,27}
28	\N	157	158	{863026784,4,32,1,3,1063352268,3,27}	{686827136,4,26,1,8,159151750,4,30,1,3,1063352268,3,27}
29	\N	160	171	{645554198,4,28,1,3,450801924,2,34}	{738895534,4,2,2,48,961458196,4,4,2,19,465579068,4,4,2,11,228890302,2,16,970530850,4,19,1,3,945777714,2,17,665602766,2,13,488843316,4,4,2,19,125276652,4,4,2,11,228890302,2,16,578967140,4,18,1,3,945777714,2,17,168365960,2,14}
30	\N	172	175	{769626246,4,25,2,14,198119638,3,9,416255908,4,2,2,6,358130610,3,10,971369676,3,11}	{405734452,4,2,2,22,232795360,4,25,2,6,198119638,3,9,358130610,3,10,520828540,4,25,2,6,198119638,3,9,971369676,3,11}
32	\N	176	186	{750417876,4,25,2,14,801036408,3,20,507440212,4,4,2,6,198119638,3,9,358130610,3,10}	{899407860,4,2,2,38,581494678,4,4,2,14,269928892,4,25,2,6,801036408,3,20,198119638,3,9,358130610,3,10,876527268,4,4,2,14,198119638,3,9,1065444660,4,25,2,6,801036408,3,20,358130610,3,10}
35	\N	187	25	{493321098,4,25,2,6,801036408,3,20,665602766,2,13}	{1,1,0}
36	\N	188	25	{143116750,4,25,2,6,801036408,3,20,168365960,2,14}	{1,1,0}
37	12	189	25	{736551474,4,4,2,6,198119638,3,9,1,1,0}	{1,1,0}
38	13	191	192	{310676158,4,25,2,14,801036408,3,20,352139162,4,4,2,6,198119638,3,9,665602766,2,13}	{125243106,4,4,2,14,269928892,4,25,2,6,801036408,3,20,198119638,3,9,665602766,2,13}
39	14	198	199	{513968298,4,25,2,14,801036408,3,20,765581604,4,4,2,6,198119638,3,9,168365960,2,14}	{76814598,4,4,2,14,269928892,4,25,2,6,801036408,3,20,198119638,3,9,168365960,2,14}
40	\N	204	25	{339187356,4,25,2,6,935094976,2,33,228890302,2,16}	{1,1,0}
41	15	206	208	{239782014,4,25,2,14,935094976,2,33,231481724,4,4,2,6,228890302,2,16,198119638,3,9}	{893693330,4,4,2,14,228890302,2,16,35900520,4,25,2,6,935094976,2,33,198119638,3,9}
42	\N	213	215	{477655354,4,25,2,11,198119638,3,9,395481382,4,18,1,3,358130610,3,10}	{583985556,4,4,2,19,232795360,4,25,2,6,198119638,3,9,358130610,3,10,446175624,4,19,1,3,358130610,3,10}
43	\N	216	218	{344052300,4,25,2,11,198119638,3,9,446175624,4,19,1,3,358130610,3,10}	{345837958,4,4,2,24,232795360,4,25,2,6,198119638,3,9,358130610,3,10,505860694,4,7,1,8,395481382,4,18,1,3,358130610,3,10}
44	16	219	257	{510972446,4,29,1,3,450801924,2,34}	{120679584,4,4,2,61,512348928,4,4,2,14,228890302,2,16,206205466,4,25,2,6,935094976,2,33,945777714,2,17,993273836,4,2,2,37,991588944,4,4,2,16,469068560,4,7,1,8,578967140,4,18,1,3,945777714,2,17,665602766,2,13,463592604,4,4,2,11,970530850,4,19,1,3,945777714,2,17,168365960,2,14}
45	\N	258	261	{1019053478,4,26,1,11,507440212,4,4,2,6,198119638,3,9,358130610,3,10}	{166912282,4,4,2,16,1048477056,4,26,1,3,198119638,3,9,491491682,4,26,1,3,358130610,3,10}
46	17	262	39	{667767012,4,6,2,11,304733658,4,7,1,3,198119638,3,9,9,1,2}	{1068305054,4,6,2,6,198119638,3,9,9,1,2}
47	\N	259	267	{1048477056,4,26,1,3,198119638,3,9}	{299594740,4,36,1,11,1068305054,4,6,2,6,198119638,3,9,9,1,2}
48	\N	270	272	{515231886,4,26,1,27,88350546,4,2,2,22,352139162,4,4,2,6,198119638,3,9,665602766,2,13,1030378374,4,4,2,6,358130610,3,10,168365960,2,14}	{1035489980,4,36,1,27,688443628,4,2,2,22,1068305054,4,6,2,6,198119638,3,9,9,1,2,1061973566,4,6,2,6,358130610,3,10,9,1,2}
49	\N	277	13	{603105228,4,2,2,32,1029560584,4,6,2,11,893746618,4,18,1,3,198119638,3,9,9,1,2,226711592,4,6,2,11,881460714,4,19,1,3,198119638,3,9,9,1,2}	{5,1,1}
50	\N	278	13	{435143854,4,36,1,3,5,1,1}	{5,1,1}
51	18	283	13	{830876612,4,26,1,42,573396794,4,2,2,37,317179742,4,4,2,16,651202052,4,7,1,8,893746618,4,18,1,3,198119638,3,9,665602766,2,13,988033300,4,4,2,11,881460714,4,19,1,3,198119638,3,9,168365960,2,14}	{5,1,1}
52	19	288	298	{145795946,4,31,1,3,450801924,2,34}	{236953196,4,4,2,24,712080540,4,26,1,3,228890302,2,16,355182768,4,26,1,11,206205466,4,25,2,6,935094976,2,33,945777714,2,17}
53	\N	239	299	{206205466,4,25,2,6,935094976,2,33,945777714,2,17}	{78578852,2,37}
54	\N	300	25	{527438386,4,25,2,6,935094976,2,33,78578852,2,37}	{1,1,0}
55	20	301	25	{339181656,4,25,2,14,935094976,2,33,206205466,4,25,2,6,935094976,2,33,945777714,2,17}	{1,1,0}
56	\N	302	303	{377115076,4,25,2,11,801036408,3,20,304733658,4,7,1,3,198119638,3,9}	{391050022,4,7,1,11,269928892,4,25,2,6,801036408,3,20,198119638,3,9}
57	\N	304	305	{698545520,4,7,1,11,507440212,4,4,2,6,198119638,3,9,358130610,3,10}	{11299142,4,4,2,11,198119638,3,9,251955836,4,7,1,3,358130610,3,10}
58	21	306	383	{827783816,4,30,1,3,450801924,2,34}	{1038695120,4,4,2,74,228890302,2,16,920679232,4,4,2,66,982468990,4,6,2,14,206205466,4,25,2,6,935094976,2,33,945777714,2,17,9,1,2,212010040,4,2,2,42,508259202,4,4,2,16,682095912,4,7,1,8,970530850,4,19,1,3,945777714,2,17,665602766,2,13,198641494,4,4,2,16,469068560,4,7,1,8,578967140,4,18,1,3,945777714,2,17,168365960,2,14}
59	\N	384	385	{799491512,4,26,1,11,1068305054,4,6,2,6,198119638,3,9,9,1,2}	{589039774,4,6,2,11,1048477056,4,26,1,3,198119638,3,9,9,1,2}
60	22	386	423	{352208300,4,32,1,3,450801924,2,34}	{173453168,4,4,2,32,712080540,4,26,1,3,228890302,2,16,1070126550,4,6,2,19,355182768,4,26,1,11,206205466,4,25,2,6,935094976,2,33,945777714,2,17,9,1,2}
\.


--
-- Name: rule_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('rule_id_seq', 60, true);


--
-- Data for Name: step; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY step (id, previous_id, expression_id, "position", step_type, proof_id, rule_id, rearrange) FROM stdin;
1	\N	35	0	set	\N	\N	\N
2	1	36	2	rule_invert	\N	4	\N
3	2	37	1	rule_invert	\N	4	\N
4	3	39	0	rule_normal	\N	5	\N
5	\N	32	0	set	\N	\N	\N
6	5	41	1	rearrange	\N	\N	{1,0}
7	6	43	0	rule_normal	\N	7	\N
8	\N	46	0	set	\N	\N	\N
9	8	47	4	rearrange	\N	\N	{1,0}
10	9	9	1	rearrange	\N	\N	{1,0}
11	10	11	0	rule_normal	\N	2	\N
12	\N	9	0	set	\N	\N	\N
13	12	11	0	rule_normal	\N	2	\N
14	13	49	0	rearrange	\N	\N	{1,0}
15	\N	46	0	set	\N	\N	\N
16	15	11	0	rule_normal	\N	10	\N
17	16	49	0	rearrange	\N	\N	{1,0}
18	\N	50	0	set	\N	\N	\N
19	18	51	2	rule_normal	\N	11	\N
20	19	52	1	rule_normal	\N	11	\N
21	20	53	0	rule_normal	\N	13	\N
22	\N	54	0	set	\N	\N	\N
23	22	55	0	rule_invert	\N	9	\N
24	23	58	0	rule_invert	\N	10	\N
25	24	61	6	rule_invert	\N	2	\N
26	25	63	1	rule_invert	\N	2	\N
27	26	66	0	rearrange	\N	\N	{0,1,2,-1,-1,3}
28	27	69	9	rearrange	\N	\N	{1,0}
29	28	71	12	rule_normal	\N	9	\N
30	29	74	5	rule_normal	\N	14	\N
31	30	76	2	rule_normal	\N	9	\N
32	31	79	5	rearrange	\N	\N	{0,1,-1,2}
33	\N	81	0	set	\N	\N	\N
34	33	82	0	rule_invert	\N	1	\N
35	34	85	2	rule_normal	\N	3	\N
36	35	86	1	rule_normal	\N	11	\N
37	36	80	0	rule_normal	\N	13	\N
38	37	25	0	rule_normal	\N	16	\N
39	\N	88	0	set	\N	\N	\N
40	39	87	0	rearrange	\N	\N	{1,0}
41	40	1	0	rule_normal	\N	18	\N
42	\N	90	0	set	\N	\N	\N
43	42	89	1	rearrange	\N	\N	{1,0}
44	43	1	0	rule_normal	\N	20	\N
45	\N	100	0	set	\N	\N	\N
46	45	104	0	rule_normal	\N	6	\N
47	46	112	6	rule_normal	\N	15	\N
48	47	116	5	rule_invert	\N	1	\N
49	48	121	5	rearrange	\N	\N	{0,3,-1,1,-1,2}
50	49	125	21	rule_invert	\N	9	\N
51	50	130	7	rule_normal	\N	1	\N
52	51	134	7	rule_normal	\N	17	\N
53	52	137	6	rule_normal	\N	19	\N
54	53	141	5	rule_normal	\N	10	\N
55	54	142	4	rule_normal	\N	21	\N
56	55	145	0	rule_normal	\N	22	\N
57	56	146	8	rule_normal	\N	23	\N
58	57	147	1	rule_normal	\N	24	\N
59	58	105	0	rule_normal	\N	18	\N
60	\N	189	0	set	\N	\N	\N
61	60	80	0	rearrange	\N	\N	{1,0}
62	61	25	0	rule_normal	\N	16	\N
63	\N	191	0	set	\N	\N	\N
64	63	194	0	rule_normal	\N	32	\N
65	64	195	8	rule_normal	\N	35	\N
66	65	196	6	rule_normal	\N	37	\N
67	66	192	0	rule_normal	\N	18	\N
68	\N	198	0	set	\N	\N	\N
69	68	201	0	rule_normal	\N	32	\N
70	69	202	8	rule_normal	\N	36	\N
71	70	203	6	rule_normal	\N	37	\N
72	71	199	0	rule_normal	\N	18	\N
73	\N	206	0	set	\N	\N	\N
74	73	209	0	rule_normal	\N	32	\N
75	74	210	2	rule_normal	\N	40	\N
76	75	211	1	rule_normal	\N	16	\N
77	76	208	0	rule_normal	\N	19	\N
78	\N	219	0	set	\N	\N	\N
79	78	220	0	rule_normal	\N	25	\N
80	79	221	2	rule_normal	\N	29	\N
81	80	224	0	rule_normal	\N	30	\N
82	81	227	9	rule_normal	\N	39	\N
83	82	230	1	rule_normal	\N	38	\N
84	83	234	10	rule_normal	\N	41	\N
85	84	238	2	rule_normal	\N	41	\N
86	85	243	12	rule_normal	\N	42	\N
87	86	248	4	rule_normal	\N	43	\N
88	87	252	12	rearrange	\N	\N	{0,1,-1,2,3,-1}
89	88	255	1	rearrange	\N	\N	{0,1,-1,2,3,-1}
90	89	257	0	rule_normal	\N	2	\N
91	\N	262	0	set	\N	\N	\N
92	91	263	0	rule_invert	\N	9	\N
93	92	264	3	rule_normal	\N	3	\N
94	93	265	1	rule_normal	\N	3	\N
95	94	266	0	rearrange	\N	\N	{0,2,-1,1,-1,3}
96	95	35	1	rule_invert	\N	11	\N
97	96	39	0	rule_normal	\N	9	\N
98	\N	283	0	set	\N	\N	\N
99	98	286	0	rule_normal	\N	48	\N
100	99	287	2	rule_normal	\N	46	\N
101	100	278	1	rule_normal	\N	49	\N
102	101	13	0	rule_normal	\N	50	\N
103	\N	288	0	set	\N	\N	\N
104	103	289	0	rule_normal	\N	27	\N
105	104	290	1	rule_normal	\N	44	\N
106	105	293	0	rule_normal	\N	45	\N
107	106	294	7	rule_normal	\N	51	\N
108	107	295	0	rearrange	\N	\N	{1,0}
109	108	291	0	rule_invert	\N	11	\N
110	109	298	0	rule_normal	\N	45	\N
111	\N	301	0	set	\N	\N	\N
112	111	300	2	rule_normal	\N	53	\N
113	112	25	0	rule_normal	\N	54	\N
114	\N	306	0	set	\N	\N	\N
115	114	307	0	rule_normal	\N	26	\N
116	115	308	2	rule_normal	\N	44	\N
117	116	311	2	rearrange	\N	\N	{0,1,2,-1}
118	117	315	0	rule_normal	\N	32	\N
119	118	317	2	rule_normal	\N	40	\N
120	119	318	1	rule_normal	\N	16	\N
121	120	314	0	rule_normal	\N	19	\N
122	121	323	2	rule_normal	\N	32	\N
123	122	326	4	rule_normal	\N	55	\N
124	123	328	3	rule_normal	\N	16	\N
125	124	329	2	rule_normal	\N	19	\N
126	125	334	6	rule_normal	\N	30	\N
127	126	338	14	rule_normal	\N	39	\N
128	127	343	7	rule_normal	\N	38	\N
129	128	348	8	rule_normal	\N	56	\N
130	129	352	15	rule_normal	\N	43	\N
131	130	357	9	rule_normal	\N	42	\N
132	131	363	8	rule_normal	\N	57	\N
133	132	368	16	rearrange	\N	\N	{0,1,2,-1}
134	133	373	7	rearrange	\N	\N	{0,1,2,-1}
135	134	377	6	rule_normal	\N	2	\N
136	135	380	2	rearrange	\N	\N	{0,1,-1,2}
137	136	383	3	rule_normal	\N	9	\N
138	\N	386	0	set	\N	\N	\N
139	138	387	0	rule_normal	\N	28	\N
140	139	388	1	rule_normal	\N	58	\N
141	140	390	0	rule_normal	\N	45	\N
142	141	394	3	rule_normal	\N	45	\N
143	142	400	10	rule_normal	\N	48	\N
144	143	405	17	rule_normal	\N	46	\N
145	144	410	12	rule_normal	\N	46	\N
146	145	414	11	rearrange	\N	\N	{1,0}
147	146	416	11	rule_normal	\N	49	\N
148	147	418	10	rule_normal	\N	50	\N
149	148	420	3	rearrange	\N	\N	{1,0}
150	149	421	3	rule_invert	\N	11	\N
151	150	423	3	rule_normal	\N	59	\N
152	\N	425	0	set	\N	\N	\N
153	152	427	2	rule_normal	\N	52	\N
154	153	429	1	rule_invert	\N	9	\N
155	154	432	1	rearrange	\N	\N	{0,1,-1,3,-1,2}
156	155	430	0	rule_normal	\N	20	\N
157	156	434	0	rearrange	\N	\N	{0,1,2,-1}
158	157	423	3	rule_normal	\N	9	\N
159	158	386	0	rule_invert	\N	60	\N
\.


--
-- Name: step_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('step_id_seq', 159, true);


--
-- Data for Name: subject; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY subject (id, descriptor_id) FROM stdin;
1	1
2	2
3	3
4	4
5	5
6	21
7	30
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
41	21	1	Classical Mechanics
42	22	1	Absolute Value
43	23	1	Body
44	24	1	Position
45	25	1	Velocity
46	26	1	Acceleration
47	27	1	Velocity Magnitude
48	28	1	Acceleration Magnitude
49	29	1	Time
50	30	1	Circular Motion
51	31	1	Body with circular path
52	32	1	Cartesian Unit Vector
53	33	1	Square root
54	34	1	Angular Speed
\.


--
-- Name: translation_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('translation_id_seq', 54, true);


--
-- Name: definition definition_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY definition
    ADD CONSTRAINT definition_pkey PRIMARY KEY (id);


--
-- Name: definition definition_rule_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY definition
    ADD CONSTRAINT definition_rule_id_key UNIQUE (rule_id);


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
-- Name: definition definition_rule_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY definition
    ADD CONSTRAINT definition_rule_id_fkey FOREIGN KEY (rule_id) REFERENCES rule(id);


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
-- Name: definition; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT ON TABLE definition TO eqdb;


--
-- Name: definition_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE definition_id_seq TO eqdb;


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

GRANT SELECT,INSERT ON TABLE rule TO eqdb;


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

