// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

library eqpg.tables;

class Category {
  final int id;
  final List<int> path;
  Category(this.id, this.path);
  factory Category.from(List r) {
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
  final bool generic;
  final String latexTemplate;
  final bool useParentheses;
  final int precedenceLevel;
  final String evaluationType;
  Function(this.id, this.categoryId, this.generic, this.latexTemplate,
      this.useParentheses, this.precedenceLevel, this.evaluationType);
  factory Function.from(List r) =>
      new Function(r[0], r[1], r[2], r[3], r[4], r[5], r[6]);
}

class ExpressionReference {
  final int id;
  final String referenceType;
  ExpressionReference(this.id, this.referenceType);
}

class Expression {
  final int id;
  final ExpressionReference reference;
  final String data, hash;
  Expression(this.id, this.reference, this.data, this.hash);
  factory Expression.from(List r) =>
      new Expression(r[0], new ExpressionReference(r[1], r[2]), r[3], r[4]);
}

class FunctionReference {
  final int id, functionId;
  final List<ExpressionReference> arguments;
  FunctionReference(this.id, this.functionId, this.arguments);
  factory FunctionReference.from(List<List> r) => new FunctionReference(
      r[0][0],
      r[0][1],
      new List<ExpressionReference>.generate(
          r.length, (i) => new ExpressionReference(r[i][2], r[i][3])));
}

class IntegerReference {
  final int id, val;
  IntegerReference(this.id, this.val);
  factory IntegerReference.from(List r) => new IntegerReference(r[0], r[1]);
}

class LineageTree {
  final int id;
  LineageTree(this.id);
  factory LineageTree.from(List r) => new LineageTree(r[0]);
}

class Lineage {
  final int id, treeId, parentId, branchIndex, initialCategoryId;
  Lineage(this.id, this.treeId, this.parentId, this.branchIndex,
      this.initialCategoryId);
  factory Lineage.from(List r) => new Lineage(r[0], r[1], r[2], r[3], r[4]);
}

class Definition {
  final int id, treeId;
  Definition(this.id, this.treeId);
  factory Definition.from(List r) => new Definition(r[0], r[1]);
}
