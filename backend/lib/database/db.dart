import 'dart:io';

import 'package:parkshare_backend/config/config.dart';
import 'package:postgres/postgres.dart';

/// PostgreSQL connection pool and migration runner.
class Db {
  static Pool? _pool;

  static Pool get pool {
    final p = _pool;
    if (p == null) {
      throw StateError('Database not initialized. Call Db.init() first.');
    }
    return p;
  }

  static Future<void> init() async {
    if (_pool != null) return;
    _pool = Pool.withEndpoints([
      Endpoint(
        host: Config.dbHost,
        port: Config.dbPort,
        database: Config.dbName,
        username: Config.dbUser,
        password: Config.dbPassword,
      ),
    ], settings: const PoolSettings(sslMode: SslMode.disable));
    // Verify connectivity on startup.
    await pool.withConnection((c) async {
      await c.execute('SELECT 1');
    });
    print(
      'Database connection verified (${Config.dbHost}:${Config.dbPort}/${Config.dbName})',
    );
  }

  static Future<void> close() async {
    await _pool?.close();
    _pool = null;
  }

  /// Applies `sql/migrations/*.sql` in filename order, tracking applied
  /// versions in the `schema_migrations` table. Idempotent.
  static Future<void> migrate() async {
    final migrationsDir = Directory('sql/migrations');
    if (!migrationsDir.existsSync()) {
      print('No sql/migrations directory found; skipping migrations.');
      return;
    }
    final files =
        migrationsDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.sql'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    await pool.withConnection((conn) async {
      await conn.execute('''
        CREATE TABLE IF NOT EXISTS schema_migrations (
          version TEXT PRIMARY KEY,
          applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )
      ''');
      for (final file in files) {
        final version = file.uri.pathSegments.last;
        final applied = await conn.execute(
          Sql.named('SELECT 1 FROM schema_migrations WHERE version = @v'),
          parameters: {'v': version},
        );
        if (applied.isNotEmpty) {
          print('Migration already applied: $version');
          continue;
        }
        final sql = file.readAsStringSync();
        await conn.runTx((tx) async {
          for (final statement in _splitStatements(sql)) {
            if (statement.trim().isEmpty) continue;
            await tx.execute(statement);
          }
          await tx.execute(
            Sql.named('INSERT INTO schema_migrations (version) VALUES (@v)'),
            parameters: {'v': version},
          );
        });
        print('Migration applied: $version');
      }
    });
  }

  /// Very small SQL statement splitter that splits on `;` at end of lines.
  /// Sufficient for our plain DDL migrations (no procedural blocks).
  static List<String> _splitStatements(String sql) {
    final statements = <String>[];
    final buffer = StringBuffer();
    for (final line in sql.split('\n')) {
      buffer.writeln(line);
      final trimmed = line.trim();
      if (trimmed.endsWith(';')) {
        statements.add(buffer.toString());
        buffer.clear();
      }
    }
    if (buffer.isNotEmpty && buffer.toString().trim().isNotEmpty) {
      statements.add(buffer.toString());
    }
    return statements;
  }
}
