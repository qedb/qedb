// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of qedb;

/// Create substitution. Expressions are not evaluated.
Future<db.SubstitutionRow> _createSubstitution(
    Session s, Subs substitution) async {
  // Insert expressions.
  final leftRow = await _createExpression(s, substitution.left);
  final rightRow = await _createExpression(s, substitution.right);

  // Check if a record exists, in this case return this record.
  final result = await s.select(
      db.substitution,
      WHERE({
        'left_expression_id': IS(leftRow.id),
        'right_expression_id': IS(rightRow.id)
      }));
  if (result.isNotEmpty) {
    return result.single;
  } else {
    return s.insert(
        db.substitution,
        VALUES({
          'left_expression_id': leftRow.id,
          'right_expression_id': rightRow.id,
          'left_array_data': ARRAY(leftRow.asExpr.toArray(), 'integer'),
          'right_array_data': ARRAY(rightRow.asExpr.toArray(), 'integer')
        }));
  }
}

Future<List<db.SubstitutionRow>> _listSubstitutions(
    Session s, Iterable<int> ids) {
  return s.selectByIds(db.substitution, ids);
}

/// Retrieve and parse given substitutions.
Future<Map<int, Subs>> getSubsMap(Session s, Iterable<int> ids) async {
  final subss = await s.selectByIds(db.substitution, ids);
  final expressionIds = new List<int>();
  for (final subs in subss) {
    expressionIds.add(subs.leftExpressionId);
    expressionIds.add(subs.rightExpressionId);
  }

  final map = await getExprMap(s, expressionIds);
  return new Map.fromIterable(subss,
      key: (db.SubstitutionRow subs) => subs.id,
      value: (db.SubstitutionRow subs) =>
          new Subs(map[subs.leftExpressionId], map[subs.rightExpressionId]));
}

/// Shorthand for retrieving just a single Subs.
Future<Subs> getSubs(Session s, int id) async {
  return (await getSubsMap(s, [id]))[id];
}

/// Generate equals expression from substitution with the given [id].
Future<Expr> _substitutionAsEqualsExpression(Session s, int id) async {
  final subs = await s.selectById(db.substitution, id);
  final map =
      await getExprMap(s, [subs.leftExpressionId, subs.rightExpressionId]);

  return new FunctionExpr(s.specialFunctions[SpecialFunction.equals], false,
      [map[subs.leftExpressionId], map[subs.rightExpressionId]]);
}

/// Find substitutions that match the given [subs].
/// This function directly searches the database using the match_subs function
/// written in Perl. In some cases, and depending on the size of the rule table,
/// this function might be more suitable than loading a [SubstitutionTable].
Future<List<SubstitutionResult>> findSubstitutions(Session s, Subs subs,
    {Sql subset, bool returnFirst: false}) async {
  final results = new List<SubstitutionResult>();

  // Prepare scanning arguments.
  final exprArraySql = [
    ARRAY(subs.left.toArray(), 'integer'),
    ARRAY(subs.right.toArray(), 'integer')
  ];
  final subsArraySql = [SQL('left_array_data'), SQL('right_array_data')];

  // Get computable function IDs (passed on to the matching algorithm).
  final computableIds = const [
    SpecialFunction.add,
    SpecialFunction.subtract,
    SpecialFunction.multiply,
    SpecialFunction.negate
  ].map((fn) => s.specialFunctions[fn]);
  final computableIdsSql = ARRAY(computableIds, 'integer');

  // Four scans through the given subset of substitutions:
  // 1. try normal substitution on given expression
  // 2. try reversed substitution on given expression
  // 3. try normal substitution on reversed expression
  // 4. try reversed substitution on reversed expression
  for (var i = 0; i < 4; i++) {
    final rItself = i % 2 != 0;
    final rTarget = i >= 2;

    final subsArgs = rItself ? subsArraySql.reversed.toList() : subsArraySql;
    final exprArgs = rTarget ? exprArraySql.reversed.toList() : exprArraySql;

    final substitutions = await s.select(
        db.substitution,
        WHERE({
          'id': IN(subset)
        }, and: [
          _matchSubs(exprArgs[0], exprArgs[1], subsArgs[0], subsArgs[1],
              computableIdsSql)
        ]),
        returnFirst ? LIMIT(1) : SQL('LIMIT ALL'));

    if (substitutions.isNotEmpty) {
      for (final substitution in substitutions) {
        results.add(new SubstitutionResult(substitution, rItself, rTarget));
      }
      if (returnFirst) {
        break;
      }
    }
  }

  return results;
}

/// Substitution search result.
class SubstitutionResult {
  final db.SubstitutionRow substitution;
  final bool reverseItself;
  final bool reverseTarget;

  SubstitutionResult(this.substitution, this.reverseItself, this.reverseTarget);
}

/// Call match_subs SQL function.
Sql _matchSubs(Sql exprLeft, Sql exprRight, Sql subsLeft, Sql subsRight,
        Sql computableIdsArray) =>
    FUNCTION('match_subs', exprLeft, exprRight, subsLeft, subsRight,
        computableIdsArray);
