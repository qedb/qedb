// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

library eqpg.tables;

import 'package:postgresql/postgresql.dart';

/// Base class.
abstract class DbTable {
  final int id;
  DbTable(this.id);
}

//------------------------------------------------------------------------------
// Descriptors and translations
//------------------------------------------------------------------------------

/// Descriptor
class Descriptor implements DbTable {
  final int id;
  final bool isSubject;
  Descriptor(this.id, this.isSubject);

  static const mapFormat = '*';
  static Descriptor map(Row r) => new Descriptor(r[0], r[1]);
}

/// Locale
class Locale implements DbTable {
  final int id;
  final String code;
  Locale(this.id, this.code);

  static const mapFormat = '*';
  static Locale map(Row r) => new Locale(r[0], r[1]);
}

/// Translation
class Translation implements DbTable {
  final int id;
  final int descriptorId, localeId;
  final String content;
  Translation(this.id, this.descriptorId, this.localeId, this.content);

  static const mapFormat = '*';
  static Translation map(Row r) => new Translation(r[0], r[1], r[2], r[3]);
}

//------------------------------------------------------------------------------
// Categories and expression storage
//------------------------------------------------------------------------------

/// Category
class Category implements DbTable {
  final int id;
  final List<int> parents;
  Category(this.id, this.parents);

  static const mapFormat = "id, array_to_string(parents, ',')";
  static Category map(Row r) {
    final String parents = r[1];
    final splittedParents = parents.isEmpty ? [] : parents.split(',');
    return new Category(
        r[0],
        new List<int>.generate(
            splittedParents.length, (i) => int.parse(splittedParents[i])));
  }
}

/// Function
class Function implements DbTable {
  final int id;
  final int categoryId;
  final int argumentCount;
  final String latexTemplate;
  final bool generic;
  Function(this.id, this.categoryId, this.argumentCount, this.latexTemplate,
      this.generic);

  static const mapFormat = '*';
  static Function map(Row r) => new Function(r[0], r[1], r[2], r[3], r[4]);
}

/// Operator configuration
class OperatorConfiguration implements DbTable {
  final int id;
  final int functionId;
  final int precedenceLevel;
  final String associativity;
  OperatorConfiguration(
      this.id, this.functionId, this.precedenceLevel, this.associativity);

  static const mapFormat = '*';
  static OperatorConfiguration map(Row r) =>
      new OperatorConfiguration(r[0], r[1], r[2], r[3]);
}

/// Expression reference
class ExpressionReference {
  final int key;
  final String type;
  ExpressionReference(this.key, this.type);
}

/// Expression
class Expression implements DbTable {
  final int id;
  final ExpressionReference reference;
  final String data, hash;
  final List<int> functions;
  Expression(this.id, this.reference, this.data, this.hash, this.functions);

  static final mapFormat = [
    'id',
    '(reference).key',
    '(reference).type',
    "encode(data, 'base64')",
    "encode(hash, 'base64')",
    "array_to_string(functions, ',')"
  ].join(',');
  static Expression map(Row r) {
    final String row5 = r[5];
    final List<String> ids = row5.isEmpty ? [] : row5.split(',');
    final functions =
        new List<int>.generate(ids.length, (i) => int.parse(ids[i]));
    return new Expression(
        r[0], new ExpressionReference(r[1], r[2]), r[3], r[4], functions);
  }
}

/// Function reference
class FunctionReference implements DbTable {
  final int id;
  final int functionId;
  final List<ExpressionReference> arguments;
  FunctionReference(this.id, this.functionId, this.arguments);

  static const mapFormat = "id, function_id, array_to_string(arguments, '')";
  static FunctionReference map(Row r) {
    // Successful parsing requires the use of: `array_to_string(arguments, '')`
    // Note: it is not neccesary to check for empty strings, it is not allowed
    // for function references to have zero arguments.
    final String argsString = r[2];
    final args = argsString.substring(1, argsString.length - 1).split(')(');
    final arguments = new List<ExpressionReference>.generate(args.length, (i) {
      final parts = args[i].split(',');
      return new ExpressionReference(int.parse(parts[0]), parts[1]);
    });
    return new FunctionReference(r[0], r[1], arguments);
  }
}

/// Integer reference
class IntegerReference implements DbTable {
  final int id;
  final int value;
  IntegerReference(this.id, this.value);

  static const mapFormat = '*';
  static IntegerReference map(Row r) => new IntegerReference(r[0], r[1]);
}

//------------------------------------------------------------------------------
// Lineages
//------------------------------------------------------------------------------

/// Lineage tree
class LineageTree implements DbTable {
  final int id;
  LineageTree(this.id);

  static const mapFormat = '*';
  static LineageTree map(Row r) => new LineageTree(r[0]);
}

/// Lineage
class Lineage implements DbTable {
  final int id;
  final int treeId, parentId, branchIndex, initialCategoryId, firstExpressionId;
  Lineage(this.id, this.treeId, this.parentId, this.branchIndex,
      this.initialCategoryId, this.firstExpressionId);

  static const mapFormat = '*';
  static Lineage map(Row r) => new Lineage(r[0], r[1], r[2], r[3], r[4], r[5]);
}

/// Rule
class Rule implements DbTable {
  final int id;
  final int categoryId;
  final int leftExpressionId;
  final int rightExpressionId;
  Rule(this.id, this.categoryId, this.leftExpressionId, this.rightExpressionId);

  static const mapFormat = '*';
  static Rule map(Row r) => new Rule(r[0], r[1], r[2], r[3]);
}

/// Definition
class Definition implements DbTable {
  final int id;
  final int ruleId;
  Definition(this.id, this.ruleId);

  static const mapFormat = '*';
  static Definition map(Row r) => new Definition(r[0], r[1]);
}
