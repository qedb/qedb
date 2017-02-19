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

/// Locale
class LocaleResource extends _Resource<db.LocaleRow> {
  int id;
  String code;

  Map<int, db.LocaleRow> _getTableMap(data) => data.localeTable;

  void load(targetId, data) {
    id = targetId;
    code = data.cache.locales[targetId];
  }

  int getId(SessionData data) =>
      id != null ? id : data.cache.locales.inverse[code];
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
  String latexTemplate;
  CategoryResource category;
  DescriptorResource descriptor;

  Map<int, db.FunctionRow> _getTableMap(data) => data.functionTable;

  void loadFields(row, data) {
    generic = row.generic;
    argumentCount = row.argumentCount;
    latexTemplate = row.latexTemplate;
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

  @ApiProperty(values: const {'rtl': 'right-to-left', 'ltr': 'left-to-right'})
  String associativity;

  FunctionResource function;

  Map<int, db.OperatorRow> _getTableMap(data) => data.operatorTable;

  void loadFields(row, data) {
    precedenceLevel = row.precedenceLevel;
    associativity = row.associativity;
    function = new FunctionResource()..load(row.functionId, data);
  }
}

/// Expression
class ExpressionResource extends _Resource<db.ExpressionRow> {
  int id;
  String data, hash;
  List<int> functions;
  ExpressionReference reference;

  Map<int, db.ExpressionRow> _getTableMap(data) => data.expressionTable;

  void loadFields(row, data) {}
}

/// Function reference (used both for function_reference and integer_reference)
class ExpressionReference {
  int id;
  int value;
  FunctionResource function;
  List<ExpressionReference> arguments;
}

//------------------------------------------------------------------------------
// Lineages
//------------------------------------------------------------------------------

/// Lineage tree
class LineageTreeResource extends _Resource<db.LineageTreeRow> {
  int id;
  List<LineageResource> lineages;

  Map<int, db.LineageTreeRow> _getTableMap(data) => data.lineageTreeTable;

  void loadFields(row, data) {}
}

/// Lineage
class LineageResource extends _Resource<db.LineageRow> {
  int id;
  int branchIndex;
  LineageTreeResource tree;
  LineageResource parent;
  //List<LineageExpressionResource> expressions;

  Map<int, db.LineageRow> _getTableMap(data) => data.lineageTable;

  void loadFields(row, data) {}
}

/// Rule
class RuleResource extends _Resource<db.RuleRow> {
  int id;
  CategoryResource category;
  ExpressionResource leftExpression;
  ExpressionResource rightExpression;

  Map<int, db.RuleRow> _getTableMap(data) => data.ruleTable;

  void loadFields(row, data) {}
}

/// Definition
class DefinitionResource extends _Resource<db.DefinitionRow> {
  int id;
  RuleResource rule;

  Map<int, db.DefinitionRow> _getTableMap(data) => data.definitionTable;

  void loadFields(row, data) {}
}
