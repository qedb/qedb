// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqpg;

class DbConnection {
  final String _dbHost, _dbName, _dbUser, _dbPass;
  final int _dbPort;

  DbConnection(
      this._dbHost, this._dbPort, this._dbName, this._dbUser, this._dbPass);

  PostgreSQLConnection create() =>
      new PostgreSQLConnection(_dbHost, _dbPort, _dbName,
          username: _dbUser, password: _dbPass);
}

class DbPool {
  final DbConnection _connection;
  final int maxConnections;
  final available = new List<PostgreSQLConnection>();
  final occupied = new List<PostgreSQLConnection>();

  DbPool(this._connection, this.maxConnections);

  Future<List<List>> query(String fmtString,
      {Map<String, dynamic> substitutionValues: null}) async {
    // If maxConnections are occupied, throw an error.
    if (occupied.length == maxConnections) {
      throw new RpcError(503, 'database_busy', 'database is busy');
    } else {
      final connection =
          available.isNotEmpty ? available.removeLast() : _connection.create();
      try {
        final data = await connection.query(fmtString);
        available.add(connection);
        return data;
      } catch (e) {
        // Close connection, just in case.
        connection.close();
        throw new RpcError(500, 'query_error', 'failed to execute query');
      }
    }
  }
}
