// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

library eqdb.api;

import 'dart:async';

import 'package:rpc/rpc.dart';
import 'package:logging/logging.dart';
import 'package:postgresql/pool.dart';
import 'package:postgresql/postgresql.dart';

import 'package:eqdb/resources.dart';
import 'package:eqdb/eqdb.dart' as api;
import 'package:eqdb/schema.dart' as db;

final log = new Logger('eqdb');
const defaultLanguage = 'en_US';

@ApiClass(name: 'eqdb', version: 'v0', description: 'EqDB read/write API')
class EqDB {
  final Pool pool;

  EqDB(String dbUri, int minConnections, int maxConnections)
      : pool = new Pool(dbUri,
            minConnections: minConnections, maxConnections: maxConnections);

  /// Initialize [pool].
  Future<Null> initialize() async {
    await pool.start();
  }

  /// Utility to reuse method calling boilerplate.
  /// Each select call should allow the specification of language codes and pass
  /// them to [languageIsoCodes].
  Future<T> _runRequestSession<T>(Future<T> handler(api.Session s),
      [List<String> languageIsoCodes = const []]) {
    return _runSandboxed<T>((conn) async {
      final data = new db.SessionData();
      final session = new api.Session(conn, data, []);

      // Retrieve all languages.
      // This may seem a bit ridiculous, but the overhead is not actually that
      // big. Additionally, this makes the rest of the code more convenient, and
      // language codes can be included in all responses for free. A TTL
      // spanning multiple sessions could be used to optimize this.
      await api.listLanguages(session);

      // Resolve language codes.
      session.languages.addAll(api.getLanguageIds(session, languageIsoCodes));

      return handler(session);
    }, pool);
  }

  @ApiMethod(path: 'language/create', method: 'POST')
  Future<LanguageResource> createLanguage(LanguageResource body) =>
      _runRequestSession<LanguageResource>((s) async => new LanguageResource()
        ..load((await api.createLanguage(s, body)).id, s.data));

  @ApiMethod(path: 'language/list', method: 'GET')
  Future<List<LanguageResource>> listLanguages() =>
      // Note that all languages are loaded for each session.
      _runRequestSession<List<LanguageResource>>((s) async => s
          .data.languageTable.values
          .map((r) => new LanguageResource()..loadRow(r, s.data))
          .toList());

  @ApiMethod(path: 'descriptor/list', method: 'GET')
  Future<List<DescriptorResource>> listDescriptors(
          {String language: defaultLanguage}) async =>
      _runRequestSession<List<DescriptorResource>>(
          (s) async => (await api.listDescriptors(s))
              .map((r) => new DescriptorResource()..load(r.id, s.data))
              .toList(),
          [language]);

  @ApiMethod(path: 'descriptor/{id}/read', method: 'GET')
  Future<DescriptorResource> readDescriptor(int id) async =>
      new DescriptorResource()
        ..id = id
        ..translations = await listDescriptorTranslations(id);

  @ApiMethod(path: 'descriptor/{id}/translation/create', method: 'POST')
  Future<TranslationResource> createTranslation(
          int id, TranslationResource body) =>
      _runRequestSession<TranslationResource>((s) async =>
          new TranslationResource()
            ..loadRow(await api.createTranslation(s, id, body), s.data));

  @ApiMethod(path: 'descriptor/{id}/translation/list', method: 'GET')
  Future<List<TranslationResource>> listDescriptorTranslations(int id) =>
      _runRequestSession<List<TranslationResource>>((s) async =>
          (await api.listTranslations(s, id))
              .map((r) => new TranslationResource()..loadRow(r, s.data))
              .toList());

  @ApiMethod(path: 'subject/create', method: 'POST')
  Future<SubjectResource> createSubject(SubjectResource body) =>
      _runRequestSession<SubjectResource>((s) async => new SubjectResource()
        ..loadRow(await api.createSubject(s, body), s.data));

  @ApiMethod(path: 'subject/list', method: 'GET')
  Future<List<SubjectResource>> listSubjects(
          {String language: defaultLanguage}) =>
      _runRequestSession<List<SubjectResource>>(
          (s) async => (await api.listSubjects(s))
              .map((r) => new SubjectResource()..load(r.id, s.data))
              .toList(),
          [language]);

  @ApiMethod(path: 'function/create', method: 'POST')
  Future<FunctionResource> createFunction(FunctionResource body) =>
      _runRequestSession<FunctionResource>((s) async => new FunctionResource()
        ..loadRow(await api.createFunction(s, body), s.data));

  @ApiMethod(path: 'function/{id}/update', method: 'POST')
  Future<FunctionResource> updateFunctionSubject(
          int id, FunctionResource body) =>
      _runRequestSession<FunctionResource>((s) async => new FunctionResource()
        ..loadRow(await api.updateFunction(s, id, body), s.data));

  @ApiMethod(path: 'function/list', method: 'GET')
  Future<List<FunctionResource>> listFunctions(
          {String language: defaultLanguage}) =>
      _runRequestSession<List<FunctionResource>>(
          (s) async => (await api.listFunctions(s))
              .map((r) => new FunctionResource()..loadRow(r, s.data))
              .toList(),
          [language]);

  @ApiMethod(path: 'operator/create', method: 'POST')
  Future<OperatorResource> createOperator(OperatorResource body) =>
      _runRequestSession<OperatorResource>((s) async => new OperatorResource()
        ..loadRow(await api.createOperator(s, body), s.data));

  @ApiMethod(path: 'operator/list', method: 'GET')
  Future<List<OperatorResource>> listOperators() =>
      _runRequestSession<List<OperatorResource>>((s) async =>
          (await api.listOperators(s))
              .map((r) => new OperatorResource()..loadRow(r, s.data))
              .toList());

  @ApiMethod(path: 'rule/create', method: 'POST')
  Future<RuleResource> createRule(RuleResource body) =>
      _runRequestSession<RuleResource>((s) async =>
          new RuleResource()..loadRow(await api.createRule(s, body), s.data));

  @ApiMethod(path: 'rule/list', method: 'GET')
  Future<List<RuleResource>> listRules({String language: defaultLanguage}) =>
      _runRequestSession<List<RuleResource>>(
          (s) async => (await api.listRules(s))
              .map((r) => new RuleResource()..loadRow(r, s.data))
              .toList(),
          [language]);

  @ApiMethod(path: 'definition/create', method: 'POST')
  Future<DefinitionResource> createDefinition(DefinitionResource body) =>
      _runRequestSession<DefinitionResource>((s) async =>
          new DefinitionResource()
            ..loadRow(await api.createDefinition(s, body), s.data));

  @ApiMethod(path: 'definition/list', method: 'GET')
  Future<List<DefinitionResource>> listDefinition(
          {String language: defaultLanguage}) =>
      _runRequestSession<List<DefinitionResource>>(
          (s) async => (await api.listDefinitions(s))
              .map((r) => new DefinitionResource()..loadRow(r, s.data))
              .toList(),
          [language]);

  @ApiMethod(path: 'difference/resolve', method: 'POST')
  Future<api.DifferenceBranch> resolveExpressionDifference(
          api.DifferenceBranch body) =>
      _runRequestSession<api.DifferenceBranch>(
          (s) => api.resolveExpressionDifference(s, body));

  @ApiMethod(path: 'proof/create', method: 'POST')
  Future<ProofResource> createProof(api.ProofData body) =>
      _runRequestSession<ProofResource>((s) async =>
          new ProofResource()..loadRow(await api.createProof(s, body), s.data));

  @ApiMethod(path: 'proof/list', method: 'GET')
  Future<List<ProofResource>> listProofs({String language: defaultLanguage}) =>
      _runRequestSession<List<ProofResource>>(
          (s) async => (await api.listProofs(s))
              .map((r) => new ProofResource()..loadRow(r, s.data))
              .toList(),
          [language]);

  @ApiMethod(path: 'proof/{id}/steps/list', method: 'GET')
  Future<List<StepResource>> listProofSteps(int id) =>
      _runRequestSession<List<StepResource>>((s) async =>
          (await api.listProofSteps(s, id))
              .map((r) => new StepResource()..loadRow(r, s.data))
              .toList());
}

/// Utility to reuse method calling boilerplate.
Future<T> _runSandboxed<T>(Future<T> handler(Connection conn), Pool pool) {
  final completer = new Completer<T>();

  // Get connection.
  pool.connect()
    ..then((conn) {
      T result;

      // Run in a transaction.
      conn.runInTransaction(() async {
        result = await handler(conn);
      })
        // When the handler inside the transaction is completed:
        ..then((_) {
          conn.close();
          completer.complete(result);
        })
        // When an error occurs during the completion of the handler:
        ..catchError((error, stackTrace) {
          conn.close();
          completer.completeError(error, stackTrace);
        });
    })
    // When an error occurs when obtaining a connection from the pool:
    ..catchError(completer.completeError);

  return completer.future;
}
