// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

library eqdb.schema;

import 'package:eqdb/utils.dart';
import 'package:eqdb/sqlbuilder.dart';
import 'package:postgresql/postgresql.dart' as pg;

part 'src/generated/tables.dart';
part 'src/generated/session_data.dart';

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
  final bool rearrangeable;
  final int argumentCount;
  final String keyword;
  final String keywordType;
  final String latexTemplate;

  FunctionRow(
      this.id,
      this.categoryId,
      this.descriptorId,
      this.generic,
      this.rearrangeable,
      this.argumentCount,
      this.keyword,
      this.keywordType,
      this.latexTemplate);

  static const mapFormat = '*';
  static FunctionRow map(pg.Row r) =>
      new FunctionRow(r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8]);
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
  final String editorTemplate;

  OperatorRow(
      this.id,
      this.functionId,
      this.precedenceLevel,
      this.associativity,
      this.operatorType,
      this.character,
      this.editorTemplate);

  static const mapFormat = '*';
  static OperatorRow map(pg.Row r) =>
      new OperatorRow(r[0], r[1], r[2], r[3], r[4], r[5], r[6]);
}

/// Expression
class ExpressionRow implements Row {
  final int id;
  final String data, hash;
  final String latex;
  final List<int> functions;
  final String nodeType;
  final int nodeValue;
  final List<int> nodeArguments;

  ExpressionRow(this.id, this.data, this.hash, this.latex, this.functions,
      this.nodeType, this.nodeValue, this.nodeArguments);

  static final mapFormat = [
    'id',
    "encode(data, 'base64')",
    "encode(hash, 'base64')",
    'latex',
    "array_to_string(functions, ',')",
    'node_type',
    'node_value',
    "array_to_string(node_arguments, ',')"
  ].join(',');
  static ExpressionRow map(pg.Row r) => new ExpressionRow(r[0], r[1], r[2],
      r[3], intsFromString(r[4]), r[5], r[6], intsFromString(r[7]));
}

//------------------------------------------------------------------------------
// Rules and definitions
//------------------------------------------------------------------------------

/// Rule
/// Note: left_array_data and right_array_data are not included.
class RuleRow implements Row {
  final int id;
  final int categoryId;
  final int leftExpressionId;
  final int rightExpressionId;

  RuleRow(
      this.id, this.categoryId, this.leftExpressionId, this.rightExpressionId);

  static const mapFormat =
      'id, category_id, left_expression_id, right_expression_id';
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
  final int initialCategoryId;
  final int initialExpressionId;

  ExpressionLineageRow(
      this.id, this.initialCategoryId, this.initialExpressionId);

  static const mapFormat = '*';
  static ExpressionLineageRow map(pg.Row r) =>
      new ExpressionLineageRow(r[0], r[1], r[2]);
}

/// Expression lineage expression
class LineageStepRow implements Row {
  final int id;
  final int lineageId;
  final int categoryId;
  final int expressionId;
  final int ruleId;
  final int position;
  final int sequence;

  LineageStepRow(this.id, this.lineageId, this.categoryId, this.expressionId,
      this.ruleId, this.position, this.sequence);

  static const mapFormat = '*';
  static LineageStepRow map(pg.Row r) =>
      new LineageStepRow(r[0], r[1], r[2], r[3], r[4], r[5], r[6]);
}
