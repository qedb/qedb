--
-- PostgreSQL database cluster dump
--

SET default_transaction_read_only = off;

SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;

--
-- Drop databases
--

DROP DATABASE qedb;




--
-- Drop roles
--

DROP ROLE postgres;
DROP ROLE qedb;


--
-- Roles
--

CREATE ROLE postgres;
ALTER ROLE postgres WITH SUPERUSER INHERIT CREATEROLE CREATEDB LOGIN REPLICATION BYPASSRLS PASSWORD 'md528780b9a9a19f6753e0a68c9c4fe5e0a';
CREATE ROLE qedb;
ALTER ROLE qedb WITH NOSUPERUSER INHERIT NOCREATEROLE NOCREATEDB LOGIN NOREPLICATION NOBYPASSRLS CONNECTION LIMIT 100 PASSWORD 'md51e208766d1dcc603be7e313f870f1a53';






--
-- Database creation
--

CREATE DATABASE qedb WITH TEMPLATE = template0 OWNER = postgres;
REVOKE CONNECT,TEMPORARY ON DATABASE qedb FROM PUBLIC;
GRANT CONNECT ON DATABASE qedb TO qedb;
GRANT TEMPORARY ON DATABASE qedb TO PUBLIC;
REVOKE CONNECT,TEMPORARY ON DATABASE template1 FROM PUBLIC;
GRANT CONNECT ON DATABASE template1 TO PUBLIC;


\connect postgres

SET default_transaction_read_only = off;

--
-- PostgreSQL database dump
--

-- Dumped from database version 9.6.3
-- Dumped by pg_dump version 9.6.3

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

\connect qedb

SET default_transaction_read_only = off;

--
-- PostgreSQL database dump
--

-- Dumped from database version 9.6.3
-- Dumped by pg_dump version 9.6.3

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
-- Name: special_function_type; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE special_function_type AS ENUM (
    'equals',
    'add',
    'subtract',
    'multiply',
    'divide',
    'power',
    'negate',
    'derivative'
);


ALTER TYPE special_function_type OWNER TO postgres;

--
-- Name: step_type; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE step_type AS ENUM (
    'set',
    'copy_proof',
    'copy_rule',
    'rearrange',
    'substitute_rule',
    'substitute_proof',
    'substitute_free'
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
-- Name: match_subs(integer[], integer[], integer[], integer[], integer[]); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION match_subs(integer[], integer[], integer[], integer[], integer[]) RETURNS boolean
    LANGUAGE plperl
    AS $_$

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

my $EXPR_INTEGER       = 1;
my $EXPR_SYMBOL        = 2;
my $EXPR_SYMBOL_GEN    = 3;
my $EXPR_FUNCTION      = 4;
my $EXPR_FUNCTION_GEN  = 5;

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
        if (exists $$mapping_hash{$hash}) {
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
          pop @stack;                    # Remove first argument flag [1].
          my $other = pop @stack;        # Get other integer.
          pop @stack;                    # Remove computation flag [0].
          my $computation = pop @stack;  # Get computation ID.

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
          push @stack, $argument, 1;
        }
      } else {
        # This is the first argument of the lowest computation in the stack.
        push @stack, $argument, 1;
      }
    } elsif ($type == $EXPR_FUNCTION) {
      if ($value == $id_add || $value == $id_sub ||
          $value == $id_mul || $value == $id_neg) {
        # Push function ID to stack.
        push @stack, $value, 0;

        # Skip argument count and content-length (we know the argument length of
        # all computable functions ahead of time).
        $ptr += 2;

        # If this is the negation function, add a first argument here as an
        # imposter. This way the negation function can be integrated in the same
        # code as the binary operators.
        if ($value == $id_neg) {
          push @stack, 0, 1;
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

my $get_genfn_params = sub {
  my ($ptrs, $mapping_hash, $data) = @_;

  if ((scalar $ptrs) == 3) {
    return $ptrs;
  }

  my $mptr_t = $$ptrs[0];
  my $mptr_p = $$ptrs[1];

  # Get hash of first argument of pattern function.
  # This first argument should be generic.
  my $pattern_arg_hash = $$data[$mptr_p + 5];
  push @$ptrs, $pattern_arg_hash;

  # If no target hash exists and the expression function has 1 argument, the
  # generic is mapped to that argument.
  if (!exists $$mapping_hash{$pattern_arg_hash}) {
    if ($$data[$mptr_t + 3] == 1) {
      # Map pattern argument to hash of first expression argument.
      my $hash = $$data[$mptr_t + 5];
      $$mapping_hash{$pattern_arg_hash} = $hash;
    } else {
      # Argument count not 1, and no target hash exists. So terminate.
      return 0;
    }
  }

  return $ptrs;
};

# Recursive expression pattern matching.
my $match_pattern;
$match_pattern = sub {
  my ($internal_remap, $mapping_hash, $mapping_genfn,
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
      # If the symbol is already mapped to an expression hash, check if the
      # target hash matches this hash in the current position. Else store the
      # target hash.
      if (exists $$mapping_hash{$hash_p}) {
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
      if (exists $$mapping_genfn{$value_p}) {
        # Internal remapping.
        if ($internal_remap) {
          # Disallow generic functions in internal remapping.
          return 0;
        }

        # Retrieve pointers.
        my $ptrs = $get_genfn_params->(
          $$mapping_genfn{$value_p}, $mapping_hash, \@data);
        if ($ptrs == 0) {
          return 0;
        }

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
          if (!$match_pattern->(1, $mapping_hash, $mapping_genfn,
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
        $$mapping_hash{$hash_p} = $hash_t;

        # Add expression pointer to mapping for later use.
        # Both pointers point at the start of the expression.
        $$mapping_genfn{$value_p} = [$ptr_t - 3, $ptr_p - 3];
      }

      # Jump over function body. Generic functions operating on generic
      # functions are actually bullshit, but we handle them anyway.
      if ($type_t == $EXPR_FUNCTION || $type_t == $EXPR_FUNCTION_GEN) {
        $ptr_t += 2 + $data[$ptr_t + 1];
      }
      $ptr_p += 2 + $data[$ptr_p + 1];
    } elsif ($type_p == $EXPR_SYMBOL) {
      # During internal remapping a symbol may be mapped to a customly computed
      # hash.
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
      } elsif (!$internal_remap && $type_t == $EXPR_INTEGER) {
        # Note: we do not run this during internal remapping to avoid
        # complicated cases with difficult behavior.

        # Check if pattern function can be evaluated to the same integer as the
        # target expression.
        my ($evaluated_value, $ptr_t) = $evaluate->($ptr_p - 3, $mapping_hash,
            $computable_ids, \@data);

        if ((!defined $evaluated_value) || $value_t != $evaluated_value) {
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

# Substitution matching
# It is possible to put match_pattern inside this function for some very minimal
# gain (arguments do not have to be copied).
my $match_subs = sub {
  my ($expr_left, $expr_right, $subs_left, $subs_right, $computable_ids) = @_;
  my (%mapping_hash, %mapping_genfn);
  my $ptr_t = 0;
  my $ptr_p = (scalar @$expr_left) + (scalar @$expr_right);
  my @data = (@$expr_left, @$expr_right, @$subs_left, @$subs_right);

  (my $result_left, $ptr_t, $ptr_p) = $match_pattern->(0,
      \%mapping_hash, \%mapping_genfn, $ptr_t, $ptr_p, $computable_ids, @data);
  if (!$result_left) {
    return 0;
  }

  my ($result_right) = $match_pattern->(0, \%mapping_hash, \%mapping_genfn,
      $ptr_t, $ptr_p, $computable_ids, @data);
  return $result_right;
};

return $match_subs->(@_);
$_$;


ALTER FUNCTION public.match_subs(integer[], integer[], integer[], integer[], integer[]) OWNER TO postgres;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: condition_proof; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE condition_proof (
    id integer NOT NULL,
    step_id integer NOT NULL,
    condition_id integer NOT NULL,
    follows_rule_id integer,
    follows_proof_id integer,
    adopt_condition boolean DEFAULT false NOT NULL,
    self_evident boolean DEFAULT false NOT NULL,
    CONSTRAINT self_evident_or_rule_or_proof CHECK ((((follows_rule_id IS NOT NULL) OR (follows_proof_id IS NOT NULL)) <> self_evident))
);


ALTER TABLE condition_proof OWNER TO postgres;

--
-- Name: condition_proof_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE condition_proof_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE condition_proof_id_seq OWNER TO postgres;

--
-- Name: condition_proof_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE condition_proof_id_seq OWNED BY condition_proof.id;


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
    special_type special_function_type,
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
    substitution_id integer NOT NULL,
    CONSTRAINT step_or_proof_or_definition CHECK (((step_id IS NOT NULL) OR (proof_id IS NOT NULL) OR is_definition))
);


ALTER TABLE rule OWNER TO postgres;

--
-- Name: rule_condition; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE rule_condition (
    id integer NOT NULL,
    rule_id integer NOT NULL,
    substitution_id integer NOT NULL
);


ALTER TABLE rule_condition OWNER TO postgres;

--
-- Name: rule_condition_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE rule_condition_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE rule_condition_id_seq OWNER TO postgres;

--
-- Name: rule_condition_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE rule_condition_id_seq OWNED BY rule_condition.id;


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
    step_type step_type NOT NULL,
    "position" smallint DEFAULT 0 NOT NULL,
    reverse_sides boolean DEFAULT false NOT NULL,
    reverse_evaluate boolean DEFAULT false NOT NULL,
    proof_id integer,
    rule_id integer,
    substitution_id integer,
    rearrange_format smallint[],
    CONSTRAINT step_position_check CHECK (("position" >= 0)),
    CONSTRAINT valid_parameterset CHECK ((((previous_id = NULL::integer) AND (step_type = 'set'::step_type)) OR ((previous_id <> NULL::integer) AND (((step_type = 'copy_proof'::step_type) AND (proof_id IS NOT NULL)) OR ((step_type = 'copy_rule'::step_type) AND (rule_id IS NOT NULL)) OR ((step_type = 'rearrange'::step_type) AND (rearrange_format IS NOT NULL)) OR ((step_type = 'substitute_rule'::step_type) AND (rule_id IS NOT NULL)) OR ((step_type = 'substitute_free'::step_type) AND (substitution_id IS NOT NULL))))))
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
-- Name: substitution; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE substitution (
    id integer NOT NULL,
    left_expression_id integer NOT NULL,
    right_expression_id integer NOT NULL,
    left_array_data integer[] NOT NULL,
    right_array_data integer[] NOT NULL,
    CONSTRAINT left_is_not_right CHECK ((left_expression_id <> right_expression_id))
);


ALTER TABLE substitution OWNER TO postgres;

--
-- Name: substitution_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE substitution_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE substitution_id_seq OWNER TO postgres;

--
-- Name: substitution_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE substitution_id_seq OWNED BY substitution.id;


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
-- Name: condition_proof id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY condition_proof ALTER COLUMN id SET DEFAULT nextval('condition_proof_id_seq'::regclass);


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
-- Name: rule_condition id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY rule_condition ALTER COLUMN id SET DEFAULT nextval('rule_condition_id_seq'::regclass);


--
-- Name: step id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY step ALTER COLUMN id SET DEFAULT nextval('step_id_seq'::regclass);


--
-- Name: subject id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY subject ALTER COLUMN id SET DEFAULT nextval('subject_id_seq'::regclass);


--
-- Name: substitution id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY substitution ALTER COLUMN id SET DEFAULT nextval('substitution_id_seq'::regclass);


--
-- Name: translation id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY translation ALTER COLUMN id SET DEFAULT nextval('translation_id_seq'::regclass);


--
-- Data for Name: condition_proof; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY condition_proof (id, step_id, condition_id, follows_rule_id, follows_proof_id, adopt_condition, self_evident) FROM stdin;
\.


--
-- Name: condition_proof_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('condition_proof_id_seq', 1, false);


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
\.


--
-- Name: descriptor_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('descriptor_id_seq', 25, true);


--
-- Data for Name: expression; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY expression (id, data, hash, latex, functions, node_type, node_value, node_arguments) FROM stdin;
1	\\x000000000100010009000000000000	\\x43015c596372b689f4f4cefecd30ec1668862206980cb58d65afb225d9c9cbe1	{}_\\text{?}a	{9}	generic	9	{}
2	\\x00000000010001000a000000000000	\\x7411a5ca9021c1572527e434ecfc5439b308a4c41d55e3ee2ce343cf960f5eb4	{}_\\text{?}b	{10}	generic	10	{}
3	\\x00000000020001000a00000007000000000001000100	\\xd419c9a79fedb89dd8fe433025dd1b7eae46f975b3982323e3eccea316b34423	-{}_\\text{?}b	{10,7}	function	7	{2}
4	\\x0000000004000200090000000a0000000200000007000000000000000200010002000301	\\x06c4317b0d80c1ce50664d8365b0cf06da41d15dbc6038d7f6c18952206908fc	{}_\\text{?}a+-{}_\\text{?}b	{9,10,2,7}	function	2	{1,3}
5	\\x0000000003000200090000000a00000003000000000000000200020001	\\x8af96fecdd3af832e9be5b6e7e23e27060e194b300e94a93954ac7e2dc1c2ee1	{}_\\text{?}a-{}_\\text{?}b	{9,10,3}	function	3	{1,2}
6	\\x0000000003000200090000000a00000004000000000000000200020001	\\xa21a2c2ab7610ca971fa03ef17af32bedb693c45c7877bcb7044ebe488983ee5	{}_\\text{?}a{}_\\text{?}b	{9,10,4}	function	4	{1,2}
7	\\x00000000010001000b000000000000	\\x81e70705060646c78a583ab14aabcd545598cbcd420c7973aba1675c2e8b705f	{}_\\text{?}c	{11}	generic	11	{}
8	\\x0000000003000200090000000b00000004000000000000000200020001	\\xb663acd854dc781f7c56f92ffc5a13a6ebb33ca51b0290a1933a94d5212c4639	{}_\\text{?}a{}_\\text{?}c	{9,11,4}	function	4	{1,7}
9	\\x0000000005000300090000000a0000000b00000002000000040000000000000000000200020003040001040002	\\xda3e94d9a6b49580ebd17ab5ea06b39f39587525854be82bfcfa859de1039c21	{}_\\text{?}a{}_\\text{?}b+{}_\\text{?}a{}_\\text{?}c	{9,10,11,2,4}	function	2	{6,8}
10	\\x00000000030002000a0000000b00000002000000000000000200020001	\\x77b5554abc9aee843fabdb8d710fc6601e1ba533ba6f40d2adc25573ffa87c1b	{}_\\text{?}b+{}_\\text{?}c	{10,11,2}	function	2	{2,7}
11	\\x0000000005000300090000000a0000000b0000000400000002000000000000000000020002000300040102	\\x0aa7057218958cccb8a12433b953a3057847686b280a2cd275d8a3302272f883	{}_\\text{?}a\\left({}_\\text{?}b+{}_\\text{?}c\\right)	{9,10,11,4,2}	function	4	{1,10}
12	\\x00000100000000000100000000	\\xcb8c6ede8e7aef082d6b7f80058cc9b51caf8daeea698e065be21383c51065fc	1	{}	integer	1	{}
13	\\x000001000200010001000000090000000400000000000200010200	\\xf69e3da77bef6544638d46b6830955372b6998c4df20f1c75737895df6774b60	1{}_\\text{?}a	{9,4}	function	4	{12,1}
14	\\x000001000200010001000000090000000600000000000200010002	\\x209140cc8cd71d6d036ba4d6b5f19ec77881b6105cfe09185569ee40cc8020c3	{}_\\text{?}a^{1}	{9,6}	function	6	{1,12}
15	\\x0000000003000200090000000a00000006000000000000000200020001	\\x179655ebc9a1bcc8e05debe8a5658f6c6f5a5a339934ca54eb5e2dc0df1ea618	{}_\\text{?}a^{{}_\\text{?}b}	{9,10,6}	function	6	{1,2}
16	\\x0000000003000200090000000b00000006000000000000000200020001	\\x1a68a647472dc53cf6fbab82825d05945bbc1b46a029514b05127173eb68c1d6	{}_\\text{?}a^{{}_\\text{?}c}	{9,11,6}	function	6	{1,7}
17	\\x0000000005000300090000000a0000000b00000004000000060000000000000000000200020003040001040002	\\xf737887c811816a54bb3ad9658d5ea4b07623762a32802bfbe85dbdd536a1618	{}_\\text{?}a^{{}_\\text{?}b}{}_\\text{?}a^{{}_\\text{?}c}	{9,10,11,4,6}	function	4	{15,16}
18	\\x0000000005000300090000000a0000000b0000000600000002000000000000000000020002000300040102	\\x0846ec457cce9d4c9ed47441fbff1e93670ad5b8f20e649e86579904ddfe839e	{}_\\text{?}a^{{}_\\text{?}b+{}_\\text{?}c}	{9,10,11,6,2}	function	6	{1,10}
19	\\x000000000100010012000000000000	\\x66803c5b1d3ff5751d87132b949534b94e1529b4dee1cbcdfbe6bb274451e5f0	{}_\\text{?}x	{18}	generic	18	{}
20	\\x00000000020002001400000012000000010000000001	\\xd8de07258a5ec8c1ed2095ed4c32887636321d9f17e68f3a3000e2c6b90550bc	{}_\\text{?}\\text{f}{\\left({}_\\text{?}x\\right)}	{20,18}	generic	20	{19}
21	\\x000000000300020012000000140000001700000000000100020002000100	\\x6d897c1dc7964377b27d2d7e48984cb938bdb94e36cf98d3b3c3284ecf23e142	\\frac{\\partial}{\\partial{}_\\text{?}x}{}_\\text{?}\\text{f}{\\left({}_\\text{?}x\\right)}	{18,20,23}	function	23	{19,20}
22	\\x00000000020001001200000015000000000001000100	\\x2bf317b87937578b666b65f3d5feb7f42c1858d8b2d76b458600ac73de15304e	\\Delta{}_\\text{?}x	{18,21}	function	21	{19}
23	\\x00000100000000000000000000	\\xe0afadbd718beefc7b9ec03c368f7f78a9eae4327d59216840678ede42d2fd96	0	{}	integer	0	{}
24	\\x000000000300010012000000020000001500000000000200010001000200	\\xa29e3899e02283ae4fb73ef1e817d1605fa2a1aa9ebf9a90110ae758722a3867	{}_\\text{?}x+\\Delta{}_\\text{?}x	{18,2,21}	function	2	{19,22}
25	\\x00000000040002001400000012000000020000001500000001000000020001000002010301	\\x52cb5617a30d86d9a8ee9b376b749f09f21529396109e5707144ac9e4e8ac53c	{}_\\text{?}\\text{f}{\\left({}_\\text{?}x+\\Delta{}_\\text{?}x\\right)}	{20,18,2,21}	generic	20	{24}
26	\\x00000000050002001400000012000000030000000200000015000000010000000200020001000200030104010001	\\x8442fdf7f36365f6326700b510143796bfed4591ba65fe8a62564b09f642a1a3	{}_\\text{?}\\text{f}{\\left({}_\\text{?}x+\\Delta{}_\\text{?}x\\right)}-{}_\\text{?}\\text{f}{\\left({}_\\text{?}x\\right)}	{20,18,3,2,21}	function	3	{25,20}
27	\\x00000000060002001400000012000000050000000300000002000000150000000100000002000200020001000203000401050100010501	\\x38997f635cb1abde5e22cdb51329cd370d2c21a94282b7b562b64c49f544444a	\\frac{\\,{}_\\text{?}\\text{f}{\\left({}_\\text{?}x+\\Delta{}_\\text{?}x\\right)}-{}_\\text{?}\\text{f}{\\left({}_\\text{?}x\\right)}\\,}{\\,\\Delta{}_\\text{?}x\\,}	{20,18,5,3,2,21}	function	5	{26,22}
28	\\x000001000700020000000000120000001400000016000000150000000500000003000000020000000000010003000100020002000200020300070405010600030001000300	\\x651eb823a52dc229134d48c1a94f3a2fd54a59c2432ffcbdf865441a7760c9bf	\\lim_{\\Delta{}_\\text{?}x\\to0}\\frac{\\,{}_\\text{?}\\text{f}{\\left({}_\\text{?}x+\\Delta{}_\\text{?}x\\right)}-{}_\\text{?}\\text{f}{\\left({}_\\text{?}x\\right)}\\,}{\\,\\Delta{}_\\text{?}x\\,}	{18,20,22,21,5,3,2}	function	22	{22,23,27}
29	\\x0000000003000200090000000a0000001c000000000000000200020001	\\x2d2529dc714196ce5c18046837791686edd0bf1632a20cc797771a01682c48da	\\left(\\begin{matrix}{}_\\text{?}a\\\\{}_\\text{?}b\\end{matrix}\\right)	{9,10,28}	function	28	{1,2}
30	\\x00000000010000000d000000000000	\\xe3ad3e8c134a597c9a8bc2d01896e698815194eeccdac37c9f3983eb2a368a21	\\hat{e_1}	{13}	function	13	{}
31	\\x000000000300010009000000040000000d000000000002000000010002	\\x19751da471698239217fecc64922a9d552dc19e683c1caa6e595e4677ba70ff6	{}_\\text{?}a\\hat{e_1}	{9,4,13}	function	4	{1,30}
32	\\x00000000010000000e000000000000	\\xdb3966066a05fab9fa9f317f9a84d1daf73c5e1fc130ab860d6022ad47947378	\\hat{e_2}	{14}	function	14	{}
33	\\x00000000030001000a000000040000000e000000000002000000010002	\\x42ec8b03c8af9c3cb6dd47ae22e58c3affd6a54c8af30060d97ca89bff7c2eb5	{}_\\text{?}b\\hat{e_2}	{10,4,14}	function	4	{2,32}
34	\\x0000000006000200090000000a00000002000000040000000d0000000e00000000000000020002000000000002030004030105	\\x1928457711ef3003e9f929c2f88de8c57ff8aa78322287f3367823c8d93bf754	{}_\\text{?}a\\hat{e_1}+{}_\\text{?}b\\hat{e_2}	{9,10,2,4,13,14}	function	2	{31,33}
35	\\x0000000005000300090000000a0000000b0000001c000000040000000000000000000200020003040001040002	\\xc45e01c3faea7750f3f6f802293bcc490370c73179780cd83fbade11655a404e	\\left(\\begin{matrix}{}_\\text{?}a{}_\\text{?}b\\\\{}_\\text{?}a{}_\\text{?}c\\end{matrix}\\right)	{9,10,11,28,4}	function	28	{6,8}
36	\\x0000000004000200090000000a000000040000000d00000000000000020000000202000103	\\x8ed875991d441d684417f8c6cc9c20a443031f29ac7a9ab31db5583dac340e36	{}_\\text{?}a{}_\\text{?}b\\hat{e_1}	{9,10,4,13}	function	4	{6,30}
37	\\x0000000004000200090000000b000000040000000e00000000000000020000000202000103	\\x24f499b37694a0c357a2c6a728cbab571e894a1c142fe3410a4a9d3254a2fc2a	{}_\\text{?}a{}_\\text{?}c\\hat{e_2}	{9,11,4,14}	function	4	{8,32}
38	\\x0000000007000300090000000a0000000b00000002000000040000000d0000000e00000000000000000002000200000000000304040001050404000206	\\x05228e414264114cf16d538d581cea9d826c89ff1bdc096a6460e135cb4815c4	{}_\\text{?}a{}_\\text{?}b\\hat{e_1}+{}_\\text{?}a{}_\\text{?}c\\hat{e_2}	{9,10,11,2,4,13,14}	function	2	{36,37}
39	\\x00000000030001000b000000040000000e000000000002000000010002	\\x1697193b18280e9c70a949cea53955e67e2a69cf81b605e3e03c120650555724	{}_\\text{?}c\\hat{e_2}	{11,4,14}	function	4	{7,32}
40	\\x0000000004000200090000000b000000040000000e00000000000000020000000200020103	\\x915675aeb06b009ffb789b01888ff6ae04c286e9731f8ea119d5e36f9e5caa32	{}_\\text{?}a\\left({}_\\text{?}c\\hat{e_2}\\right)	{9,11,4,14}	function	4	{1,39}
41	\\x0000000007000300090000000a0000000b00000002000000040000000d0000000e00000000000000000002000200000000000304040001050400040206	\\xc5ee133a99511504f27b936b3dc5ab5af49bfa70dfcabdbec5ec321932920df9	{}_\\text{?}a{}_\\text{?}b\\hat{e_1}+{}_\\text{?}a\\left({}_\\text{?}c\\hat{e_2}\\right)	{9,10,11,2,4,13,14}	function	2	{36,40}
42	\\x00000000030001000a000000040000000d000000000002000000010002	\\x9173bff7f1f319b137ff4d06e76b185d7c85f90577d03545659d63f153eb7fca	{}_\\text{?}b\\hat{e_1}	{10,4,13}	function	4	{2,30}
43	\\x0000000004000200090000000a000000040000000d00000000000000020000000200020103	\\x464474048ba61398451d021ab677821b109f36b42bcb3cc94c926f83c116d0ae	{}_\\text{?}a\\left({}_\\text{?}b\\hat{e_1}\\right)	{9,10,4,13}	function	4	{1,42}
44	\\x0000000007000300090000000a0000000b00000002000000040000000d0000000e00000000000000000002000200000000000304000401050400040206	\\xa1000008781bcc20f2debe57279a2e61d4d46e0da6b66d46ed60bf21901ef34d	{}_\\text{?}a\\left({}_\\text{?}b\\hat{e_1}\\right)+{}_\\text{?}a\\left({}_\\text{?}c\\hat{e_2}\\right)	{9,10,11,2,4,13,14}	function	2	{43,40}
45	\\x00000000060002000a0000000b00000002000000040000000d0000000e00000000000000020002000000000002030004030105	\\xc3198650145c5aa0773524388b4613da5203e15008a8f3266a1ecca1712a278a	{}_\\text{?}b\\hat{e_1}+{}_\\text{?}c\\hat{e_2}	{10,11,2,4,13,14}	function	2	{42,39}
46	\\x0000000007000300090000000a0000000b00000004000000020000000d0000000e0000000000000000000200020000000000030004030105030206	\\xf36878477e942efa4226507a7c6ffbdc1fe53e64426ad592145c3671670b4bb8	{}_\\text{?}a\\left({}_\\text{?}b\\hat{e_1}+{}_\\text{?}c\\hat{e_2}\\right)	{9,10,11,4,2,13,14}	function	4	{1,45}
47	\\x00000000030002000a0000000b0000001c000000000000000200020001	\\xb6ebc726bb9ddeefaeda42bb258c810af48922ebc43cbea4b07b827dd0bbeab6	\\left(\\begin{matrix}{}_\\text{?}b\\\\{}_\\text{?}c\\end{matrix}\\right)	{10,11,28}	function	28	{2,7}
48	\\x0000000005000300090000000a0000000b000000040000001c000000000000000000020002000300040102	\\xc328e2d948a76d43c68b261b84b35da8667072efe9bf565624d0d6ebe00c183b	{}_\\text{?}a\\left(\\begin{matrix}{}_\\text{?}b\\\\{}_\\text{?}c\\end{matrix}\\right)	{9,10,11,4,28}	function	4	{1,47}
\.


--
-- Name: expression_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('expression_id_seq', 48, true);


--
-- Data for Name: function; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY function (id, subject_id, descriptor_id, generic, rearrangeable, argument_count, keyword, keyword_type, latex_template, special_type) FROM stdin;
1	1	8	f	f	2	\N	\N	${.0}=${1.}	equals
2	1	9	f	t	2	\N	\N	${.0}+${1(+).}	add
3	1	10	f	f	2	\N	\N	${.0}-${1(+).}	subtract
4	1	11	f	t	2	\N	\N	${.0(+):}${:1(*).}	multiply
5	1	12	f	f	2	frac	latex	\\frac{\\,${0}\\,}{\\,${1}\\,}	divide
6	1	13	f	f	2	\N	\N	${.0(*)}^{${1}}	power
7	1	14	f	f	1	\N	\N	$!-${0(^).}	negate
8	2	15	f	f	1	\N	\N	${.0(~):}!	\N
9	1	\N	t	f	0	a	symbol	\N	\N
10	1	\N	t	f	0	b	symbol	\N	\N
11	1	\N	t	f	0	c	symbol	\N	\N
12	1	\N	t	f	0	n	symbol	\N	\N
13	3	\N	f	f	0	e1	symbol	\\hat{e_1}	\N
14	3	\N	f	f	0	e2	symbol	\\hat{e_2}	\N
15	3	\N	f	f	0	e3	symbol	\\hat{e_3}	\N
16	4	16	f	f	1	sin	latex	\\sin${:0(+).}	\N
17	4	17	f	f	1	cos	latex	\\cos${:0(+).}	\N
18	5	\N	t	f	0	x	symbol	\N	\N
19	5	\N	t	f	0	y	symbol	\N	\N
20	5	\N	t	f	1	f	abbreviation	\N	\N
21	5	18	f	f	1	d	symbol	\\Delta${:0(+).}	\N
22	5	19	f	f	3	lim	latex	\\lim_{${0}\\to${1}}${:2(+).}	\N
23	5	20	f	f	2	diff	abbreviation	\\frac{\\partial}{\\partial${:0(+)}}${:1(+).}	derivative
24	1	21	f	f	1	abs	abbreviation	\\left\\|${0}\\right\\|	\N
25	6	22	f	f	0	true	word	\\text{True}	\N
26	6	23	f	f	0	false	word	\\text{False}	\N
27	7	24	f	f	2	leq	abbreviation	${.0}\\leq${1.}	\N
28	1	25	f	f	2	vec2	abbreviation	\\left(\\begin{matrix}${0}\\\\${1}\\end{matrix}\\right)	\N
\.


--
-- Name: function_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('function_id_seq', 28, true);


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
\.


--
-- Name: proof_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('proof_id_seq', 1, true);


--
-- Data for Name: rule; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY rule (id, step_id, proof_id, is_definition, substitution_id) FROM stdin;
1	\N	\N	t	1
2	\N	\N	t	2
3	\N	\N	t	3
4	\N	\N	t	4
5	\N	\N	t	5
6	\N	\N	t	6
7	\N	\N	t	7
8	\N	1	f	8
\.


--
-- Data for Name: rule_condition; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY rule_condition (id, rule_id, substitution_id) FROM stdin;
\.


--
-- Name: rule_condition_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('rule_condition_id_seq', 1, false);


--
-- Name: rule_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('rule_id_seq', 8, true);


--
-- Data for Name: step; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY step (id, previous_id, expression_id, step_type, "position", reverse_sides, reverse_evaluate, proof_id, rule_id, substitution_id, rearrange_format) FROM stdin;
1	\N	35	set	0	f	f	\N	\N	\N	\N
2	1	38	substitute_rule	0	f	f	\N	7	\N	\N
3	2	41	rearrange	6	f	f	\N	\N	\N	{0,1,2,-1}
4	3	44	rearrange	1	f	f	\N	\N	\N	{0,1,2,-1}
5	4	46	substitute_rule	0	f	f	\N	2	\N	\N
6	5	48	substitute_rule	2	t	f	\N	7	\N	\N
\.


--
-- Name: step_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('step_id_seq', 6, true);


--
-- Data for Name: subject; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY subject (id, descriptor_id) FROM stdin;
1	1
2	2
3	3
4	4
5	5
6	6
7	7
\.


--
-- Name: subject_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('subject_id_seq', 7, true);


--
-- Data for Name: substitution; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY substitution (id, left_expression_id, right_expression_id, left_array_data, right_array_data) FROM stdin;
1	4	5	{576332304,4,2,2,11,198119638,3,9,251955836,4,7,1,3,358130610,3,10}	{725194104,4,3,2,6,198119638,3,9,358130610,3,10}
2	9	11	{755105816,4,2,2,22,507440212,4,4,2,6,198119638,3,9,358130610,3,10,792166020,4,4,2,6,198119638,3,9,971369676,3,11}	{528846700,4,4,2,14,198119638,3,9,416255908,4,2,2,6,358130610,3,10,971369676,3,11}
3	1	13	{198119638,3,9}	{955462542,4,4,2,6,5,1,1,198119638,3,9}
4	1	14	{198119638,3,9}	{510478350,4,6,2,6,198119638,3,9,5,1,1}
5	17	18	{71005026,4,4,2,22,695795496,4,6,2,6,198119638,3,9,358130610,3,10,622151856,4,6,2,6,198119638,3,9,971369676,3,11}	{491848602,4,6,2,14,198119638,3,9,416255908,4,2,2,6,358130610,3,10,971369676,3,11}
6	21	28	{909282448,4,23,2,11,910648714,3,18,129606980,5,20,1,3,910648714,3,18}	{298586446,4,22,3,58,662684094,4,21,1,3,910648714,3,18,1,1,0,976197574,4,5,2,42,396128080,4,3,2,29,76780122,5,20,1,16,1022394746,4,2,2,11,910648714,3,18,662684094,4,21,1,3,910648714,3,18,129606980,5,20,1,3,910648714,3,18,662684094,4,21,1,3,910648714,3,18}
7	29	34	{772497386,4,28,2,6,198119638,3,9,358130610,3,10}	{88350546,4,2,2,22,352139162,4,4,2,6,198119638,3,9,665602766,2,13,1030378374,4,4,2,6,358130610,3,10,168365960,2,14}
8	35	48	{834342920,4,28,2,22,507440212,4,4,2,6,198119638,3,9,358130610,3,10,792166020,4,4,2,6,198119638,3,9,971369676,3,11}	{976989156,4,4,2,14,198119638,3,9,76271144,4,28,2,6,358130610,3,10,971369676,3,11}
\.


--
-- Name: substitution_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('substitution_id_seq', 8, true);


--
-- Data for Name: translation; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY translation (id, descriptor_id, language_id, content) FROM stdin;
1	1	1	Basic Algebra
2	2	1	Combinatorics
3	3	1	Vector Algebra
4	4	1	Trigonometry
5	5	1	Calculus
6	6	1	Boolean Algebra
7	7	1	Logic
8	8	1	Equality
9	9	1	Add
10	10	1	Subtract
11	11	1	Multiply
12	12	1	Divide
13	13	1	Power
14	14	1	Negate
15	15	1	Factorial
16	16	1	Sine
17	17	1	Cosine
18	18	1	Delta
19	19	1	Limit
20	20	1	Derivative
21	21	1	Absolute Value
22	22	1	True
23	23	1	False
24	24	1	Less or Equal
25	1	2	Basis algebra
26	2	2	Combinatoriek
27	3	2	Vectoralgebra
28	4	2	Trigonometrie
29	5	2	Calculus
30	8	2	Gelijkheid
31	9	2	Optellen
32	10	2	Aftrekken
33	11	2	Vermenigvuldigen
34	12	2	Delen
35	13	2	Macht
36	14	2	Omkeren
37	15	2	Factorial
38	16	2	Sinus
39	17	2	Cosinus
40	18	2	Delta
41	19	2	Limiet
42	20	2	Afgeleide
43	25	1	2D Vector
\.


--
-- Name: translation_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('translation_id_seq', 43, true);


--
-- Name: condition_proof condition_proof_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY condition_proof
    ADD CONSTRAINT condition_proof_pkey PRIMARY KEY (id);


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
-- Name: function function_special_type_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY function
    ADD CONSTRAINT function_special_type_key UNIQUE (special_type);


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
-- Name: rule_condition rule_condition_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY rule_condition
    ADD CONSTRAINT rule_condition_pkey PRIMARY KEY (id);


--
-- Name: rule_condition rule_condition_rule_id_substitution_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY rule_condition
    ADD CONSTRAINT rule_condition_rule_id_substitution_id_key UNIQUE (rule_id, substitution_id);


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
-- Name: substitution substitution_left_expression_id_right_expression_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY substitution
    ADD CONSTRAINT substitution_left_expression_id_right_expression_id_key UNIQUE (left_expression_id, right_expression_id);


--
-- Name: substitution substitution_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY substitution
    ADD CONSTRAINT substitution_pkey PRIMARY KEY (id);


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
-- Name: function_rearrangeable; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX function_rearrangeable ON function USING btree (rearrangeable);


--
-- Name: function function_latex_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER function_latex_update AFTER UPDATE ON function FOR EACH ROW EXECUTE PROCEDURE clear_expression_latex();


--
-- Name: condition_proof condition_proof_condition_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY condition_proof
    ADD CONSTRAINT condition_proof_condition_id_fkey FOREIGN KEY (condition_id) REFERENCES rule_condition(id);


--
-- Name: condition_proof condition_proof_follows_proof_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY condition_proof
    ADD CONSTRAINT condition_proof_follows_proof_id_fkey FOREIGN KEY (follows_proof_id) REFERENCES proof(id);


--
-- Name: condition_proof condition_proof_follows_rule_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY condition_proof
    ADD CONSTRAINT condition_proof_follows_rule_id_fkey FOREIGN KEY (follows_rule_id) REFERENCES rule(id);


--
-- Name: condition_proof condition_proof_step_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY condition_proof
    ADD CONSTRAINT condition_proof_step_id_fkey FOREIGN KEY (step_id) REFERENCES step(id);


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
-- Name: rule_condition rule_condition_rule_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY rule_condition
    ADD CONSTRAINT rule_condition_rule_id_fkey FOREIGN KEY (rule_id) REFERENCES rule(id);


--
-- Name: rule_condition rule_condition_substitution_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY rule_condition
    ADD CONSTRAINT rule_condition_substitution_id_fkey FOREIGN KEY (substitution_id) REFERENCES substitution(id);


--
-- Name: rule rule_proof_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY rule
    ADD CONSTRAINT rule_proof_id_fkey FOREIGN KEY (proof_id) REFERENCES proof(id);


--
-- Name: rule rule_step_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY rule
    ADD CONSTRAINT rule_step_id_fkey FOREIGN KEY (step_id) REFERENCES step(id);


--
-- Name: rule rule_substitution_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY rule
    ADD CONSTRAINT rule_substitution_id_fkey FOREIGN KEY (substitution_id) REFERENCES substitution(id);


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
-- Name: step step_substitution_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY step
    ADD CONSTRAINT step_substitution_id_fkey FOREIGN KEY (substitution_id) REFERENCES substitution(id);


--
-- Name: subject subject_descriptor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY subject
    ADD CONSTRAINT subject_descriptor_id_fkey FOREIGN KEY (descriptor_id) REFERENCES descriptor(id);


--
-- Name: substitution substitution_left_expression_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY substitution
    ADD CONSTRAINT substitution_left_expression_id_fkey FOREIGN KEY (left_expression_id) REFERENCES expression(id);


--
-- Name: substitution substitution_right_expression_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY substitution
    ADD CONSTRAINT substitution_right_expression_id_fkey FOREIGN KEY (right_expression_id) REFERENCES expression(id);


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

GRANT ALL ON LANGUAGE plperl TO qedb;


--
-- Name: condition_proof; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT ON TABLE condition_proof TO qedb;


--
-- Name: condition_proof_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE condition_proof_id_seq TO qedb;


--
-- Name: descriptor; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT ON TABLE descriptor TO qedb;


--
-- Name: descriptor_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE descriptor_id_seq TO qedb;


--
-- Name: expression; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT ON TABLE expression TO qedb;


--
-- Name: expression.latex; Type: ACL; Schema: public; Owner: postgres
--

GRANT UPDATE(latex) ON TABLE expression TO qedb;


--
-- Name: expression_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE expression_id_seq TO qedb;


--
-- Name: function; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT ON TABLE function TO qedb;


--
-- Name: function.subject_id; Type: ACL; Schema: public; Owner: postgres
--

GRANT UPDATE(subject_id) ON TABLE function TO qedb;


--
-- Name: function.keyword; Type: ACL; Schema: public; Owner: postgres
--

GRANT UPDATE(keyword) ON TABLE function TO qedb;


--
-- Name: function.keyword_type; Type: ACL; Schema: public; Owner: postgres
--

GRANT UPDATE(keyword_type) ON TABLE function TO qedb;


--
-- Name: function.latex_template; Type: ACL; Schema: public; Owner: postgres
--

GRANT UPDATE(latex_template) ON TABLE function TO qedb;


--
-- Name: function_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE function_id_seq TO qedb;


--
-- Name: language; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT ON TABLE language TO qedb;


--
-- Name: language_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE language_id_seq TO qedb;


--
-- Name: operator; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT ON TABLE operator TO qedb;


--
-- Name: operator_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE operator_id_seq TO qedb;


--
-- Name: proof; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT ON TABLE proof TO qedb;


--
-- Name: proof_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE proof_id_seq TO qedb;


--
-- Name: rule; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE ON TABLE rule TO qedb;


--
-- Name: rule_condition; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE ON TABLE rule_condition TO qedb;


--
-- Name: rule_condition_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE rule_condition_id_seq TO qedb;


--
-- Name: rule_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE rule_id_seq TO qedb;


--
-- Name: step; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT ON TABLE step TO qedb;


--
-- Name: step_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE step_id_seq TO qedb;


--
-- Name: subject; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT ON TABLE subject TO qedb;


--
-- Name: subject_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE subject_id_seq TO qedb;


--
-- Name: substitution; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT ON TABLE substitution TO qedb;


--
-- Name: substitution_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE substitution_id_seq TO qedb;


--
-- Name: translation; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT ON TABLE translation TO qedb;


--
-- Name: translation_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE translation_id_seq TO qedb;


--
-- PostgreSQL database dump complete
--

\connect template1

SET default_transaction_read_only = off;

--
-- PostgreSQL database dump
--

-- Dumped from database version 9.6.3
-- Dumped by pg_dump version 9.6.3

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

