// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import 'dart:html';
import 'dart:async';

import 'package:editex/editex.dart';
import 'package:http/browser_client.dart';
import 'package:eqdb_client/eqdb_client.dart';

/// Implements command resolvers for EdiTeX.
class CommandResolver {
  List<FunctionResource> functions;
  List<OperatorResource> operators;

  Future loadData(EqdbApi db) async {
    functions = await db.listFunctions();
    operators = await db.listOperators();
  }

  String generateFunctionParseTemplate(FunctionResource fn) {
    final args = new List<String>.generate(fn.argumentCount, (i) => '\$$i');
    return '#${fn.id.toRadixString(16)}(${args.join(',')})';
  }

  EdiTeXCommand resolveCommand(String command) {
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
          fn.keyword, template, generateFunctionParseTemplate(fn));
    }
    return null;
  }

  EdiTeXCommand resolveInstantCommand(String command) {
    final ops = operators.where((op) => op.character == command);
    if (ops.isNotEmpty) {
      final op = ops.single;
      final fn = functions.singleWhere((fn) => fn.id == op.function.id);
      // Strip function template of arguments.
      var template = fn.latexTemplate;
      template = template.replaceAll(new RegExp(r'\$[0-9]+'), '');

      if (op.character == '/') {
        // This operator has a special behavior.
        return null;
      } else if (op.character == '*') {
        // The database template uses implicit multiplication.
        template = '\\cdot';
      }

      // Surround infix operators with groups to force spacing in LaTeX.
      if (op.operatorType == 'infix') {
        template = '{}$template{}';
      }

      return new EdiTeXCommand(
          op.character, template, generateFunctionParseTemplate(fn));
    }
    return null;
  }
}

Future main() async {
  // Retrieve operators and functions.
  final db = new EqdbApi(new BrowserClient());
  final resolver = new CommandResolver();
  await resolver.loadData(db);
  final editexInterface = new EdiTeXInterface(
      resolver.resolveCommand, resolver.resolveInstantCommand);

  // Construct editors.
  EdiTeX prev;
  for (final div in querySelectorAll('.editex')) {
    final editor = new EdiTeX(div, editexInterface);

    if (prev != null) {
      prev.onRightLeave.listen((_) {
        editor.cursorIdx = 0;
        editor.doUpdate = true;
        editor.container.focus();
      });

      final prevWrapper = prev;
      editor.onLeftLeave.listen((_) {
        prevWrapper.cursorIdx = prevWrapper.content.length - 1;
        prevWrapper.doUpdate = true;
        prevWrapper.container.focus();
      });
    }

    prev = editor;
  }
}
