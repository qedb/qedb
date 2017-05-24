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
  final extraInstantCommands = new Map<String, EdiTeXCommand>();

  List<FunctionResource> functions;
  List<OperatorResource> operators;
  final operatorConfig = new OperatorConfig();

  EqDBEdiTeXInterface() {
    extraInstantCommands['('] = new EdiTeXCommand(
        '(', parseLaTeXTemplate(r'\left($0\right)', operatorConfig), r'($0)');
    extraInstantCommands['['] = new EdiTeXCommand(
        '[', parseLaTeXTemplate(r'\left[$0\right]', operatorConfig), r'($0)');
  }

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

  String _generateFunctionParseTemplate(FunctionResource fn) {
    final generic = fn.generic ? '?' : '';
    if (fn.argumentCount > 0) {
      final args = new List<String>.generate(fn.argumentCount, (i) => '\$$i');
      return '$generic#${fn.id.toRadixString(16)}#(${args.join(',')})';
    } else {
      return '$generic#${fn.id.toRadixString(16)}#';
    }
  }

  EdiTeXCommand resolveCommand(command) {
    final fns = functions.where((fn) => fn.keyword == command);
    if (fns.isNotEmpty) {
      final fn = fns.single;
      var templateStr = fn.latexTemplate;

      // Generate fallback template.
      if (templateStr == null) {
        templateStr = fn.generic ? r'{}_\text{?}' : '';

        // Add keywords and arguments.
        if (fn.argumentCount == 0) {
          templateStr = '$templateStr${fn.keyword}';
        } else {
          final args =
              new List<String>.generate(fn.argumentCount, (i) => '\$$i');
          templateStr = '$templateStr\\text{${fn.keyword}}'
              '{\\left(${args.join(',\,')}\\right)}';
        }
      }

      final template = parseLaTeXTemplate(templateStr, operatorConfig);
      return new EdiTeXCommand(
          fn.keyword, template, _generateFunctionParseTemplate(fn));
    }
    return null;
  }

  bool hasCommand(command) {
    return functions.any((fn) => fn.keyword == command);
  }

  EdiTeXCommand resolveInstantCommand(command) {
    if (extraInstantCommands.containsKey(command)) {
      return extraInstantCommands[command];
    }

    final ops = operators.where((op) => op.character == command);
    if (ops.isNotEmpty) {
      final op = ops.single;
      if (op.character == '/') {
        // This operator has a special behavior.
        return null;
      }

      // Generate parse template.
      // The operator editor template can never contain arguments that come
      // before the operator (that would have been typed already). Since our
      // operators have a maximum of two arguments, this means at most one
      // argument is present in the operator. If this is the case the parse
      // template will also contain one argument.
      final templateStr = op.editorTemplate;
      final parseTemplate =
          templateStr.contains(r'$0') ? '${op.character}(\$0)' : op.character;

      final template = parseLaTeXTemplate(templateStr, operatorConfig);
      return new EdiTeXCommand(op.character, template, parseTemplate);
    }
    return null;
  }

  bool hasInstantCommand(command) {
    return command != '/' &&
        (extraInstantCommands.containsKey(command) ||
            operators.any((op) => op.character == command));
  }
}
