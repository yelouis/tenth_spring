import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:companion/explore/explore_service.dart';
import 'package:companion/explore/grid.dart';
import 'package:companion/explore/places_pack.dart';
import 'package:companion/main.dart';
import 'package:companion/outbox/database.dart';

File _resolveFixtureFile() {
  final candidates = [
    File('../game/tests/fixtures/places_pack_fixture.json.gz'),
    File('game/tests/fixtures/places_pack_fixture.json.gz'),
  ];
  for (final f in candidates) {
    if (f.existsSync()) return f;
  }
  throw StateError('Could not locate places_pack_fixture.json.gz');
}

class _FakeWidgetPositionSource implements PositionSource {
  Position nextPosition;

  _FakeWidgetPositionSource(this.nextPosition);

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;

  @override
  Future<LocationPermission> requestPermission() async =>
      LocationPermission.whileInUse;

  @override
  Future<Position> getCurrentPosition() async => nextPosition;

  @override
  Future<bool> openAppSettings() async => true;
}

void main() {
  testWidgets(
      'Explore Here big button is on the first screen and a tap shows the result card (§3.7)',
      (WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());

    final pack = PlacesPack.loadFile(_resolveFixtureFile().path);
    final center = Grid.cellCenterWm(4, 2); // Old Town in Fixture City
    final ll = Grid.wmToLatlon(center.x, center.y);

    final fakePos = _FakeWidgetPositionSource(
      Position(
        latitude: ll.lat,
        longitude: ll.lon,
        timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true),
        accuracy: 8.0,
        altitude: 0.0,
        altitudeAccuracy: 1.0,
        heading: 0.0,
        headingAccuracy: 1.0,
        speed: 0.0,
        speedAccuracy: 1.0,
      ),
    );

    await tester.pumpWidget(
      CompanionApp(
        database: db,
        initialPack: pack,
        positionSource: fakePos,
      ),
    );
    await tester.pumpAndSettle();

    // Big button is on the first screen
    expect(find.byKey(const Key('explore_here_button')), findsOneWidget);
    expect(find.text('Explore Here'), findsOneWidget);
    expect(find.text('0 discoveries waiting'), findsOneWidget);
    expect(find.byKey(const Key('explore_result_card')), findsNothing);

    // Tap Explore Here
    await tester.tap(find.byKey(const Key('explore_here_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    // Result card appears with the exact §3.3 message and pending count increments
    expect(find.byKey(const Key('explore_result_card')), findsOneWidget);
    expect(
      find.text(
        'New neighbourhood — Old Town, Fixture City! 1 of 2 to reveal the whole city.',
      ),
      findsOneWidget,
    );
    expect(find.text('1 discoveries waiting'), findsOneWidget);
  });
}
