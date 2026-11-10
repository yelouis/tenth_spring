import 'dart:io';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:companion/explore/explore_store.dart';

void main() {
  group('ExploreStore Drift schema v2 (§3.2, §3.7)', () {
    test('falsifying schema reflection: no table in AppDatabase has a RealColumn',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() => db.close());

      // Force schema creation
      await db.getAllExploredAreas();

      expect(db.allTables, isNotEmpty);
      for (final table in db.allTables) {
        for (final col in table.$columns) {
          expect(
            col.type,
            isNot(equals(DriftSqlType.double)),
            reason:
                'Table ${table.actualTableName} column ${col.$name} must not be REAL/double',
          );
          expect(
            col,
            isNot(isA<GeneratedColumn<double>>()),
            reason:
                'Table ${table.actualTableName} column ${col.$name} must not be GeneratedColumn<double>',
          );
        }
      }

      // Also verify directly against SQLite PRAGMA table_info
      final tables = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';",
          )
          .get();
      expect(tables, isNotEmpty);
      for (final tRow in tables) {
        final tName = tRow.read<String>('name');
        final cols = await db.customSelect('PRAGMA table_info("$tName");').get();
        for (final cRow in cols) {
          final colName = cRow.read<String>('name');
          final colType = cRow.read<String>('type').toUpperCase();
          expect(
            colType.contains('REAL') ||
                colType.contains('DOUBLE') ||
                colType.contains('FLOA'),
            isFalse,
            reason: 'SQLite table $tName column $colName has real type $colType',
          );
        }
      }
    });

    test('v1 -> v2 migration drops visit_outbox and preserves meta_table',
        () async {
      final tempDir = Directory.systemTemp.createTempSync('companion_mig_test_');
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      final dbFile = File('${tempDir.path}/outbox_v1.sqlite');

      // Open with v2 AppDatabase on a pre-seeded v1 SQLite database so onUpgrade(m, 1, 2) runs
      final migratedDb = AppDatabase(
        NativeDatabase(
          dbFile,
          setup: (rawDb) {
            rawDb.execute('''
              CREATE TABLE visit_outbox (
                seq INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
                kind TEXT NOT NULL,
                lat REAL NOT NULL,
                lon REAL NOT NULL,
                started_at INTEGER NOT NULL,
                dwell_seconds INTEGER NULL,
                synced INTEGER NOT NULL DEFAULT 0
              );
            ''');
            rawDb.execute('''
              CREATE TABLE meta_table (
                key TEXT NOT NULL PRIMARY KEY,
                value TEXT NOT NULL
              );
            ''');
            rawDb.execute(
              "INSERT INTO visit_outbox (kind, lat, lon, started_at) VALUES ('visit', 38.89, -77.03, 1700000000000);",
            );
            rawDb.execute(
              "INSERT INTO meta_table (key, value) VALUES ('legacy_key', 'kept');",
            );
            rawDb.execute('PRAGMA user_version = 1;');
          },
        ),
      );
      addTearDown(() => migratedDb.close());

      // Trigger migration
      expect(await migratedDb.getMeta('legacy_key'), equals('kept'));

      // Verify visit_outbox is dropped completely
      final checkOld = await migratedDb
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='visit_outbox';",
          )
          .get();
      expect(checkOld, isEmpty);

      // Verify v2 tables exist and work
      await migratedDb.recordExploreUnlock(
        areaKey: 'osm:n9104',
        placeId: 'city:fixture-city',
        tsUtcMs: 1700000005000,
        packVersion: 1,
      );
      expect((await migratedDb.getAllExploredAreas()).length, equals(1));
      expect((await migratedDb.getAllOutboxItems()).length, equals(1));
    });
  });
}
