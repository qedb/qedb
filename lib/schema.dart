// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

library eqdb.schema;

import 'package:eqdb/utils.dart';
import 'package:eqdb/sqlbuilder.dart';
import 'package:postgresql/postgresql.dart';

part 'src/generated/tables.dart';
part 'src/generated/session_data.dart';

//------------------------------------------------------------------------------
// Descriptors and translations
//------------------------------------------------------------------------------

/// Locale
class LocaleRow implements Record {
  final int id;
  final String code;

  LocaleRow(this.id, this.code);

  static const select = '*';
  static LocaleRow map(Row r) => new LocaleRow(r[0], r[1]);
}

/// Descriptor
class DescriptorRow implements Record {
  final int id;

  DescriptorRow(this.id);

  static const select = '*';
  static DescriptorRow map(Row r) => new DescriptorRow(r[0]);
}

/// Subject
class SubjectRow implements Record {
  final int id;
  final int descriptorId;

  SubjectRow(this.id, this.descriptorId);

  static const select = '*';
  static SubjectRow map(Row r) => new SubjectRow(r[0], r[1]);
}

/// Translation
class TranslationRow implements Record {
  final int id;
  final int descriptorId, localeId;
  final String content;

  TranslationRow(this.id, this.descriptorId, this.localeId, this.content);

  static const select = '*';
  static TranslationRow map(Row r) =>
      new TranslationRow(r[0], r[1], r[2], r[3]);
}

//------------------------------------------------------------------------------
// Categories and expression storage
//------------------------------------------------------------------------------

/// Category
class CategoryRow implements Record {
  final int id;
  final int subjectId;
  final List<int> parents;

  CategoryRow(this.id, this.subjectId, this.parents);

  static const select = '*';
  static CategoryRow map(Row r) =>
      new CategoryRow(r[0], r[1], pgIntArray(r[2]));
}

/// Function
class FunctionRow implements Record {
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

  static const select = '*';
  static FunctionRow map(Row r) =>
      new FunctionRow(r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8]);
}

/// Function subject tag
class FunctionSubjectTagRow implements Record {
  final int id;
  final int functionId;
  final int subjectId;

  FunctionSubjectTagRow(this.id, this.functionId, this.subjectId);

  static const select = '*';
  static FunctionSubjectTagRow map(Row r) =>
      new FunctionSubjectTagRow(r[0], r[1], r[2]);
}

/// Operator
class OperatorRow implements Record {
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

  static const select = '*';
  static OperatorRow map(Row r) =>
      new OperatorRow(r[0], r[1], r[2], r[3], r[4], r[5], r[6]);
}

/// Expression
class ExpressionRow implements Record {
  final int id;
  final String data, hash;
  final String latex;
  final List<int> functions;
  final String nodeType;
  final int nodeValue;
  final List<int> nodeArguments;

  ExpressionRow(this.id, this.data, this.hash, this.latex, this.functions,
      this.nodeType, this.nodeValue, this.nodeArguments);

  static final select = [
    'id',
    "encode(data, 'base64')",
    "encode(hash, 'base64')",
    'latex',
    'functions',
    'node_type',
    'node_value',
    'node_arguments'
  ].join(',');
  static ExpressionRow map(Row r) => new ExpressionRow(
      r[0], r[1], r[2], r[3], pgIntArray(r[4]), r[5], r[6], pgIntArray(r[7]));
}

//------------------------------------------------------------------------------
// Rules and definitions
//------------------------------------------------------------------------------

/// Rule
/// Note: left_array_data and right_array_data are not included.
class RuleRow implements Record {
  final int id;
  final int categoryId;
  final int leftExpressionId;
  final int rightExpressionId;

  RuleRow(
      this.id, this.categoryId, this.leftExpressionId, this.rightExpressionId);

  static const select =
      'id, category_id, left_expression_id, right_expression_id';
  static RuleRow map(Row r) => new RuleRow(r[0], r[1], r[2], r[3]);
}

/// Definition
class DefinitionRow implements Record {
  final int id;
  final int ruleId;

  DefinitionRow(this.id, this.ruleId);

  static const select = '*';
  static DefinitionRow map(Row r) => new DefinitionRow(r[0], r[1]);
}

//------------------------------------------------------------------------------
// Expression lineages
//------------------------------------------------------------------------------

/// Lineage step
class LineageStepRow implements Record {
  final int id;
  final int previousId;
  final int categoryId;
  final int expressionId;

  final int position;
  final String type;
  final List<int> rearrange;
  final int ruleId;

  LineageStepRow(this.id, this.previousId, this.categoryId, this.expressionId,
      this.position, this.type, this.rearrange, this.ruleId);

  static const select = '*';
  static LineageStepRow map(Row r) => new LineageStepRow(
      r[0], r[1], r[2], r[3], r[4], r[5], pgIntArray(r[6]), r[7]);
}

/// Lineage
class LineageRow implements Record {
  final int id;
  final List<int> steps;

  LineageRow(this.id, this.steps);

  static const select = '*';
  static LineageRow map(Row r) => new LineageRow(r[0], pgIntArray(r[1]));
}
