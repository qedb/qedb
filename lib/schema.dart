// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

library eqpg.schema;

import 'package:eqpg/utils.dart';
import 'package:postgresql/postgresql.dart' as pg;

/// Base class.
abstract class Row {
  int get id;
}

//------------------------------------------------------------------------------
// Descriptors and translations
//------------------------------------------------------------------------------

/// Descriptor
class DescriptorRow implements Row {
  final int id;
  DescriptorRow(this.id);

  static const mapFormat = '*';
  static DescriptorRow map(pg.Row r) => new DescriptorRow(r[0]);
}

/// Subject
class SubjectRow implements Row {
  final int id;
  final int descriptorId;
  SubjectRow(this.id, this.descriptorId);

  static const mapFormat = '*';
  static SubjectRow map(pg.Row r) => new SubjectRow(r[0], r[1]);
}

/// Locale
class LocaleRow implements Row {
  final int id;
  final String code;
  LocaleRow(this.id, this.code);

  static const mapFormat = '*';
  static LocaleRow map(pg.Row r) => new LocaleRow(r[0], r[1]);
}

/// Translation
class TranslationRow implements Row {
  final int id;
  final int descriptorId, localeId;
  final String content;

  TranslationRow(this.id, this.descriptorId, this.localeId, this.content);

  static const mapFormat = '*';
  static TranslationRow map(pg.Row r) =>
      new TranslationRow(r[0], r[1], r[2], r[3]);
}

//------------------------------------------------------------------------------
// Categories and expression storage
//------------------------------------------------------------------------------

/// Category
class CategoryRow implements Row {
  final int id;
  final int subjectId;
  final List<int> parents;
  CategoryRow(this.id, this.subjectId, this.parents);

  static const mapFormat = "id, subject_id, array_to_string(parents, ',')";
  static CategoryRow map(pg.Row r) =>
      new CategoryRow(r[0], r[1], intsFromString(r[2]));
}

/// Function
class FunctionRow implements Row {
  final int id;
  final int categoryId;
  final int descriptorId;
  final int argumentCount;
  final String latexTemplate;
  final bool generic;
  FunctionRow(this.id, this.categoryId, this.descriptorId, this.argumentCount,
      this.latexTemplate, this.generic);

  static const mapFormat = '*';
  static FunctionRow map(pg.Row r) =>
      new FunctionRow(r[0], r[1], r[2], r[3], r[4], r[5]);
}

/// Function subject tag
class FunctionSubjectTagRow implements Row {
  final int id;
  final int functionId;
  final int subjectId;
  FunctionSubjectTagRow(this.id, this.functionId, this.subjectId);

  static const mapFormat = '*';
  static FunctionSubjectTagRow map(pg.Row r) =>
      new FunctionSubjectTagRow(r[0], r[1], r[2]);
}

/// Operator
class OperatorRow implements Row {
  final int id;
  final int functionId;
  final int precedenceLevel;
  final String associativity;
  OperatorRow(
      this.id, this.functionId, this.precedenceLevel, this.associativity);

  static const mapFormat = '*';
  static OperatorRow map(pg.Row r) => new OperatorRow(r[0], r[1], r[2], r[3]);
}

/// Expression reference
class ExpressionReference {
  final int key;
  final String type;

  ExpressionReference(this.key, this.type);
  static ExpressionReference map(List<String> r) =>
      new ExpressionReference(int.parse(r[0]), r[1]);
}

/// Expression
class ExpressionRow implements Row {
  final int id;
  final ExpressionReference reference;
  final String data, hash;
  final List<int> functions;
  ExpressionRow(this.id, this.reference, this.data, this.hash, this.functions);

  static final mapFormat = [
    'id',
    '(reference).key',
    '(reference).type',
    "encode(data, 'base64')",
    "encode(hash, 'base64')",
    "array_to_string(functions, ',')"
  ].join(',');
  static ExpressionRow map(pg.Row r) => new ExpressionRow(r[0],
      new ExpressionReference(r[1], r[2]), r[3], r[4], intsFromString(r[5]));
}

/// Function reference
class FunctionReferenceRow implements Row {
  final int id;
  final int functionId;
  final List<ExpressionReference> arguments;
  FunctionReferenceRow(this.id, this.functionId, this.arguments);

  static const mapFormat = "id, function_id, array_to_string(arguments, '')";
  static FunctionReferenceRow map(pg.Row r) => new FunctionReferenceRow(
      r[0], r[1], splitPgRowList(r[2]).map(ExpressionReference.map));
}

/// Integer reference
class IntegerReferenceRow implements Row {
  final int id;
  final int value;
  IntegerReferenceRow(this.id, this.value);

  static const mapFormat = '*';
  static IntegerReferenceRow map(pg.Row r) =>
      new IntegerReferenceRow(r[0], r[1]);
}

//------------------------------------------------------------------------------
// Lineages
//------------------------------------------------------------------------------

/// Lineage
class LineageRow implements Row {
  final int id;
  final int treeId, parentId, branchIndex, initialCategoryId, firstExpressionId;
  LineageRow(this.id, this.treeId, this.parentId, this.branchIndex,
      this.initialCategoryId, this.firstExpressionId);

  static const mapFormat = '*';
  static LineageRow map(pg.Row r) =>
      new LineageRow(r[0], r[1], r[2], r[3], r[4], r[5]);
}

/// Rule
class RuleRow implements Row {
  final int id;
  final int categoryId;
  final int leftExpressionId;
  final int rightExpressionId;
  RuleRow(
      this.id, this.categoryId, this.leftExpressionId, this.rightExpressionId);

  static const mapFormat = '*';
  static RuleRow map(pg.Row r) => new RuleRow(r[0], r[1], r[2], r[3]);
}

/// Definition
class DefinitionRow implements Row {
  final int id;
  final int ruleId;
  DefinitionRow(this.id, this.ruleId);

  static const mapFormat = '*';
  static DefinitionRow map(pg.Row r) => new DefinitionRow(r[0], r[1]);
}
