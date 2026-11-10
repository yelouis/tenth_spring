import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

part 'explore_store.g.dart';

@DataClassName('ExploredAreaRow')
class ExploredArea extends Table {
  TextColumn get areaKey => text()();
  TextColumn get placeId => text()();
  IntColumn get firstAtMs => integer()();
  BoolColumn get starter => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {areaKey};
}

@DataClassName('ExploreOutboxItem')
class ExploreOutbox extends Table {
  IntColumn get seq => integer().autoIncrement()();
  TextColumn get kind => text()(); // 'explore' or 'home'
  TextColumn get placeId => text()();
  TextColumn get areaKey => text().nullable()();
  IntColumn get tsUtcMs => integer()();
}

@DataClassName('Meta')
class MetaTable extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

typedef ExploreStore = AppDatabase;

@DriftDatabase(tables: [ExploredArea, ExploreOutbox, MetaTable])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? e]) : super(e ?? _openConnection());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
        },
        onUpgrade: (Migrator m, int from, int to) async {
          if (from < 2) {
            await customStatement('DROP TABLE IF EXISTS visit_outbox;');
            await m.createTable(exploredArea);
            await m.createTable(exploreOutbox);
            await customStatement(
              'CREATE TABLE IF NOT EXISTS meta_table (key TEXT NOT NULL PRIMARY KEY, value TEXT NOT NULL);',
            );
          }
        },
      );

  Future<bool> isAreaExplored(String key) async {
    final row = await (select(exploredArea)
          ..where((t) => t.areaKey.equals(key))
          ..limit(1))
        .getSingleOrNull();
    return row != null;
  }

  Future<List<ExploredAreaRow>> getExploredAreasForPlace(String pid) {
    return (select(exploredArea)
          ..where((t) => t.placeId.equals(pid))
          ..orderBy([(t) => OrderingTerm(expression: t.firstAtMs)]))
        .get();
  }

  Future<List<ExploredAreaRow>> getAllExploredAreas() {
    return (select(exploredArea)
          ..orderBy([(t) => OrderingTerm(expression: t.firstAtMs)]))
        .get();
  }

  Future<int> countExploredAreasForPlace(String pid) async {
    final rows = await getExploredAreasForPlace(pid);
    return rows.length;
  }

  Future<int> insertExploreOutbox({
    required String kind,
    required String placeId,
    String? areaKey,
    required int tsUtcMs,
  }) {
    return into(exploreOutbox).insert(
      ExploreOutboxCompanion.insert(
        kind: kind,
        placeId: placeId,
        areaKey: Value(areaKey),
        tsUtcMs: tsUtcMs,
      ),
    );
  }

  Future<List<ExploreOutboxItem>> getPendingOutbox({int limit = 500}) {
    return (select(exploreOutbox)
          ..orderBy([
            (t) => OrderingTerm(expression: t.seq, mode: OrderingMode.asc),
          ])
          ..limit(limit))
        .get();
  }

  Future<List<ExploreOutboxItem>> getAllOutboxItems() {
    return (select(exploreOutbox)
          ..orderBy([
            (t) => OrderingTerm(expression: t.seq, mode: OrderingMode.asc),
          ]))
        .get();
  }

  Future<int> deleteSyncedUpTo(int maxSeq) {
    return (delete(exploreOutbox)
          ..where((t) => t.seq.isSmallerOrEqualValue(maxSeq)))
        .go();
  }

  Future<String?> getMeta(String k) async {
    final row = await (select(metaTable)
          ..where((t) => t.key.equals(k))
          ..limit(1))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> setMeta(String k, String v) async {
    await into(metaTable).insertOnConflictUpdate(
      MetaTableCompanion.insert(key: k, value: v),
    );
  }

  Future<String?> getStarterPlaceId() => getMeta('starter_place_id');

  Future<void> setStarterPlaceId(String placeId) =>
      setMeta('starter_place_id', placeId);

  Future<String?> getPackVersion() => getMeta('pack_version');

  Future<void> setPackVersion(int version) =>
      setMeta('pack_version', version.toString());

  Future<void> recordExploreUnlock({
    required String areaKey,
    required String placeId,
    required int tsUtcMs,
    required int packVersion,
  }) async {
    await into(exploredArea).insert(
      ExploredAreaCompanion.insert(
        areaKey: areaKey,
        placeId: placeId,
        firstAtMs: tsUtcMs,
        starter: const Value(false),
      ),
      mode: InsertMode.insertOrIgnore,
    );
    await into(exploreOutbox).insert(
      ExploreOutboxCompanion.insert(
        kind: 'explore',
        placeId: placeId,
        areaKey: Value(areaKey),
        tsUtcMs: tsUtcMs,
      ),
    );
    await setPackVersion(packVersion);
  }

  Future<void> recordSetHome({
    required String cityId,
    required String? waypostAreaKey,
    required int tsUtcMs,
    required int packVersion,
  }) async {
    await setStarterPlaceId(cityId);
    await setPackVersion(packVersion);
    if (waypostAreaKey != null && waypostAreaKey.isNotEmpty) {
      await into(exploredArea).insert(
        ExploredAreaCompanion.insert(
          areaKey: waypostAreaKey,
          placeId: cityId,
          firstAtMs: tsUtcMs,
          starter: const Value(true),
        ),
        mode: InsertMode.insertOrIgnore,
      );
    }
    await into(exploreOutbox).insert(
      ExploreOutboxCompanion.insert(
        kind: 'home',
        placeId: cityId,
        areaKey: const Value(null),
        tsUtcMs: tsUtcMs,
      ),
    );
  }

  Future<void> eraseAll() async {
    await transaction(() async {
      await delete(exploredArea).go();
      await delete(exploreOutbox).go();
      await delete(metaTable).go();
    });
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'companion_outbox.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
