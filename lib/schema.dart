// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

library eqpg.tables;

import 'package:postgresql/postgresql.dart';

/// Base class.
abstract class Table {
  int get id;
}

//------------------------------------------------------------------------------
// Descriptors and translations
//------------------------------------------------------------------------------

/// Descriptor
class DescriptorTable implements Table {
  final int id;
  DescriptorTable(this.id);

  static const mapFormat = '*';
  static DescriptorTable map(Row r) => new DescriptorTable(r[0]);
}

/// Subject
class SubjectTable implements Table {
  final int id;
  final int descriptorId;
  SubjectTable(this.id, this.descriptorId);

  static const mapFormat = '*';
  static SubjectTable map(Row r) => new SubjectTable(r[0], r[1]);
}

/// Locale
class LocaleTable implements Table {
  final int id;
  final String code;
  LocaleTable(this.id, this.code);

  static const mapFormat = '*';
  static LocaleTable map(Row r) => new LocaleTable(r[0], r[1]);
}

/// Translation
class TranslationTable implements Table {
  final int id;
  final int descriptorId, localeId;
  final String content;
  TranslationTable(this.id, this.descriptorId, this.localeId, this.content);

  static const mapFormat = '*';
  static TranslationTable map(Row r) =>
      new TranslationTable(r[0], r[1], r[2], r[3]);
}

//------------------------------------------------------------------------------
// Categories and expression storage
//------------------------------------------------------------------------------

/// Category
class CategoryTable implements Table {
  final int id;
  final int subjectId;
  final List<int> parents;
  CategoryTable(this.id, this.subjectId, this.parents);

  static const mapFormat = "id, subject_id, array_to_string(parents, ',')";
  static CategoryTable map(Row r) {
    final String parents = r[2];
    final splittedParents = parents.isEmpty ? [] : parents.split(',');
    return new CategoryTable(
        r[0],
        r[1],
        new List<int>.generate(
            splittedParents.length, (i) => int.parse(splittedParents[i])));
  }
}

/// Function
class FunctionTable implements Table {
  final int id;
  final int categoryId;
  final int descriptorId;
  final int argumentCount;
  final String latexTemplate;
  final bool generic;
  FunctionTable(this.id, this.descriptorId, this.categoryId, this.argumentCount,
      this.latexTemplate, this.generic);

  static const mapFormat = '*';
  static FunctionTable map(Row r) =>
      new FunctionTable(r[0], r[1], r[2], r[3], r[4], r[5]);
}

/// Function subject tag
class FunctionSubjectTagTable implements Table {
  final int id;
  final int functionId;
  final int subjectId;
  FunctionSubjectTagTable(this.id, this.functionId, this.subjectId);

  static const mapFormat = '*';
  static FunctionSubjectTagTable map(Row r) =>
      new FunctionSubjectTagTable(r[0], r[1], r[2]);
}

/// Operator configuration
class OperatorConfigurationTable implements Table {
  final int id;
  final int functionId;
  final int precedenceLevel;
  final String associativity;
  OperatorConfigurationTable(
      this.id, this.functionId, this.precedenceLevel, this.associativity);

  static const mapFormat = '*';
  static OperatorConfigurationTable map(Row r) =>
      new OperatorConfigurationTable(r[0], r[1], r[2], r[3]);
}

/// Expression reference
class ExpressionReference {
  final int key;
  final String type;
  ExpressionReference(this.key, this.type);
}

/// Expression
class ExpressionTable implements Table {
  final int id;
  final ExpressionReference reference;
  final String data, hash;
  final List<int> functions;
  ExpressionTable(
      this.id, this.reference, this.data, this.hash, this.functions);

  static final mapFormat = [
    'id',
    '(reference).key',
    '(reference).type',
    "encode(data, 'base64')",
    "encode(hash, 'base64')",
    "array_to_string(functions, ',')"
  ].join(',');
  static ExpressionTable map(Row r) {
    final String row5 = r[5];
    final List<String> ids = row5.isEmpty ? [] : row5.split(',');
    final functions =
        new List<int>.generate(ids.length, (i) => int.parse(ids[i]));
    return new ExpressionTable(
        r[0], new ExpressionReference(r[1], r[2]), r[3], r[4], functions);
  }
}

/// Function reference
class FunctionReferenceTable implements Table {
  final int id;
  final int functionId;
  final List<ExpressionReference> arguments;
  FunctionReferenceTable(this.id, this.functionId, this.arguments);

  static const mapFormat = "id, function_id, array_to_string(arguments, '')";
  static FunctionReferenceTable map(Row r) {
    // Successful parsing requires the use of: `array_to_string(arguments, '')`
    // Note: it is not neccesary to check for empty strings, it is not allowed
    // for function references to have zero arguments.
    final String argsString = r[2];
    final args = argsString.substring(1, argsString.length - 1).split(')(');
    final arguments = new List<ExpressionReference>.generate(args.length, (i) {
      final parts = args[i].split(',');
      return new ExpressionReference(int.parse(parts[0]), parts[1]);
    });
    return new FunctionReferenceTable(r[0], r[1], arguments);
  }
}

/// Integer reference
class IntegerReferenceTable implements Table {
  final int id;
  final int value;
  IntegerReferenceTable(this.id, this.value);

  static const mapFormat = '*';
  static IntegerReferenceTable map(Row r) =>
      new IntegerReferenceTable(r[0], r[1]);
}

//------------------------------------------------------------------------------
// Lineages
//------------------------------------------------------------------------------

/// Lineage
class LineageTable implements Table {
  final int id;
  final int treeId, parentId, branchIndex, initialCategoryId, firstExpressionId;
  LineageTable(this.id, this.treeId, this.parentId, this.branchIndex,
      this.initialCategoryId, this.firstExpressionId);

  static const mapFormat = '*';
  static LineageTable map(Row r) =>
      new LineageTable(r[0], r[1], r[2], r[3], r[4], r[5]);
}

/// Rule
class RuleTable implements Table {
  final int id;
  final int categoryId;
  final int leftExpressionId;
  final int rightExpressionId;
  RuleTable(
      this.id, this.categoryId, this.leftExpressionId, this.rightExpressionId);

  static const mapFormat = '*';
  static RuleTable map(Row r) => new RuleTable(r[0], r[1], r[2], r[3]);
}

/// Definition
class DefinitionTable implements Table {
  final int id;
  final int ruleId;
  DefinitionTable(this.id, this.ruleId);

  static const mapFormat = '*';
  static DefinitionTable map(Row r) => new DefinitionTable(r[0], r[1]);
}
