// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

library eqdb.schema;

import 'package:eqdb/utils.dart';
import 'package:postgresql/postgresql.dart' as pg;

/// Base class.
abstract class Row {
  int get id;
}

//------------------------------------------------------------------------------
// Descriptors and translations
//------------------------------------------------------------------------------

/// Locale
class LocaleRow implements Row {
  final int id;
  final String code;

  LocaleRow(this.id, this.code);

  static const mapFormat = '*';
  static LocaleRow map(pg.Row r) => new LocaleRow(r[0], r[1]);
}

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
  final bool generic;
  final int argumentCount;
  final String keyword;
  final String keywordType;
  final String latexTemplate;

  FunctionRow(this.id, this.categoryId, this.descriptorId, this.generic,
      this.argumentCount, this.keyword, this.keywordType, this.latexTemplate);

  static const mapFormat = '*';
  static FunctionRow map(pg.Row r) =>
      new FunctionRow(r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7]);
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
  final String operatorType;
  final String character;

  OperatorRow(this.id, this.functionId, this.precedenceLevel,
      this.associativity, this.operatorType, this.character);

  static const mapFormat = '*';
  static OperatorRow map(pg.Row r) =>
      new OperatorRow(r[0], r[1], r[2], r[3], r[4], r[5]);
}

/// Expression
class ExpressionRow implements Row {
  final int id;
  final String data, hash;
  final List<int> functions;
  final String nodeType;
  final int nodeValue;
  final List<int> nodeArguments;

  ExpressionRow(this.id, this.data, this.hash, this.functions, this.nodeType,
      this.nodeValue, this.nodeArguments);

  static final mapFormat = [
    'id',
    "encode(data, 'base64')",
    "encode(hash, 'base64')",
    "array_to_string(functions, ',')",
    'node_type',
    'node_value',
    "array_to_string(node_arguments, ',')"
  ].join(',');
  static ExpressionRow map(pg.Row r) => new ExpressionRow(
      r[0], r[1], r[2], intsFromString(r[3]), r[4], r[5], intsFromString(r[6]));
}

//------------------------------------------------------------------------------
// Rules and definitions
//------------------------------------------------------------------------------

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

//------------------------------------------------------------------------------
// Expression lineages
//------------------------------------------------------------------------------

/// Expression lineage
class ExpressionLineageRow implements Row {
  final int id;

  ExpressionLineageRow(this.id);

  static const mapFormat = '*';
  static ExpressionLineageRow map(pg.Row r) => new ExpressionLineageRow(r[0]);
}

/// Expression lineage expression
class LineageExpressionRow implements Row {
  final int id,
      lineageId,
      categoryId,
      ruleId,
      expressionId,
      sequence,
      substitutionPosition;

  LineageExpressionRow(this.id, this.lineageId, this.categoryId, this.ruleId,
      this.expressionId, this.sequence, this.substitutionPosition);

  static const mapFormat = '*';
  static LineageExpressionRow map(pg.Row r) =>
      new LineageExpressionRow(r[0], r[1], r[2], r[3], r[4], r[5], r[6]);
}
