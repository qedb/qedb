// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

library eqpg.resources;

import 'package:rpc/rpc.dart';
import 'package:eqpg/dbutils.dart';

import 'package:eqpg/schema.dart' as db;

//------------------------------------------------------------------------------
// Descriptors and translations
//------------------------------------------------------------------------------

/// Descriptor
class DescriptorResource {
  int id;
  List<TranslationResource> translations;

  DescriptorResource();
  DescriptorResource.idOnly(this.id);
  DescriptorResource.from(db.DescriptorRow target, SessionData data) {
    id = target.id;
    translations = data.translationTable.values
        .where((r) => r.descriptorId == target.id)
        .map((r) => new TranslationResource.from(r, data))
        .toList();
  }

  DescriptorResource.fromTranslations(this.translations);
}

/// Subject
class SubjectResource {
  int id;
  DescriptorResource descriptor;

  SubjectResource();
  SubjectResource.idOnly(this.id);
  SubjectResource.from(db.SubjectRow target, SessionData data) {
    id = target.id;

    if (data.descriptorTable.containsKey(target.descriptorId)) {
      descriptor = new DescriptorResource.from(
          data.descriptorTable[target.descriptorId], data);
    } else {
      descriptor = new DescriptorResource.idOnly(target.descriptorId);
    }
  }
}

/// Locale
class LocaleResource {
  int id;
  String code;

  LocaleResource();
  LocaleResource.idOnly(this.id);
  LocaleResource.from(int targetId, SessionData data) {
    id = targetId;
    code = data.cache.locales[targetId];
  }
}

/// Translation
class TranslationResource {
  int id;
  String content;
  LocaleResource locale;

  TranslationResource();
  TranslationResource.idOnly(this.id);
  TranslationResource.from(db.TranslationRow target, SessionData data) {
    id = target.id;
    content = target.content;
    locale = new LocaleResource.from(target.localeId, data);
  }
}

//------------------------------------------------------------------------------
// Categories and expression storage
//------------------------------------------------------------------------------

/// Category
class CategoryResource {
  int id;
  List<int> parents;
  SubjectResource subject;
  //List<FunctionResource> functions;
  //List<DefinitionResource> definitions;

  CategoryResource();
}

/// Function
class FunctionResource {
  int id;
  int argumentCount;
  String latexTemplate;
  bool generic;
  DescriptorResource descriptor;
}

/// Operator
class OperatorResource {
  int id;
  int precedenceLevel;

  @ApiProperty(values: const {'rtl': 'right-to-left', 'ltr': 'left-to-right'})
  String associativity;

  FunctionResource function;
}

/// Expression
class ExpressionResource {
  int id;
  String data, hash;
  List<int> functions;
  ExpressionReference reference;
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
class LineageTreeResource {
  int id;
  List<LineageResource> lineages;
}

/// Lineage
class LineageResource {
  int id;
  int branchIndex;
  LineageTreeResource tree;
  LineageResource parent;
  //List<LineageExpressionResource> expressions;
}

/// Rule
class RuleResource {
  int id;
  ExpressionResource leftExpression;
  ExpressionResource rightExpression;
}

/// Definition
class DefinitionResource {
  int id;
  RuleResource rule;
}
