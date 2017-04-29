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

/// Language
class LanguageRow implements Record {
  final int id;
  final String code;

  LanguageRow(this.id, this.code);

  static const select = '*';
  static LanguageRow map(Row r) => new LanguageRow(r[0], r[1]);
}

/// Descriptor
class DescriptorRow implements Record {
  final int id;

  DescriptorRow(this.id);

  static const select = '*';
  static DescriptorRow map(Row r) => new DescriptorRow(r[0]);
}

/// Translation
class TranslationRow implements Record {
  final int id;
  final int descriptorId, languageId;
  final String content;

  TranslationRow(this.id, this.descriptorId, this.languageId, this.content);

  static const select = '*';
  static TranslationRow map(Row r) =>
      new TranslationRow(r[0], r[1], r[2], r[3]);
}

/// Subject
class SubjectRow implements Record {
  final int id;
  final int descriptorId;

  SubjectRow(this.id, this.descriptorId);

  static const select = '*';
  static SubjectRow map(Row r) => new SubjectRow(r[0], r[1]);
}

//------------------------------------------------------------------------------
// Functions and expression storage
//------------------------------------------------------------------------------

/// Function
class FunctionRow implements Record {
  final int id;
  final int subjectId;
  final int descriptorId;
  final bool generic;
  final bool rearrangeable;
  final int argumentCount;
  final String keyword;
  final String keywordType;
  final String latexTemplate;

  FunctionRow(
      this.id,
      this.subjectId,
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
  static ExpressionRow map(Row r) => new ExpressionRow(r[0], fixBase64(r[1]),
      fixBase64(r[2]), r[3], pgIntArray(r[4]), r[5], r[6], pgIntArray(r[7]));
}

//------------------------------------------------------------------------------
// Rule
//------------------------------------------------------------------------------

/// Rule
/// Note: left_array_data and right_array_data are not included.
class RuleRow implements Record {
  final int id;
  final int stepId;
  final int proofId;
  final bool isDefinition;
  final int leftExpressionId;
  final int rightExpressionId;

  RuleRow(this.id, this.stepId, this.proofId, this.isDefinition,
      this.leftExpressionId, this.rightExpressionId);

  static const select =
      'id, step_id, proof_id, is_definition, left_expression_id, right_expression_id';
  static RuleRow map(Row r) => new RuleRow(r[0], r[1], r[2], r[3], r[4], r[5]);
}

//------------------------------------------------------------------------------
// Expression manipulation
//------------------------------------------------------------------------------

/// Proof
class ProofRow implements Record {
  final int id;
  final int firstStepId;
  final int lastStepId;

  ProofRow(this.id, this.firstStepId, this.lastStepId);

  static const select = '*';
  static ProofRow map(Row r) => new ProofRow(r[0], r[1], r[2]);
}

/// Step
class StepRow implements Record {
  final int id;
  final int previousId;
  final int expressionId;

  final int position;
  final String type;
  final int proofId;
  final int ruleId;
  final List<int> rearrange;

  StepRow(this.id, this.previousId, this.expressionId, this.position, this.type,
      this.proofId, this.ruleId, this.rearrange);

  static const select = '*';
  static StepRow map(Row r) =>
      new StepRow(r[0], r[1], r[2], r[3], r[4], r[5], r[6], pgIntArray(r[5]));
}
