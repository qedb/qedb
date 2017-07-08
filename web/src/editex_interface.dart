// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

library qedb.web.interface;

import 'dart:async';

import 'package:eqlib/eqlib.dart';
import 'package:eqlib/latex.dart';
import 'package:editex/editex.dart';
import 'package:qedb_client/qedb_client.dart';

import 'package:editex/katex.dart' as katex;
import 'package:editex/src/utils.dart' as editex_utils;

/// Implements command resolvers for EdiTeX.
class QEDbEdiTeXInterface implements EdiTeXInterface {
  /// LaTeX printer.
  final LaTeXPrinter printer;

  /// Additional templates for parentheses.
  final instantAdditional = new Map<String, EdiTeXTemplate>();
  final additionalList = new List<EdiTeXTemplate>();

  final List<FunctionResource> functions;
  final List<OperatorResource> operators;
  final Map<int, FunctionResource> functionMap;
  final Map<int, OperatorResource> operatorMap;
  final OperatorConfig operatorConfig;
  final Map<String, int> specialFunctions;

  QEDbEdiTeXInterface(this.functions, this.operators, this.functionMap,
      this.operatorMap, this.operatorConfig, this.specialFunctions)
      : printer = new LaTeXPrinter(
            (int id) => functions.singleWhere((r) => r.id == id).keyword,
            operatorConfig) {
    // Populate LaTeX printer dictionary.
    for (final fn in functions) {
      if (fn.latexTemplate != null) {
        printer.addTemplate(fn.id, fn.latexTemplate);
      }
    }

    // Add additional templates.
    addInstantTemplate('(', r'\left(${0}\right)', r'($0)');
    addInstantTemplate('[', r'\left[${0}\right]', r'($0)');
    //addInstantTemplate('&', r'\quad\land\quad', r'&');
  }

  void addInstantTemplate(String character, String latex, String parsable) {
    final id = (additionalList.length << 2) | 3;
    instantAdditional[character] = new EdiTeXTemplate(
        id, '', parseLaTeXTemplate(latex, operatorConfig), parsable);
    additionalList.add(instantAdditional[character]);
  }

  int assignId(String label, bool generic) {
    // We generate radix string labels (see [_generateFunctionParseTemplate]).
    if (label.length < 3) {
      throw new Exception('invalid label: $label');
    }

    final idStr = label.substring(1, label.length - 1);
    final id = int.parse(idStr, radix: 16, onError: (_) => -1);
    if (id == -1) {
      throw new Exception('invalid label: $label');
    } else {
      return id;
    }
  }

  Expr parse(String content) {
    return parseExpression(content, operatorConfig, assignId);
  }

  /// Use to evaluate expressions client-side.
  /// Note: currently this function is not used.
  num compute(int id, List<num> args) {
    // Only do operations that given two integers will always return an integer.
    if (id == specialFunctions['add']) {
      return args[0] + args[1];
    } else if (id == specialFunctions['subtract']) {
      return args[0] - args[1];
    } else if (id == specialFunctions['multiply']) {
      return args[0] * args[1];
    } else if (id == specialFunctions['negate']) {
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
    if (operatorMap.containsKey(id)) {
      final op = operatorMap[id];

      // Generate parse template.
      // This is a dirty solution (happens to work with binary operators).
      final templateStr = op.editorTemplate;
      final parsableTemplate =
          templateStr.contains(r'${0}') ? '${op.character}(\$0)' : op.character;

      final template = parseLaTeXTemplate(templateStr, operatorConfig);
      return new EdiTeXTemplate(
          (op.id << 2) | 1, '', template, parsableTemplate);
    } else {
      return null;
    }
  }

  @override
  List<EdiTeXTemplate> lookupKeyword(keyword) {
    final fns = functions.where((fn) => fn.keyword == keyword);
    return fns.map((fn) => createFunctionTemplate(fn.id)).toList();
  }

  EdiTeXTemplate createFunctionTemplate(int id) {
    if (functionMap.containsKey(id)) {
      final fn = functionMap[id];

      // Generate fallback template.
      var templateStr = fn.latexTemplate;
      if (templateStr == null) {
        templateStr = fn.generic ? r'{}_\text{?}' : '';

        // Add keywords and arguments.
        if (fn.argumentCount == 0) {
          templateStr = '$templateStr${fn.keyword}';
        } else {
          final args =
              new List<String>.generate(fn.argumentCount, (i) => '\${$i}');
          templateStr = '$templateStr\\text{${fn.keyword}}'
              '{\\left(${args.join(',\,')}\\right)}';
        }
      }

      final template = parseLaTeXTemplate(templateStr, operatorConfig);

      // Get a label. According to the constraints we can expect at least a
      // template or a descriptor.
      var label = '?';
      if (fn.descriptor != null) {
        label = fn.descriptor.translations.first.content;
      } else {
        final args = new List<String>.filled(template.parameterCount, r'...');
        final latex = editex_utils.renderLaTeXTemplate(template, args);
        label = katex.renderToStringNoMathML(latex);
      }

      return new EdiTeXTemplate(
          fn.id << 2, label, template, _generateFunctionParseTemplate(fn));
    } else {
      return null;
    }
  }

  bool hasCommand(command) {
    return functions.any((fn) => fn.keyword == command);
  }
}

String _generateFunctionParseTemplate(FunctionResource fn) {
  final generic = fn.generic ? '?' : '';

  // Note that adding the argument list is essential, even if empty, to
  // separate this function from the next one in the final string.
  // (a trailing space is also possible but why not just one solution)
  final args = new List<String>.generate(fn.argumentCount, (i) => '\$$i');
  return '$generic#${fn.id.toRadixString(16)}#(${args.join(',')})';
}

/// Construct [QEDbEdiTeXInterface] instance from database.
Future<QEDbEdiTeXInterface> createQEDbEdiTeXInterface(QedbApi db) async {
  final functions = await db.listFunctions();
  final operators = await db.listOperators();

  final functionMap = new Map<int, FunctionResource>.fromIterable(functions,
      key: (fn) => fn.id, value: (fn) => fn);
  final operatorMap = new Map<int, OperatorResource>.fromIterable(operators,
      key: (op) => op.id, value: (op) => op);

  // Load special functions.
  final specialFunctions = new Map<String, int>();
  for (final function in functions) {
    if (function.specialType != null) {
      specialFunctions[function.specialType] = function.id;
    }
  }

  // Load operator configuration.
  final operatorConfig = new OperatorConfig();
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
  // special behavior. In fact this behavior causes problems] (e.g. a^b c^d).
  final multiply = operatorConfig.byId[specialFunctions['multiply']];
  operatorConfig.add(new Operator(
      operatorConfig.implicitMultiplyId,
      multiply.precedenceLevel,
      multiply.associativity,
      -1,
      OperatorType.infix));

  return new QEDbEdiTeXInterface(functions, operators, functionMap, operatorMap,
      operatorConfig, specialFunctions);
}
