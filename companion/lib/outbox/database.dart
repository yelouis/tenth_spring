import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

part 'database.g.dart';

@DataClassName('VisitOutboxItem')
class VisitOutbox extends Table {
  IntColumn get seq => integer().autoIncrement()();
  TextColumn get kind => text()(); // 'visit' or 'corridor'
  RealColumn get lat => real()(); // fuzzed lat
  RealColumn get lon => real()(); // fuzzed lon
  IntColumn get startedAt => integer()(); // UTC ms
  IntColumn get dwellSeconds => integer().nullable()(); // visits only
  IntColumn get synced => integer().withDefault(const Constant(0))();
}

@DataClassName('Meta')
class MetaTable extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [VisitOutbox, MetaTable])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? e]) : super(e ?? _openConnection());

  @override
  int get schemaVersion => 1;

  Future<int> insertVisit({
    required String kind,
    required double lat,
    required double lon,
    required int startedAt,
    int? dwellSeconds,
  }) {
    return into(visitOutbox).insert(VisitOutboxCompanion.insert(
      kind: kind,
      lat: lat,
      lon: lon,
      startedAt: startedAt,
      dwellSeconds: Value(dwellSeconds),
    ));
  }

  Future<List<VisitOutboxItem>> getUnsyncedVisits() {
    return (select(visitOutbox)..where((t) => t.synced.equals(0))).get();
  }

  Future<List<VisitOutboxItem>> getAllVisits() {
    return select(visitOutbox).get();
  }

  Future<int> markSyncedUpTo(int maxSeq) {
    return (update(visitOutbox)..where((t) => t.seq.isSmallerOrEqualValue(maxSeq)))
        .write(const VisitOutboxCompanion(synced: Value(1)));
  }

  Future<int> deleteSyncedUpTo(int maxSeq) {
    return (delete(visitOutbox)..where((t) => t.seq.isSmallerOrEqualValue(maxSeq)))
        .go();
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'companion_outbox.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
