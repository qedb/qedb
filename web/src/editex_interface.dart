// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

library eqdb.web.interface;

import 'dart:async';

import 'package:eqlib/eqlib.dart';
import 'package:eqlib/latex.dart';
import 'package:editex/editex.dart';
import 'package:eqdb_client/eqdb_client.dart';

/// Implements command resolvers for EdiTeX.
class EqDBEdiTeXInterface implements EdiTeXInterface {
  /// Additional templates for parentheses.
  final instantAdditional = new Map<String, EdiTeXTemplate>();
  final additionalList = new List<EdiTeXTemplate>();

  List<FunctionResource> functions;
  List<OperatorResource> operators;
  final operatorConfig = new OperatorConfig();

  EqDBEdiTeXInterface() {
    // Load additional templates.
    instantAdditional['('] = new EdiTeXTemplate((0 << 2) | 4, '',
        parseLaTeXTemplate(r'\left(${0}\right)', operatorConfig), r'($0)');
    additionalList.add(instantAdditional['(']);
    instantAdditional['['] = new EdiTeXTemplate((1 << 2) | 4, '',
        parseLaTeXTemplate(r'\left[${0}\right]', operatorConfig), r'($0)');
    additionalList.add(instantAdditional['[']);
  }

  /// Load functions and operators from database.
  Future loadData(EqdbApi db) async {
    functions = await db.listFunctions();
    operators = await db.listOperators();

    // Populate operator config.
    for (final op in operators) {
      operatorConfig.add(new Operator(
          op.id,
          op.precedenceLevel,
          op.associativity == 'ltr' ? Associativity.ltr : Associativity.rtl,
          op.character.runes.first,
          op.operatorType == 'infix'
              ? OperatorType.infix
              : op.operatorType == 'prefix'
                  ? OperatorType.prefix
                  : OperatorType.postfix));
    }

    // Use the same associativity and precedence as the multiplication operator.
    // Since the input is already structured (editex), there is no need for
    // special behavior. In fact this behavior causes problems (e.g. a^b c^d).
    final multiplyOp = operatorConfig.byId[operatorConfig.id('*')];
    operatorConfig.add(new Operator(
        operatorConfig.implicitMultiplyId,
        multiplyOp.precedenceLevel,
        multiplyOp.associativity,
        -1,
        OperatorType.infix));
  }

  int assignId(String label, bool generic) {
    // We generate radix string labels (see [_generateFunctionParseTemplate]).
    try {
      return int.parse(label.substring(1, label.length - 1), radix: 16);
    } catch (e) {
      throw new Exception('invalid label');
    }
  }

  Expr parse(String content) {
    return parseExpression(content, operatorConfig, assignId);
  }

  num compute(int id, List<num> args) {
    // Only do operations that given two integers will always return an integer.
    if (id == operatorConfig.id('+')) {
      return args[0] + args[1];
    } else if (id == operatorConfig.id('-')) {
      return args[0] - args[1];
    } else if (id == operatorConfig.id('*')) {
      return args[0] * args[1];
    } else if (id == operatorConfig.id('~')) {
      return -args[0];
    } else {
      return double.NAN;
    }
  }

  @override
  EdiTeXTemplate getTemplate(id) {
    // First two bits are used to specify in which sub-collection we look:
    // - 00: functions
    // - 01: operators
    // - 10: shortcuts
    // - 11: custom instant templates

    final subCollection = id & 3;
    final index = id >> 2;
    switch (subCollection) {
      case 0:
        return createFunctionTemplate(index);
      case 1:
        return createOperatorTemplate(index);
      case 3:
        return additionalList[index];
      default:
        return null;
    }
  }

  @override
  EdiTeXTemplate lookupCharacter(char) {
    if (instantAdditional.containsKey(char)) {
      return instantAdditional[char];
    }

    final ops = operators.where((op) => op.character == char);
    if (ops.isNotEmpty) {
      final op = ops.single;
      const specialOperators = const ['/'];
      if (specialOperators.contains(op.character)) {
        return null;
      } else {
        return createOperatorTemplate(op.id);
      }
    }

    return null;
  }

  EdiTeXTemplate createOperatorTemplate(int id) {
    final op = operators.singleWhere((op) => op.id == id);

    // Generate parse template.
    // This is a dirty solution (happens to work with binary operators).
    final templateStr = op.editorTemplate;
    final parsableTemplate =
        templateStr.contains(r'${0}') ? '${op.character}(\$0)' : op.character;

    final template = parseLaTeXTemplate(templateStr, operatorConfig);
    return new EdiTeXTemplate((op.id << 2) | 1, '', template, parsableTemplate);
  }

  @override
  List<EdiTeXTemplate> lookupKeyword(keyword) {
    final fns = functions.where((fn) => fn.keyword == keyword);
    return fns.map((fn) => createFunctionTemplate(fn.id)).toList();
  }

  EdiTeXTemplate createFunctionTemplate(int id) {
    final fn = functions.singleWhere((fn) => fn.id == id);
    var templateStr = fn.latexTemplate;

    // Generate fallback template.
    if (templateStr == null) {
      templateStr = fn.generic ? r'{}_\text{?}' : '';

      // Add keywords and arguments.
      if (fn.argumentCount == 0) {
        templateStr = '$templateStr${fn.keyword}';
      } else {
        final args = new List<String>.generate(fn.argumentCount, (i) => '\$$i');
        templateStr = '$templateStr\\text{${fn.keyword}}'
            '{\\left(${args.join(',\,')}\\right)}';
      }
    }

    final template = parseLaTeXTemplate(templateStr, operatorConfig);
    final desc = fn.descriptor;
    final label = desc != null ? desc.translations.first.content : '?';
    return new EdiTeXTemplate(
        fn.id << 2, label, template, _generateFunctionParseTemplate(fn));
  }

  bool hasCommand(command) {
    return functions.any((fn) => fn.keyword == command);
  }
}

String _generateFunctionParseTemplate(FunctionResource fn) {
  final generic = fn.generic ? '?' : '';
  if (fn.argumentCount > 0) {
    final args = new List<String>.generate(fn.argumentCount, (i) => '\$$i');
    return '$generic#${fn.id.toRadixString(16)}#(${args.join(',')})';
  } else {
    return '$generic#${fn.id.toRadixString(16)}#';
  }
}
