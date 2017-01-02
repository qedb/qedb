// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqpg;

class DbConnection {
  final String _dbHost, _dbName, _dbUser, _dbPass;
  final int _dbPort;

  DbConnection(
      this._dbHost, this._dbPort, this._dbName, this._dbUser, this._dbPass);

  Future<PostgreSQLConnection> create() async {
    final connection = new PostgreSQLConnection(_dbHost, _dbPort, _dbName,
        username: _dbUser, password: _dbPass);
    await connection.open();
    return connection;
  }
}

class DbPool {
  final DbConnection _connection;
  int connectionSpace;
  final available = new List<PostgreSQLConnection>();

  DbPool(this._connection, this.connectionSpace);

  Future<List<List>> query(String fmtString,
      [Map<String, dynamic> substitutionValues = null]) async {
    // If maxConnections are occupied, throw an error.
    if (connectionSpace == 0 && available.isEmpty) {
      throw new RpcError(503, 'database_busy', 'database is busy');
    } else {
      PostgreSQLConnection connection;
      if (available.isNotEmpty) {
        connection = available.removeLast();
      } else {
        connectionSpace--;
        connection = await _connection.create();
      }

      try {
        final data = await connection.query(fmtString,
            substitutionValues: substitutionValues);
        available.add(connection);
        return data;
      } catch (e) {
        // Close connection, just in case.
        if (connection != null) {
          connection.close();
        }

        connectionSpace++;
        throw new RpcError(500, 'query_error', 'failed to execute query')
          ..errors.add(new RpcErrorDetail(message: e.toString()));
      }
    }
  }
}
