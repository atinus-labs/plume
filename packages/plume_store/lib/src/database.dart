import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:logging/logging.dart';
import 'package:sqlite3/sqlite3.dart' show Database;

import 'database.steps.dart';
import 'sql_functions.dart';

part 'database.g.dart';

final _log = Logger('plume_store');

/// Per-connection setup: pragmas and application-defined functions. Runs in
/// the isolate that owns the connection (it is sent to background isolates,
/// so it must stay a top-level function without captured state).
void configureConnection(Database db) {
  db.execute('PRAGMA busy_timeout = 5000;');
  db.execute('PRAGMA journal_mode = WAL;');
  db.execute('PRAGMA synchronous = NORMAL;');
  db.execute('PRAGMA temp_store = MEMORY;');
  db.execute('PRAGMA cache_size = -16000;');
  db.execute('PRAGMA mmap_size = 268435456;');
  db.execute('PRAGMA journal_size_limit = 67108864;');
  registerPlumeFunctions(db);
}

/// A schema migration from version `v` to `v + 1`.
typedef _MigrationStep = Future<void> Function(Migrator m, PlumeDatabase db);

/// The Plume SQLite database. Schema in `schema.drift`.
@DriftDatabase(include: {'schema.drift'})
class PlumeDatabase extends _$PlumeDatabase {
  /// Wraps an existing executor. Pass an executor whose connections were set
  /// up with [configureConnection].
  PlumeDatabase(super.e);

  /// Opens (creating if needed) the database at [file]. SQLite runs on a
  /// background isolate in WAL mode; [readPool] additional reader isolates
  /// let UI queries proceed while a sync transaction is writing.
  factory PlumeDatabase.open(File file, {int readPool = 2, bool logStatements = false}) {
    file.parent.createSync(recursive: true);
    return PlumeDatabase(
      NativeDatabase.createInBackground(
        file,
        setup: configureConnection,
        readPool: readPool,
        logStatements: logStatements,
      ),
    );
  }

  /// A private in-memory database (tests, previews).
  factory PlumeDatabase.memory({bool logStatements = false}) =>
      PlumeDatabase(NativeDatabase.memory(setup: configureConnection, logStatements: logStatements));

  @override
  int get schemaVersion => 3;

  /// Migration steps keyed by the version they upgrade from. When bumping
  /// [schemaVersion]: edit `schema.drift`, run
  /// `dart run drift_dev make-migrations`, then add the step here (the
  /// generated `database.steps.dart` provides typed per-version schemas via
  /// `stepByStep`) and extend the generated migration test.
  static final Map<int, _MigrationStep> _steps = {
    1: (m, db) async {
      final v2 = Schema2(database: db);
      await m.addColumn(v2.accounts, v2.accounts.providerConfig);
    },
    2: (m, db) async {
      final v3 = Schema3(database: db);
      await m.createTable(v3.localDrafts);
      await m.createIndex(v3.localDraftsByAccount);
    },
  };

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => transaction(() => m.createAll()),
    onUpgrade: (m, from, to) async {
      if (from > to) {
        throw UnsupportedError(
          'The mail database (schema v$from) was written by a newer version of Plume '
          'than this one (schema v$to).',
        );
      }
      _log.info('Migrating mail database from schema v$from to v$to');
      // Table rebuilds need foreign keys off; this pragma is a no-op
      // inside a transaction, so it is set before starting one.
      await customStatement('PRAGMA foreign_keys = OFF');
      await transaction(() async {
        for (var v = from; v < to; v++) {
          final step = _steps[v];
          if (step == null) throw StateError('No migration from schema v$v to v${v + 1}');
          await step(m, this);
        }
        final broken = await customSelect('PRAGMA foreign_key_check').get();
        if (broken.isNotEmpty) {
          throw StateError(
            'Migration left ${broken.length} foreign key violations: '
            '${broken.take(5).map((r) => r.data).join(', ')}',
          );
        }
      });
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
