[![Travis](https://img.shields.io/travis/qedb/qedb.svg)](https://travis-ci.org/qedb/qedb)
[![Codecov](https://img.shields.io/codecov/c/github/qedb/qedb.svg)](https://codecov.io/gh/qedb/qedb)

PostgreSQL backend for QEDb
===========================
This repository implements a database schema and a REST API using the Dart RPC
package. This can also be used as direct database client.

## Convention on exception handling

The convention in this repository is to do minimal custom exception handling.
Exceptions should be handled gracefully, but adding code to catch specific
exceptions and show a customized error is not recommended. Doing so adds more
code which usually doesn't actually change how anything works. If there are
reasonable fallbacks, those can be implemented. However it is fine to design
code that makes an assumption that might not always be true, and fails if this
assumption is not true. For example, in this repository we use a map of special
functions such as addition and subtraction. If a value in this map is accessed
(e.g. the equality function) while this value is not present (e.g. in the case
of an empty database), a normal exception will be thrown and nobody gets hurt.
It is of much larger importance that the computations that are done are correct.

## Suggested improvements for next iteration

+ Export simple .tex file from proof.
+ Implement conditions and built-in conditions (integer derivative).
+ Add API call that expands a proof into all possible rules (for fundamentals).

