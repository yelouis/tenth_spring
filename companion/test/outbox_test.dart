import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:companion/outbox/database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('Outbox stores visits and generates auto-incrementing seq', () async {
    final id1 = await db.insertVisit(
      kind: 'visit',
      lat: 37.775,
      lon: -122.419,
      startedAt: 1000000,
      dwellSeconds: 150,
    );

    final id2 = await db.insertVisit(
      kind: 'corridor',
      lat: 37.776,
      lon: -122.420,
      startedAt: 1000100,
    );

    expect(id1, equals(1));
    expect(id2, equals(2));

    final unsynced = await db.getUnsyncedVisits();
    expect(unsynced.length, equals(2));
    expect(unsynced.first.seq, equals(1));
    expect(unsynced.first.kind, equals('visit'));
    expect(unsynced.last.seq, equals(2));
    expect(unsynced.last.kind, equals('corridor'));
  });

  test('markSyncedUpTo and deleteSyncedUpTo behave correctly', () async {
    await db.insertVisit(
      kind: 'visit',
      lat: 37.775,
      lon: -122.419,
      startedAt: 1000000,
      dwellSeconds: 150,
    );
    await db.insertVisit(
      kind: 'visit',
      lat: 37.776,
      lon: -122.420,
      startedAt: 1000200,
      dwellSeconds: 200,
    );

    await db.markSyncedUpTo(1);
    final unsynced = await db.getUnsyncedVisits();
    expect(unsynced.length, equals(1));
    expect(unsynced.first.seq, equals(2));

    await db.deleteSyncedUpTo(1);
    final allVisits = await db.getAllVisits();
    expect(allVisits.length, equals(1));
    expect(allVisits.first.seq, equals(2));
  });
}
