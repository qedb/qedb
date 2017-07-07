// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

library qedb.schema;

import 'package:eqlib/eqlib.dart';
import 'package:qedb/utils.dart';
import 'package:qedb/sqlbuilder.dart';
import 'package:postgresql/postgresql.dart';

part 'src/generated/tables.dart';
part 'src/generated/session_data.dart';

//------------------------------------------------------------------------------
// Descriptors and translations
//------------------------------------------------------------------------------

/// Language
class LanguageRow extends Record {
  final int id;
  final String code;

  LanguageRow(this.id, this.code);
  factory LanguageRow.from(Row r) => new LanguageRow(r[0], r[1]);
}

/// Descriptor
class DescriptorRow extends Record {
  final int id;

  DescriptorRow(this.id);
  factory DescriptorRow.from(Row r) => new DescriptorRow(r[0]);
}

/// Translation
class TranslationRow extends Record {
  final int id;
  final int descriptorId, languageId;
  final String content;

  TranslationRow(this.id, this.descriptorId, this.languageId, this.content);
  factory TranslationRow.from(Row r) =>
      new TranslationRow(r[0], r[1], r[2], r[3]);
}

/// Subject
class SubjectRow extends Record {
  final int id;
  final int descriptorId;

  SubjectRow(this.id, this.descriptorId);
  factory SubjectRow.from(Row r) => new SubjectRow(r[0], r[1]);
}

//------------------------------------------------------------------------------
// Functions and expression storage
//------------------------------------------------------------------------------

/// Function
class FunctionRow extends Record {
  final int id;
  final int subjectId;
  final int descriptorId;
  final bool generic;
  final bool rearrangeable;
  final int argumentCount;
  final String keyword;
  final String keywordType;
  final String latexTemplate;
  final String specialType;

  FunctionRow(
      this.id,
      this.subjectId,
      this.descriptorId,
      this.generic,
      this.rearrangeable,
      this.argumentCount,
      this.keyword,
      this.keywordType,
      this.latexTemplate,
      this.specialType);
  factory FunctionRow.from(Row r) => new FunctionRow(
      r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9]);
}

/// Operator
class OperatorRow extends Record {
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
  factory OperatorRow.from(Row r) =>
      new OperatorRow(r[0], r[1], r[2], r[3], r[4], r[5], r[6]);
}

/// Expression
class ExpressionRow extends Record {
  final int id;
  final String data, hash;
  final String latex;
  final List<int> functions;
  final String nodeType;
  final int nodeValue;
  final List<int> nodeArguments;

  ExpressionRow(this.id, this.data, this.hash, this.latex, this.functions,
      this.nodeType, this.nodeValue, this.nodeArguments);
  factory ExpressionRow.from(Row r) => new ExpressionRow(r[0], fixBase64(r[1]),
      fixBase64(r[2]), r[3], pgIntArray(r[4]), r[5], r[6], pgIntArray(r[7]));

  Expr get expr => new Expr.fromBase64(data);
}

//------------------------------------------------------------------------------
// Rule
//------------------------------------------------------------------------------

/// Rule
class RuleRow extends Record {
  final int id;
  final int stepId;
  final int proofId;
  final bool isDefinition;
  final int leftExpressionId;
  final int rightExpressionId;

  RuleRow(this.id, this.stepId, this.proofId, this.isDefinition,
      this.leftExpressionId, this.rightExpressionId);
  factory RuleRow.from(Row r) =>
      new RuleRow(r[0], r[1], r[2], r[3], r[4], r[5]);
}

/// Condition
class ConditionRow extends Record {
  final int id;
  final int leftExpressionId;
  final int rightExpressionId;

  ConditionRow(this.id, this.leftExpressionId, this.rightExpressionId);
  factory ConditionRow.from(Row r) => new ConditionRow(r[0], r[1], r[2]);
}

/// Rule condition
class RuleConditionRow extends Record {
  final int id;
  final int ruleId;
  final int conditionId;

  RuleConditionRow(this.id, this.ruleId, this.conditionId);
  factory RuleConditionRow.from(Row r) =>
      new RuleConditionRow(r[0], r[1], r[2]);
}

//------------------------------------------------------------------------------
// Expression manipulation
//------------------------------------------------------------------------------

/// Proof
class ProofRow extends Record {
  final int id;
  final int firstStepId;
  final int lastStepId;

  ProofRow(this.id, this.firstStepId, this.lastStepId);
  factory ProofRow.from(Row r) => new ProofRow(r[0], r[1], r[2]);
}

/// Step
class StepRow extends Record {
  final int id;
  final int previousId;
  final int expressionId;

  final String type;
  final int position;

  final bool reverseSides;
  final bool reverseEvaluate;

  final int proofId;
  final int conditionId;
  final int ruleId;
  final List<int> rearrangeFormat;

  StepRow(
      this.id,
      this.previousId,
      this.expressionId,
      this.type,
      this.position,
      this.reverseSides,
      this.reverseEvaluate,
      this.proofId,
      this.conditionId,
      this.ruleId,
      this.rearrangeFormat);
  factory StepRow.from(Row r) => new StepRow(r[0], r[1], r[2], r[3], r[4], r[5],
      r[6], r[7], r[8], r[9], pgIntArray(r[10]));
}

/// Step conditions proof
class ConditionProofRow extends Record {
  final int id;
  final int stepId;
  final int conditionId;
  final int followsRuleId;
  final int followsProofId;
  final bool adoptCondition;
  final bool selfEvident;

  ConditionProofRow(this.id, this.stepId, this.conditionId, this.followsRuleId,
      this.followsProofId, this.adoptCondition, this.selfEvident);
  factory ConditionProofRow.from(Row r) =>
      new ConditionProofRow(r[0], r[1], r[2], r[3], r[4], r[5], r[6]);
}
