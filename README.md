[![Travis](https://img.shields.io/travis/eqdb/eqdb.svg)](https://travis-ci.org/eqdb/eqdb)
[![Codecov](https://img.shields.io/codecov/c/github/eqdb/eqdb.svg)](https://codecov.io/gh/eqdb/eqdb)

PostgreSQL backend for EqDB
===========================
This repository implements a database schema and a REST API using the Dart RPC
package. This can also be used as direct database client.

## Suggested improvements for next iteration

+ Enable explicit boundaries in LaTeX templates. This is useful in the case of
  the unary minus where the '-' often visually collides with other code. E.g.
  consider `diff(a, -1)`. Its template could be `$-$0` where the '$' denotes a
  boundary.
+ Refactor LaTeX printing of negative integers. The easiers way is to built an
  extension into eqlib that applies the negation template to negative integers.
+ Enable usage of tabs to navigate to empty placeholders in EdiTeX.
+ Add API call that expands a proof into all possible rules (for fundamentals).
+ Introduce subject properties that defines that two given subjects are
  definitively non-overlapping.
+ Use subject overlap to allow keyword reuse.
+ Add (subject specific) keywords for quick insertion of specific expressions.
+ Make parenthesis type in LaTeX type configurable (eqlib improvement).
+ Add integer only generics (no arguments) and implement in pattern matching.
