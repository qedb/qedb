// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import 'dart:async';

import 'package:eqlib/eqlib.dart';
import 'package:editex/editex.dart';
import 'package:eqdb_client/eqdb_client.dart';

/// Implements command resolvers for EdiTeX.
class EqDBEdiTeXInterface implements EdiTeXInterface {
  static const extraInstantCommands = const {
    '(': const EdiTeXCommand('(', r'\left($0\right)', r'($0)'),
    '[': const EdiTeXCommand('(', r'\left[$0\right]', r'($0)'),
  };

  List<FunctionResource> functions;
  List<OperatorResource> operators;
  final operatorConfig = new OperatorConfig();

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

    // Add default setting for implicit multiplication.
    // (same precedence level as power operator).
    operatorConfig.add(new Operator(
        operatorConfig.implicitMultiplyId,
        operatorConfig.byId[operatorConfig.id('^')].precedenceLevel,
        Associativity.rtl,
        -1,
        OperatorType.infix));
  }

  int assignId(String label, bool generic) {
    // Check if this is a radix label (it is possible that the expression
    // contains uncompleted commands).
    if (!label.startsWith('#')) {
      throw new Exception('expression not complete');
    }

    // We generate radix string labels (see [_generateFunctionParseTemplate]).
    return int.parse(label.substring(1), radix: 16);
  }

  Expr parse(String content) {
    return parseExpression(content, operatorConfig, assignId);
  }

  String _generateFunctionParseTemplate(FunctionResource fn) {
    final generic = fn.generic ? '?' : '';
    if (fn.argumentCount > 0) {
      final args = new List<String>.generate(fn.argumentCount, (i) => '\$$i');
      return '$generic#${fn.id.toRadixString(16)}(${args.join(',')})';
    } else {
      return '$generic#${fn.id.toRadixString(16)}';
    }
  }

  EdiTeXCommand resolveCommand(command) {
    final fns = functions.where((fn) => fn.keyword == command);
    if (fns.isNotEmpty) {
      final fn = fns.single;
      var template = fn.latexTemplate;

      // Generate fallback template.
      if (template == null) {
        template = fn.generic ? r'{}_\text{?}' : '';

        // Add keywords and arguments.
        if (fn.argumentCount == 0) {
          template = '$template${fn.keyword}';
        } else {
          final args =
              new List<String>.generate(fn.argumentCount, (i) => '\$$i');
          template =
              '$template\\text{${fn.keyword}}{\\left(${args.join(',\,')}\\right)}';
        }
      }

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
      final template = op.editorTemplate;
      final parseTemplate =
          template.contains(r'$0') ? '${op.character}(\$0)' : op.character;

      return new EdiTeXCommand(op.character, template, parseTemplate);
    }
    return null;
  }

  bool hasInstantCommand(command) {
    return extraInstantCommands.containsKey(command) ||
        operators.any((op) => op.character == command);
  }
}
