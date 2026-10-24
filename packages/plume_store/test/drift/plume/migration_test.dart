// Schema and migration tests. The dumps in drift_schemas/plume/ and the
// helpers in generated/ are produced by `dart run drift_dev make-migrations`
// (run it after every schema change, together with a schemaVersion bump).
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:plume_store/plume_store.dart';
import 'package:test/test.dart';

import 'generated/schema.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;
  final latest = PlumeDatabase.memory().schemaVersion;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper(), setup: configureConnection));

  test('the latest schema has been dumped', () {
    expect(
      GeneratedHelper.versions.last,
      latest,
      reason: 'Run `dart run drift_dev make-migrations` after changing the schema.',
    );
  });

  test('a new database matches the dumped schema', () async {
    final db = PlumeDatabase(NativeDatabase.memory(setup: configureConnection));
    await verifier.migrateAndValidate(db, latest);
    await db.validateDatabaseSchema(setup: configureConnection);
    await db.close();
  });

  for (final from in GeneratedHelper.versions.where((v) => v < latest)) {
    test('upgrades from v$from to v$latest', () async {
      final schema = await verifier.schemaAt(from);
      final db = PlumeDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, latest);
      await db.close();
    });
  }

  test('a database written by a newer version is refused', () async {
    final schema = await verifier.schemaAt(latest);
    schema.rawDatabase.execute('PRAGMA user_version = ${latest + 1}');
    final db = PlumeDatabase(schema.newConnection());
    await expectLater(db.customSelect('SELECT 1').get(), throwsA(isA<UnsupportedError>()));
    await db.close();
  });
}
