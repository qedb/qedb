// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

library eqpg.tables;

import 'package:postgresql/postgresql.dart';

////////////////////////////////////////////////////////////////////////////////
// Categories and expression storage
////////////////////////////////////////////////////////////////////////////////

class Category {
  final int id;
  final List<int> path;
  Category(this.id, this.path);
  static Category map(Row r) {
    String path = r[1];
    final splittedPath = path.isEmpty ? [] : path.split(',');
    return new Category(
        r[0],
        new List<int>.generate(
            splittedPath.length, (i) => int.parse(splittedPath[i])));
  }
}

class Function {
  final int id, categoryId;
  final int argumentCount;
  final String latexTemplate;
  final bool generic;
  Function(this.id, this.categoryId, this.argumentCount, this.latexTemplate,
      this.generic);
  static Function map(Row r) => new Function(r[0], r[1], r[2], r[3], r[4]);
}

class ExpressionReference {
  final int id;
  final String type;
  ExpressionReference(this.id, this.type);
}

class Expression {
  final int id;
  final ExpressionReference reference;
  final String data, hash;
  Expression(this.id, this.reference, this.data, this.hash);
  static Expression map(Row r) =>
      new Expression(r[0], new ExpressionReference(r[1], r[2]), r[3], r[4]);
}

class FunctionReference {
  final int id, functionId;
  final List<ExpressionReference> arguments;
  FunctionReference(this.id, this.functionId, this.arguments);
  static FunctionReference map(Row r) {
    // For the time being, this is implemented by ad-hock parsing of the
    // PostgreSQL string representation of expression_reference[].
    final String argsString = r[2];
    if (argsString.isNotEmpty) {
      final args = argsString.substring(1, argsString.length - 2).split(')(');
      final arguments =
          new List<ExpressionReference>.generate(args.length, (i) {
        final parts = args[i].split(',');
        return new ExpressionReference(int.parse(parts[0]), parts[1]);
      });
      return new FunctionReference(r[0], r[1], arguments);
    } else {
      return new FunctionReference(r[0], r[1], []);
    }
  }
}

class IntegerReference {
  final int id, val;
  IntegerReference(this.id, this.val);
  static IntegerReference map(Row r) => new IntegerReference(r[0], r[1]);
}

////////////////////////////////////////////////////////////////////////////////
// Lineages
////////////////////////////////////////////////////////////////////////////////

class LineageTree {
  final int id;
  LineageTree(this.id);
  static LineageTree map(Row r) => new LineageTree(r[0]);
}

class Lineage {
  final int id, treeId, parentId, branchIndex, initialCategoryId;
  Lineage(this.id, this.treeId, this.parentId, this.branchIndex,
      this.initialCategoryId);
  static Lineage map(Row r) => new Lineage(r[0], r[1], r[2], r[3], r[4]);
}

class Rule {
  final int id, leftExpressionId, rightExpressionId;
  Rule(this.id, this.leftExpressionId, this.rightExpressionId);
  static Rule map(Row r) => new Rule(r[0], r[1], r[2]);
}

class Definition {
  final int id, treeId;
  Definition(this.id, this.treeId);
  static Definition map(Row r) => new Definition(r[0], r[1]);
}
