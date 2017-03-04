// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

library eqpg.resources;

import 'package:rpc/rpc.dart';
import 'package:eqpg/dbutils.dart';

import 'package:eqpg/schema.dart' as db;

/// Boilerplate for resource classes.
abstract class _Resource<T extends db.Row> {
  set id(int v);

  /// Get database row from the session [data] by [id].
  Map<int, T> _getTableMap(SessionData data);

  /// Load resource data from session [data] using the specified [targetId].
  void load(int targetId, SessionData data) {
    id = targetId;
    final row = _getTableMap(data)[targetId];
    if (row != null) {
      loadFields(row, data);
    }
  }

  /// Load remaining resource fiels (only if row was found in the session data).
  void loadFields(T row, SessionData data) {}

  /// Load from row.
  void loadRow(T row, SessionData data) {
    id = row.id;
    loadFields(row, data);
  }
}

//------------------------------------------------------------------------------
// Descriptors and translations
//------------------------------------------------------------------------------

/// Locale
class LocaleResource extends _Resource<db.LocaleRow> {
  int id;
  String code;

  Map<int, db.LocaleRow> _getTableMap(data) => data.localeTable;

  void load(targetId, data) {
    id = targetId;
    code = data.cache.localeIdToCode[targetId];
  }

  int getId(SessionData data) =>
      id != null ? id : data.cache.localeCodeToId[code];
}

/// Descriptor
class DescriptorResource extends _Resource<db.DescriptorRow> {
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

/// Subject
class SubjectResource extends _Resource<db.SubjectRow> {
  int id;
  DescriptorResource descriptor;

  Map<int, db.SubjectRow> _getTableMap(data) => data.subjectTable;

  void loadFields(row, data) {
    descriptor = new DescriptorResource()..load(row.descriptorId, data);
  }
}

/// Translation
class TranslationResource extends _Resource<db.TranslationRow> {
  int id;
  String content;
  LocaleResource locale;

  Map<int, db.TranslationRow> _getTableMap(data) => data.translationTable;

  void loadFields(row, data) {
    content = row.content;
    locale = new LocaleResource()..load(row.localeId, data);
  }
}

//------------------------------------------------------------------------------
// Categories and expression storage
//------------------------------------------------------------------------------

/// Category
class CategoryResource extends _Resource<db.CategoryRow> {
  int id;
  List<int> parents;
  SubjectResource subject;

  Map<int, db.CategoryRow> _getTableMap(data) => data.categoryTable;

  void loadFields(row, data) {
    parents = row.parents;
    subject = new SubjectResource()..load(row.subjectId, data);
  }
}

/// Function
class FunctionResource extends _Resource<db.FunctionRow> {
  int id;
  bool generic;
  int argumentCount;
  List<String> latexTemplates;
  CategoryResource category;
  DescriptorResource descriptor;

  Map<int, db.FunctionRow> _getTableMap(data) => data.functionTable;

  void loadFields(row, data) {
    generic = row.generic;
    argumentCount = row.argumentCount;

    // Extract templates from session data.
    latexTemplates = (data.functionLaTeXTemplateTable.values
            .where((row) => row.functionId == id)
            .toList()..sort((a, b) => a.priority - b.priority))
        .map((row) => row.template)
        .toList();

    category = new CategoryResource()..load(row.categoryId, data);
    if (row.descriptorId != null) {
      descriptor = new DescriptorResource()..load(row.descriptorId, data);
    }
  }
}

/// Operator
class OperatorResource extends _Resource<db.OperatorRow> {
  int id;
  int precedenceLevel;
  String unicodeCharacter;
  String latexCommand;
  FunctionResource function;

  @ApiProperty(values: const {'rtl': 'right-to-left', 'ltr': 'left-to-right'})
  String associativity;

  Map<int, db.OperatorRow> _getTableMap(data) => data.operatorTable;

  void loadFields(row, data) {
    precedenceLevel = row.precedenceLevel;
    associativity = row.associativity;
    unicodeCharacter = row.unicodeCharacter;
    latexCommand = row.latexCommand;
    function = new FunctionResource()..load(row.functionId, data);
  }
}

/// Expression
class ExpressionResource extends _Resource<db.ExpressionRow> {
  int id;
  String data;
  String hash;
  List<int> functions;

  Map<int, db.ExpressionRow> _getTableMap(data) => data.expressionTable;

  void loadFields(row, sdata) {
    data = row.data;
    hash = row.hash;
    functions = row.functions;
  }
}

//------------------------------------------------------------------------------
// Rules and definitions
//------------------------------------------------------------------------------

/// Rule
class RuleResource extends _Resource<db.RuleRow> {
  int id;
  CategoryResource category;
  ExpressionResource leftExpression;
  ExpressionResource rightExpression;

  Map<int, db.RuleRow> _getTableMap(data) => data.ruleTable;

  void loadFields(row, data) {
    category = new CategoryResource()..load(row.categoryId, data);
    leftExpression = new ExpressionResource()..load(row.leftExpressionId, data);
    rightExpression = new ExpressionResource()
      ..load(row.rightExpressionId, data);
  }
}

/// Definition
class DefinitionResource extends _Resource<db.DefinitionRow> {
  int id;
  RuleResource rule;

  Map<int, db.DefinitionRow> _getTableMap(data) => data.definitionTable;

  void loadFields(row, data) {
    rule = new RuleResource()..load(row.ruleId, data);
  }
}

//------------------------------------------------------------------------------
// Expression lineages
//------------------------------------------------------------------------------

/// Expression lineage
class ExpressionLineageResource extends _Resource<db.ExpressionLineageRow> {
  int id;
  List<LineageExpressionResource> expressions;

  Map<int, db.ExpressionLineageRow> _getTableMap(data) =>
      data.expressionLineageTable;
}

/// Expression lineage expression
class LineageExpressionResource extends _Resource<db.LineageExpressionRow> {
  int id;
  ExpressionLineageResource lineage;
  CategoryResource category;
  RuleResource rule;
  ExpressionResource expression;
  int sequence, substitutionPosition;

  Map<int, db.LineageExpressionRow> _getTableMap(data) =>
      data.lineageExpressionTable;
}
