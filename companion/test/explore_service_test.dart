import 'dart:async';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:companion/explore/explore_service.dart';
import 'package:companion/explore/explore_store.dart';
import 'package:companion/explore/grid.dart';
import 'package:companion/explore/places_pack.dart';

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

Position _makePosition({
  required double lat,
  required double lon,
  double accuracy = 12.0,
}) {
  return Position(
    latitude: lat,
    longitude: lon,
    timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true),
    accuracy: accuracy,
    altitude: 0.0,
    altitudeAccuracy: 1.0,
    heading: 0.0,
    headingAccuracy: 1.0,
    speed: 0.0,
    speedAccuracy: 1.0,
  );
}

({double lat, double lon}) _latLonForCell(int cx, int cy) {
  final center = Grid.cellCenterWm(cx, cy);
  return Grid.wmToLatlon(center.x, center.y);
}

class FakePositionSource implements PositionSource {
  LocationPermission permission;
  LocationPermission permissionAfterRequest;
  Position? nextPosition;
  Object? nextError;
  int requestPermissionCalls = 0;
  int openSettingsCalls = 0;

  FakePositionSource({
    this.permission = LocationPermission.whileInUse,
    this.permissionAfterRequest = LocationPermission.whileInUse,
    this.nextPosition,
    this.nextError,
  });

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async {
    requestPermissionCalls++;
    permission = permissionAfterRequest;
    return permission;
  }

  @override
  Future<Position> getCurrentPosition() async {
    if (nextError != null) {
      throw nextError!;
    }
    return nextPosition!;
  }

  @override
  Future<bool> openAppSettings() async {
    openSettingsCalls++;
    return true;
  }
}

void main() {
  group('ExploreService (§3.3–§3.5)', () {
    late PlacesPack pack;
    late AppDatabase db;
    late FakePositionSource fakePos;
    late ExploreService service;
    int nowClock = 1700000000000;
    int vibrateCalls = 0;

    setUpAll(() {
      pack = PlacesPack.loadFile(_resolveFixtureFile().path);
    });

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      fakePos = FakePositionSource();
      nowClock = 1700000000000;
      vibrateCalls = 0;
      service = ExploreService(
        store: db,
        pack: pack,
        positionSource: fakePos,
        clockMs: () => nowClock += 1000,
        vibrate: () async {
          vibrateCalls++;
        },
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('permission denied after single request records nothing and returns exact copy',
        () async {
      fakePos.permission = LocationPermission.denied;
      fakePos.permissionAfterRequest = LocationPermission.denied;

      final res = await service.exploreHere();
      expect(fakePos.requestPermissionCalls, equals(1));
      expect(res.kind, equals(ExploreOutcomeKind.permissionDenied));
      expect(res.permissionDenied, isTrue);
      expect(res.unlockedNew, isFalse);
      expect(
        res.message,
        equals(
          'Explore Here needs your location once, only when you tap. You can allow it in Settings.',
        ),
      );
      expect(await db.getAllExploredAreas(), isEmpty);
      expect(await db.getAllOutboxItems(), isEmpty);
    });

    test('timeout records nothing and returns exact copy', () async {
      fakePos.nextError = TimeoutException('GPS timeout');

      final res = await service.exploreHere();
      expect(res.kind, equals(ExploreOutcomeKind.timeout));
      expect(res.unlockedNew, isFalse);
      expect(
        res.message,
        equals("Couldn't find your location — try again in the open."),
      );
      expect(await db.getAllExploredAreas(), isEmpty);
      expect(await db.getAllOutboxItems(), isEmpty);
    });

    test('fuzzy reading (accuracy > 100 m) records nothing and returns exact copy',
        () async {
      final ll = _latLonForCell(4, 2); // Inside Old Town
      fakePos.nextPosition = _makePosition(
        lat: ll.lat,
        lon: ll.lon,
        accuracy: 100.5,
      );

      final res = await service.exploreHere();
      expect(res.kind, equals(ExploreOutcomeKind.fuzzy));
      expect(res.unlockedNew, isFalse);
      expect(
        res.message,
        equals('Your location is too fuzzy here — try again in the open.'),
      );
      expect(await db.getAllExploredAreas(), isEmpty);
      expect(await db.getAllOutboxItems(), isEmpty);
    });

    test('not in any place records nothing and returns exact copy', () async {
      final ll = _latLonForCell(50, 50); // Outside all places
      fakePos.nextPosition = _makePosition(lat: ll.lat, lon: ll.lon);

      final res = await service.exploreHere();
      expect(res.kind, equals(ExploreOutcomeKind.notInAnyPlace));
      expect(res.unlockedNew, isFalse);
      expect(
        res.message,
        equals(
          "This spot isn't on Tenth Spring's map. The map covers 27 famous cities and 60 parks and wonders.",
        ),
      );
      expect(await db.getAllExploredAreas(), isEmpty);
      expect(await db.getAllOutboxItems(), isEmpty);
    });

    test(
        'city neighbourhood flow: 1st area, already explored, 2nd area reaches T, 3rd area does not repeat threshold message',
        () async {
      // 1. Explore Old Town (cell 4, 2) -> k = 1, T = 2
      final oldTownLl = _latLonForCell(4, 2);
      fakePos.nextPosition = _makePosition(lat: oldTownLl.lat, lon: oldTownLl.lon);
      final res1 = await service.exploreHere();
      expect(res1.kind, equals(ExploreOutcomeKind.newNeighbourhood));
      expect(res1.unlockedNew, isTrue);
      expect(
        res1.message,
        equals(
          'New neighbourhood — Old Town, Fixture City! 1 of 2 to reveal the whole city.',
        ),
      );
      expect(vibrateCalls, equals(1));
      expect((await db.getAllExploredAreas()).length, equals(1));
      expect((await db.getAllOutboxItems()).length, equals(1));

      // 2. Re-explore Old Town -> already explored, records nothing
      final resRepeat = await service.exploreHere();
      expect(resRepeat.kind, equals(ExploreOutcomeKind.alreadyExplored));
      expect(resRepeat.unlockedNew, isFalse);
      expect(
        resRepeat.message,
        equals(
          'Already explored — Old Town. 1 of 2 neighbourhoods explored in Fixture City.',
        ),
      );
      expect(vibrateCalls, equals(1));
      expect((await db.getAllExploredAreas()).length, equals(1));
      expect((await db.getAllOutboxItems()).length, equals(1));

      // 3. Explore Mill District (cell 2, 2) -> k = 2 == T = 2 -> threshold reached!
      final millLl = _latLonForCell(2, 2);
      fakePos.nextPosition = _makePosition(lat: millLl.lat, lon: millLl.lon);
      final res2 = await service.exploreHere();
      expect(res2.kind, equals(ExploreOutcomeKind.newNeighbourhoodCityRevealed));
      expect(res2.unlockedNew, isTrue);
      expect(
        res2.message,
        equals(
          'New neighbourhood — Mill District, Fixture City! 2 of 2 to reveal the whole city.\n'
          'City revealed — Fixture City! You can Distort there from home.',
        ),
      );
      expect((await db.getAllExploredAreas()).length, equals(2));
      expect((await db.getAllOutboxItems()).length, equals(2));

      // 4. Explore Riverside (cell 6, 2) -> k = 3 > T = 2 -> threshold message must NOT appear again!
      final riverLl = _latLonForCell(6, 2);
      fakePos.nextPosition = _makePosition(lat: riverLl.lat, lon: riverLl.lon);
      final res3 = await service.exploreHere();
      expect(res3.kind, equals(ExploreOutcomeKind.newNeighbourhood));
      expect(res3.unlockedNew, isTrue);
      expect(
        res3.message,
        equals(
          'New neighbourhood — Riverside, Fixture City! 3 of 2 to reveal the whole city.',
        ),
      );
      expect(res3.message.contains('City revealed —'), isFalse);
      expect((await db.getAllExploredAreas()).length, equals(3));
      expect((await db.getAllOutboxItems()).length, equals(3));
    });

    test('site flow: new park revealed and already-explored park records nothing',
        () async {
      final parkLl = _latLonForCell(10, 4);
      fakePos.nextPosition = _makePosition(lat: parkLl.lat, lon: parkLl.lon);

      final res1 = await service.exploreHere();
      expect(res1.kind, equals(ExploreOutcomeKind.newSiteRevealed));
      expect(res1.unlockedNew, isTrue);
      expect(
        res1.message,
        equals('Fixture Park revealed! You can Distort there from home.'),
      );
      expect((await db.getAllExploredAreas()).length, equals(1));
      expect((await db.getAllOutboxItems()).length, equals(1));

      // Second tap on the same park records nothing
      final res2 = await service.exploreHere();
      expect(res2.kind, equals(ExploreOutcomeKind.alreadyExplored));
      expect(res2.unlockedNew, isFalse);
      expect(res2.message, equals('Already explored — Fixture Park.'));
      expect((await db.getAllExploredAreas()).length, equals(1));
      expect((await db.getAllOutboxItems()).length, equals(1));
    });

    test(
        'setHome marks starter Waypost neighbourhood locally without queueing an explore row and queues only a home row',
        () async {
      // Point anywhere near Fixture City
      fakePos.nextPosition = _makePosition(lat: 0.05, lon: 0.05);

      final res = await service.setHome();
      expect(res.kind, equals(ExploreOutcomeKind.homeSet));
      expect(
        res.message,
        equals('Your starting city is Fixture City. Only its name is saved.'),
      );
      expect(await db.getStarterPlaceId(), equals('city:fixture-city'));

      // Starter Waypost is at (0.0103486, 0.0080489) -> cell (3, 4) -> osm:n9104 ("Old Town")
      final explored = await db.getAllExploredAreas();
      expect(explored.length, equals(1));
      expect(explored.first.areaKey, equals('osm:n9104'));
      expect(explored.first.placeId, equals('city:fixture-city'));
      expect(explored.first.starter, isTrue);

      // Outbox has ONLY the 'home' row, never the starter neighbourhood
      final outbox = await db.getAllOutboxItems();
      expect(outbox.length, equals(1));
      expect(outbox.first.kind, equals('home'));
      expect(outbox.first.placeId, equals('city:fixture-city'));
      expect(outbox.first.areaKey, isNull);

      // Exploring one more neighbourhood in Fixture City (Mill District) reaches T=2 because k counts the starter Waypost neighbourhood (§3.3)
      final millLl = _latLonForCell(2, 2);
      fakePos.nextPosition = _makePosition(lat: millLl.lat, lon: millLl.lon);
      final resExplore = await service.exploreHere();
      expect(
        resExplore.kind,
        equals(ExploreOutcomeKind.newNeighbourhoodCityRevealed),
      );
      expect(resExplore.exploredCount, equals(2));
    });
  });
}
