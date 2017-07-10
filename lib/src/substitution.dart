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

/// Get parsed substitution object.
Future<Subs> getSubs(Session s, int id) async {
  final subs = await s.selectById(db.substitution, id);
  final sides = [subs.leftExpressionId, subs.rightExpressionId];
  final map = await getExprMap(s, sides);
  return new Subs(map[sides[0]], map[sides[1]]);
}

/// Generate equals expression from substitution with the given [id].
Future<Expr> _substitutionAsEqualsExpression(Session s, int id) async {
  final subs = await s.selectById(db.substitution, id);
  final map =
      await getExprMap(s, [subs.leftExpressionId, subs.rightExpressionId]);

  return new FunctionExpr(s.specialFunctions[SpecialFunction.equals], false,
      [map[subs.leftExpressionId], map[subs.rightExpressionId]]);
}
