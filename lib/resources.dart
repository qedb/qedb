// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

library qedb.resources;

import 'package:rpc/rpc.dart';
import 'package:eqlib/eqlib.dart';
import 'package:qedb/sqlbuilder.dart';

import 'package:qedb/schema.dart' as db;

/// Boilerplate for resource classes.
abstract class ResourceBase<T extends Record> {
  int get id;
  set id(int v);

  /// Get database row from the session [data] by [id].
  Map<int, T> _getTableMap(db.SessionData data);

  /// Load resource data from session [data] using the specified [targetId].
  void load(int targetId, db.SessionData data) {
    id = targetId;
    final row = _getTableMap(data)[targetId];
    if (row != null) {
      loadFields(row, data);
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

/// Helper for loading [ResourceBase] instance when [id] could be null.
ResourceBase getResource(int id, db.SessionData data, ResourceBase target) {
  if (id == null) {
    return null;
  } else {
    return target..load(id, data);
  }
}

//------------------------------------------------------------------------------
// Descriptors and translations
//------------------------------------------------------------------------------

/// Language
class LanguageResource extends ResourceBase<db.LanguageRow> {
  int id;
  String code;

  Map<int, db.LanguageRow> _getTableMap(data) => data.languageTable;

  void loadFields(row, data) {
    code = row.code;
  }
}

/// Descriptor
class DescriptorResource extends ResourceBase<db.DescriptorRow> {
  int id;
  List<TranslationResource> translations;

  Map<int, db.DescriptorRow> _getTableMap(data) => data.descriptorTable;

  void load(targetId, data) {
    id = targetId;
    translations = data.translationTable.values
        .where((r) => r.descriptorId == targetId)
        .map((r) => new TranslationResource()..loadRow(r, data))
        .toList();
    if (translations.isEmpty) {
      translations = null;
    }
  }
}

/// Translation
class TranslationResource extends ResourceBase<db.TranslationRow> {
  int id;
  LanguageResource language;
  String content;

  Map<int, db.TranslationRow> _getTableMap(data) => data.translationTable;

  void loadFields(row, data) {
    language = new LanguageResource()..load(row.languageId, data);
    content = row.content;
  }
}

/// Subject
class SubjectResource extends ResourceBase<db.SubjectRow> {
  int id;
  DescriptorResource descriptor;

  Map<int, db.SubjectRow> _getTableMap(data) => data.subjectTable;

  void loadFields(row, data) {
    descriptor = new DescriptorResource()..load(row.descriptorId, data);
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

  Map<int, db.FunctionRow> _getTableMap(data) => data.functionTable;

  void loadFields(row, data) {
    subject = getResource(row.subjectId, data, new SubjectResource());
    descriptor = getResource(row.descriptorId, data, new DescriptorResource());
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

  Map<int, db.OperatorRow> _getTableMap(data) => data.operatorTable;

  void loadFields(row, data) {
    precedenceLevel = row.precedenceLevel;
    associativity = row.associativity;
    operatorType = row.operatorType;
    character = row.character;
    editorTemplate = row.editorTemplate;
    function = new FunctionResource()..load(row.functionId, data);
  }
}

/// Expression
class ExpressionResource extends ResourceBase<db.ExpressionRow> {
  int id;
  String data;
  String hash;
  String latex;
  List<int> functions;

  Map<int, db.ExpressionRow> _getTableMap(data) => data.expressionTable;

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

  Map<int, db.SubstitutionRow> _getTableMap(data) => data.substitutionTable;

  void loadFields(row, data) {
    leftExpression = new ExpressionResource()..load(row.leftExpressionId, data);
    rightExpression = new ExpressionResource()
      ..load(row.rightExpressionId, data);
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
  List<SubstitutionResource> conditions;

  Map<int, db.RuleRow> _getTableMap(data) => data.ruleTable;

  void loadFields(row, data) {
    step = getResource(row.stepId, data, new StepResource());
    proof = getResource(row.proofId, data, new ProofResource());
    isDefinition = row.isDefinition;
    substitution = new SubstitutionResource()..load(row.substitutionId, data);

    if (data.ruleConditions.containsKey(id)) {
      conditions = data.ruleConditions[id]
          .map((substitutionId) =>
              new SubstitutionResource()..load(substitutionId, data))
          .toList();
    } else {
      conditions = [];
    }
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

  // TODO
  //List<ConditionProofResource> conditionProofs

  List<int> rearrangeFormat;

  Map<int, db.StepRow> _getTableMap(data) => data.stepTable;

  void loadFields(row, data) {
    expression = new ExpressionResource()..load(row.expressionId, data);
    proof = getResource(row.proofId, data, new ProofResource());
    rule = getResource(row.ruleId, data, new RuleResource());
    substitution =
        getResource(row.substitutionId, data, new SubstitutionResource());

    position = row.position;
    type = row.type;
    rearrangeFormat = row.rearrangeFormat;
  }
}

/// Proof
class ProofResource extends ResourceBase<db.ProofRow> {
  int id;
  StepResource firstStep;
  StepResource lastStep;

  Map<int, db.ProofRow> _getTableMap(data) => data.proofTable;

  void loadFields(row, data) {
    firstStep = getResource(row.firstStepId, data, new StepResource());
    lastStep = getResource(row.lastStepId, data, new StepResource());
  }
}
