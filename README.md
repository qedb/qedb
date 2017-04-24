[![Travis](https://img.shields.io/travis/eqdb/eqdb.svg)](https://travis-ci.org/eqdb/eqdb)
[![Codecov](https://img.shields.io/codecov/c/github/eqdb/eqdb.svg)](https://codecov.io/gh/eqdb/eqdb)

PostgreSQL backend for EqDB
===========================
This repository implements a database schema and a REST API using the Dart RPC
package. This can also be used as direct database client.

## Suggested improvements for next iteration

+ Delete rules
+ Expand proof after submission
+ Copy/pase expressions in editor
+ Non-destructive parenthesis removal in editor
+ Look into improving editor performance (HTML diffing?)
+ Look into using matrix notation for vectors
+ Contextual keywords and LaTeX template?
+ Create rule directly from proof
+ Create rule from proof with equality signs
+ Improve automatic generation of parentheses (more specifically for templates
  as `-$0`, `\sin$0` and `\frac{\partial}{\partial$0}$1`)

## Bugs

- EdiTeX: delete parenthenses with `Del` before the closing parentheses does not
  move the cursor index correctly.
