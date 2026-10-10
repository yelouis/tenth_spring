import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:companion/main.dart';
import 'package:companion/capture/location_source.dart';
import 'package:companion/capture/gpx_replay_source.dart';
import 'package:companion/capture/fuzz.dart';
import 'package:companion/outbox/database.dart';
import 'package:companion/ui/scout_ledger_screen.dart';

class _FakeLocationSource implements LocationSource {
  final _controller = StreamController<Fix>.broadcast();
  Fix? nextCurrentFix;

  @override
  Stream<Fix> fixes() => _controller.stream;

  @override
  Stream<OsVisit>? nativeVisits() => null;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<Fix?> currentFix() async => nextCurrentFix;

  void emit(Fix fix) {
    _controller.add(fix);
  }

  void dispose() {
    _controller.close();
  }
}

void main() {
  testWidgets('Scout Ledger UI renders correctly', (WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());

    await tester.pumpWidget(CompanionApp(database: db));
    await tester.pumpAndSettle();

    expect(find.text('Tenth Spring Scout Ledger'), findsOneWidget);
    expect(find.text('0 places scouted today'), findsOneWidget);
    expect(find.text('Sync at your PC to add them to your map.'), findsOneWidget);
  });

  testWidgets('Scout here uses fresh one-shot fix instead of cached fix (F36)',
      (WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());

    final fakeSource = _FakeLocationSource();
    addTearDown(fakeSource.dispose);

    await tester.pumpWidget(MaterialApp(
      home: ScoutLedgerScreen(
        database: db,
        locationSource: fakeSource,
      ),
    ));
    await tester.pumpAndSettle();

    // Stream emits fix A (cached / stream fix)
    const fixA = Fix(lat: 37.700, lon: -122.400, accuracyM: 10, tsUtcMs: 1000);
    fakeSource.emit(fixA);
    await tester.pump();

    // Current location returns fresh fix B
    const fixB = Fix(lat: 37.800, lon: -122.500, accuracyM: 10, tsUtcMs: 9000);
    fakeSource.nextCurrentFix = fixB;

    // Tap Scout Here
    await tester.tap(find.text('Scout Here'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final visits = await db.getAllVisits();
    expect(visits.length, 1);
    expect(visits.first.startedAt, 9000);

    final expectedP = fuzzPoint(37.800, -122.500);
    expect(visits.first.lat, expectedP.lat);
    expect(visits.first.lon, expectedP.lon);
    expect(find.text('Scouted a location near you'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets(
      'Scout here falls back to nothing when currentFix is null and shows exact SnackBar (F36)',
      (WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());

    final fakeSource = _FakeLocationSource();
    addTearDown(fakeSource.dispose);

    await tester.pumpWidget(MaterialApp(
      home: ScoutLedgerScreen(
        database: db,
        locationSource: fakeSource,
      ),
    ));
    await tester.pumpAndSettle();

    // Stream emits fix A
    const fixA = Fix(lat: 37.700, lon: -122.400, accuracyM: 10, tsUtcMs: 1000);
    fakeSource.emit(fixA);
    await tester.pump();

    // currentFix returns null
    fakeSource.nextCurrentFix = null;

    // Tap Scout Here
    await tester.tap(find.text('Scout Here'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final visits = await db.getAllVisits();
    expect(visits.isEmpty, true);
    expect(
      find.text("Couldn't find your location — try again in a moment."),
      findsOneWidget,
    );
    await tester.pumpAndSettle();
  });

  test('GpxReplaySource currentFix is null before replay and last emitted fix after (F36)',
      () async {
    const gpxSample = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1">
  <trk>
    <trkseg>
      <trkpt lat="37.7749" lon="-122.4194">
        <time>2026-10-10T12:00:00Z</time>
      </trkpt>
      <trkpt lat="37.7750" lon="-122.4195">
        <time>2026-10-10T12:01:00Z</time>
      </trkpt>
    </trkseg>
  </trk>
</gpx>''';

    final replaySource = GpxReplaySource(gpxSample, instant: true);
    addTearDown(replaySource.dispose);

    // Null before replay
    expect(await replaySource.currentFix(), isNull);

    // Run replay
    await replaySource.start();

    // Contains last emitted fix
    final lastFix = await replaySource.currentFix();
    expect(lastFix, isNotNull);
    expect(lastFix!.lat, 37.7750);
    expect(lastFix.lon, -122.4195);
  });
}
