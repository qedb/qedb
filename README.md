[![Travis](https://img.shields.io/travis/eqdb/eqdb.svg)](https://travis-ci.org/eqdb/eqdb)
[![Codecov](https://img.shields.io/codecov/c/github/eqdb/eqdb.svg)](https://codecov.io/gh/eqdb/eqdb)

PostgreSQL backend for EqDB
===========================
This repository implements a database schema and a REST API using the Dart RPC
package. This can also be used as direct database client.

## Suggested improvements for next iteration

+ Find way to use generics for integer-only rules.
+ Add API call that expands a proof into all possible rules (for fundamentals).
+ Add shotcut snippets with keyword for quick expression insertion.
+ Allow keyword reuse within different subjects, guess target function based
  on context subject (determine based on involved functions). Add autocomplete
  UI to EdiTeX to select alternative functions with the same keyword.
