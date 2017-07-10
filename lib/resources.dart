// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

library qedb.resources;

import 'package:rpc/rpc.dart';
import 'package:eqlib/eqlib.dart';
import 'package:qedb/sqlbuilder.dart';

import 'package:qedb/schema.dart' as db;

// ignore_for_file: always_declare_return_types, annotate_overrides

/// Boilerplate for resource classes.
abstract class ResourceBase<T extends Record> {
  int get id;
  set id(int v);

  /// Get table info object.
  TableInfo<T, db.SessionData> info();

  /// Load resource data from session [data] using the specified [targetId].
  ResourceBase load(int targetId, db.SessionData data) {
    if (targetId != null) {
      id = targetId;
      final row = info().getCache(data)[targetId];
      if (row != null) {
        loadFields(row, data);
      }

      return this;
    } else {
      return null;
    }
  }

  /// Load remaining resource fields (only if row was found in the session data).
  void loadFields(T row, db.SessionData data) {}

  /// Load from row.
  void loadRow(T row, db.SessionData data) {
    id = row.id;
    loadFields(row, data);
  }
}

//------------------------------------------------------------------------------
// Descriptors and translations
//------------------------------------------------------------------------------

/// Language
class LanguageResource extends ResourceBase<db.LanguageRow> {
  int id;
  String code;

  info() => db.language;

  void loadFields(row, data) {
    code = row.code;
  }
}

/// Descriptor
class DescriptorResource extends ResourceBase<db.DescriptorRow> {
  int id;
  List<TranslationResource> translations;

  info() => db.descriptor;

  /// Implements [load] directly because often the descriptor table is not
  /// actually retrieved.
  DescriptorResource load(targetId, data) {
    if (targetId != null) {
      id = targetId;
      translations = data.translationTable.values
          .where((r) => r.descriptorId == targetId)
          .map((r) => new TranslationResource()..loadRow(r, data))
          .toList();
      return this;
    } else {
      return null;
    }
  }
}

/// Translation
class TranslationResource extends ResourceBase<db.TranslationRow> {
  int id;
  LanguageResource language;
  String content;

  info() => db.translation;

  void loadFields(row, data) {
    language = new LanguageResource().load(row.languageId, data);
    content = row.content;
  }
}

/// Subject
class SubjectResource extends ResourceBase<db.SubjectRow> {
  int id;
  DescriptorResource descriptor;

  info() => db.subject;

  void loadFields(row, data) {
    descriptor = new DescriptorResource().load(row.descriptorId, data);
  }
}

//------------------------------------------------------------------------------
// Functions and expression storage
//------------------------------------------------------------------------------

/// Function
class FunctionResource extends ResourceBase<db.FunctionRow> {
  int id;
  SubjectResource subject;
  DescriptorResource descriptor;
  bool generic;
  bool rearrangeable;
  int argumentCount;
  String keyword;

  @ApiProperty(values: const {
    'word': '[a-z]+ form of the function name descriptor',
    'acronym': 'Short form of the function name descriptor',
    'abbreviation': 'Short form of the function name descriptor',
    'symbol': '[a-z]+ form of the function symbol',
    'latex': 'The keyword is directly related to a LaTeX command'
  })
  String keywordType;

  String latexTemplate;
  String specialType;

  info() => db.function;

  void loadFields(row, data) {
    subject = new SubjectResource().load(row.subjectId, data);
    descriptor = new DescriptorResource().load(row.descriptorId, data);
    generic = row.generic;
    rearrangeable = row.rearrangeable;
    argumentCount = row.argumentCount;
    keyword = row.keyword;
    keywordType = row.keywordType;
    latexTemplate = row.latexTemplate;
    specialType = row.specialType;
  }
}

/// Operator
class OperatorResource extends ResourceBase<db.OperatorRow> {
  int id;
  int precedenceLevel;

  @ApiProperty(values: const {'rtl': 'right-to-left', 'ltr': 'left-to-right'})
  String associativity;

  @ApiProperty(values: const {
    'prefix': 'unary operator written before argument',
    'infix': 'binary operator with infix notation',
    'postfix': 'unary operator written after argument'
  })
  String operatorType;

  String character;
  String editorTemplate;
  FunctionResource function;

  info() => db.operator;

  void loadFields(row, data) {
    precedenceLevel = row.precedenceLevel;
    associativity = row.associativity;
    operatorType = row.operatorType;
    character = row.character;
    editorTemplate = row.editorTemplate;
    function = new FunctionResource().load(row.functionId, data);
  }
}

/// Expression
class ExpressionResource extends ResourceBase<db.ExpressionRow> {
  int id;
  String data;
  String hash;
  String latex;
  List<int> functions;

  info() => db.expression;

  void loadFields(row, sdata) {
    data = row.data;
    hash = row.hash;
    latex = row.latex;
    functions = row.functions;
  }

  Expr get asExpr => new Expr.fromBase64(data);
}

//------------------------------------------------------------------------------
// Rule
//------------------------------------------------------------------------------

/// Substitution
class SubstitutionResource extends ResourceBase<db.SubstitutionRow> {
  int id;
  ExpressionResource leftExpression;
  ExpressionResource rightExpression;

  info() => db.substitution;

  void loadFields(row, data) {
    leftExpression = new ExpressionResource().load(row.leftExpressionId, data);
    rightExpression =
        new ExpressionResource().load(row.rightExpressionId, data);
  }

  Subs get asSubs => new Subs(leftExpression.asExpr, rightExpression.asExpr);
}

/// Rule
class RuleResource extends ResourceBase<db.RuleRow> {
  int id;
  StepResource step;
  ProofResource proof;
  bool isDefinition;
  SubstitutionResource substitution;
  List<RuleCondition> conditions;

  info() => db.rule;

  /// Wrapper to link a [RuleCondition.proof] in the context of a step.
  RuleResource loadWithProofs(int ruleId, int stepId, db.SessionData data) {
    final self = load(ruleId, data);
    if (self == null) {
      return null;
    }

    // Assign proofs to conditions.
    if (conditions != null) {
      for (final condition in conditions) {
        // Check if a condition proof exists for the given [stepId].
        final proofs = data.conditionProofTable.values.where(
            (row) => row.stepId == stepId && row.conditionId == condition.id);

        // If a proof exists, add it to the condition.
        if (proofs.isNotEmpty) {
          condition.proof = new ConditionProofResource()
            ..loadRow(proofs.single, data);
        }
      }
    }

    return this;
  }

  void loadFields(row, data) {
    step = new StepResource().load(row.stepId, data);
    proof = new ProofResource().load(row.proofId, data);
    isDefinition = row.isDefinition;
    substitution = new SubstitutionResource().load(row.substitutionId, data);
    conditions = data.ruleConditionTable.values
        .where((row) => row.ruleId == id)
        .map((row) => new RuleCondition()..loadRow(row, data))
        .toList();
  }
}

/// Rule condition
class RuleCondition extends ResourceBase<db.RuleConditionRow> {
  int id;
  SubstitutionResource substitution;
  ConditionProofResource proof;

  info() => db.ruleCondition;

  void loadFields(row, data) {
    substitution = new SubstitutionResource().load(row.substitutionId, data);
    // The proof may be added later by [RuleResource.loadWithProofs].
  }
}

//------------------------------------------------------------------------------
// Expression manipulation
//------------------------------------------------------------------------------

/// Step
class StepResource extends ResourceBase<db.StepRow> {
  int id;
  ExpressionResource expression;
  int position;

  @ApiProperty(values: const {
    'set': 'Set expression to arbitrary value.',
    'copy_proof': 'Copy first and last expression of a proof.',
    'copy_rule': 'Copy left and right expression of a rule.',
    'rearrange': 'Rearrange using the given format.',
    'substitute_rule': 'Apply a rule based substitution.',
    'substitute_free': 'Apply a free substitution (creates condition).'
  })
  String type;

  ProofResource proof;
  RuleResource rule;
  SubstitutionResource substitution;
  List<int> rearrangeFormat;

  info() => db.step;

  void loadFields(row, data) {
    expression = new ExpressionResource().load(row.expressionId, data);
    proof = new ProofResource().load(row.proofId, data);
    rule = new RuleResource().loadWithProofs(row.ruleId, id, data);
    substitution = new SubstitutionResource().load(row.substitutionId, data);

    position = row.position;
    type = row.type;
    rearrangeFormat = row.rearrangeFormat;
  }
}

/// Condition proof
class ConditionProofResource extends ResourceBase<db.ConditionProofRow> {
  int id;
  RuleResource followsRule;
  ProofResource followsProof;
  bool adoptCondition;
  bool selfEvident;

  info() => db.conditionProof;

  void loadFields(row, data) {
    followsRule = new RuleResource().load(row.followsRuleId, data);
    followsProof = new ProofResource().load(row.followsProofId, data);
    adoptCondition = row.adoptCondition;
    selfEvident = row.selfEvident;
  }
}

/// Proof
class ProofResource extends ResourceBase<db.ProofRow> {
  int id;
  StepResource firstStep;
  StepResource lastStep;

  info() => db.proof;

  void loadFields(row, data) {
    firstStep = new StepResource().load(row.firstStepId, data);
    lastStep = new StepResource().load(row.lastStepId, data);
  }
}
