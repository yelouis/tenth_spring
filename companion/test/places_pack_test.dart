import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
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

void main() {
  group('PlacesPack lookup and metadata', () {
    late PlacesPack pack;

    setUpAll(() {
      pack = PlacesPack.loadFile(_resolveFixtureFile().path);
    });

    test('pack metadata and place counts', () {
      expect(pack.packVersion, equals(1));
      expect(pack.snapshot, equals('261001'));
      expect(pack.attribution, contains('OpenStreetMap'));
      expect(pack.places.length, equals(2));
      expect(pack.threshold('city:fixture-city'), equals(2));
      expect(pack.threshold('site:fixture-park'), equals(1));
      expect(pack.areasOf('city:fixture-city').length, equals(4));
      expect(pack.areasOf('site:fixture-park').length, equals(1));
    });

    test('lookupCell inside each area of the fixture pack', () {
      // Mill District: (2, 2)..(3, 3)
      final hitMill = pack.lookupCell(2, 2);
      expect(hitMill, isNotNull);
      expect(hitMill!.placeId, equals('city:fixture-city'));
      expect(hitMill.areaKey, equals('osm:r9010'));
      expect(pack.area(hitMill.areaKey)?.name, equals('Mill District'));

      // Old Town: (4, 2), (3, 4), etc.
      final hitOldTown = pack.lookupCell(4, 2);
      expect(hitOldTown, isNotNull);
      expect(hitOldTown!.placeId, equals('city:fixture-city'));
      expect(hitOldTown.areaKey, equals('osm:n9104'));
      expect(pack.area(hitOldTown.areaKey)?.name, equals('Old Town'));

      // Riverside: (6, 2), (7, 6), etc.
      final hitRiver = pack.lookupCell(6, 2);
      expect(hitRiver, isNotNull);
      expect(hitRiver!.placeId, equals('city:fixture-city'));
      expect(hitRiver.areaKey, equals('osm:n9105'));
      expect(pack.area(hitRiver.areaKey)?.name, equals('Riverside'));

      // North End: (2, 6), (2, 7), etc.
      final hitNorth = pack.lookupCell(2, 6);
      expect(hitNorth, isNotNull);
      expect(hitNorth!.placeId, equals('city:fixture-city'));
      expect(hitNorth.areaKey, equals('osm:n9103'));
      expect(pack.area(hitNorth.areaKey)?.name, equals('North End'));

      // Fixture Park: (9, 3)..(12, 6)
      final hitPark = pack.lookupCell(10, 4);
      expect(hitPark, isNotNull);
      expect(hitPark!.placeId, equals('site:fixture-park'));
      expect(hitPark.areaKey, equals('site:fixture-park'));
      expect(pack.area(hitPark.areaKey)?.name, equals('Fixture Park'));
    });

    test('lookupCell on exact cell boundary and outside all places', () {
      // Exact SW corner of cell (4, 2) in Web Mercator -> lat/lon -> latlonToCell
      final swOrigin = Grid.cellOriginWm(4, 2);
      final ll = Grid.wmToLatlon(swOrigin.x + 1e-4, swOrigin.y + 1e-4);
      final edgeCell = Grid.latlonToCell(ll.lat, ll.lon);
      expect(edgeCell.cx, equals(4));
      expect(edgeCell.cy, equals(2));
      final edgeHit = pack.lookupCell(edgeCell.cx, edgeCell.cy);
      expect(edgeHit, isNotNull);
      expect(edgeHit!.areaKey, equals('osm:n9104'));

      // Just west of cell (2, 2) -> cell (1, 2) is outside
      expect(pack.lookupCell(1, 2), isNull);
      // Gap between city (max cx 7) and park (min cx 9) -> cell (8, 4) is outside
      expect(pack.lookupCell(8, 4), isNull);
      // Far away cell -> null
      expect(pack.lookupCell(-500, 500), isNull);
    });

    test('cellsOf round-trip matches lookupCell', () {
      for (final p in pack.places) {
        for (final a in p.areas) {
          final cells = pack.cellsOf(a.key);
          expect(cells.length, equals(a.cellCount));
          expect(cells, isNotEmpty);
          for (final c in cells) {
            final hit = pack.lookupCell(c.cx, c.cy);
            expect(hit, isNotNull);
            expect(hit!.placeId, equals(p.id));
            expect(hit.areaKey, equals(a.key));
          }
        }
      }
    });

    test('nearestCity picks closest city Waypost and breaks ties by lower id', () {
      expect(pack.nearestCity(0.01, 0.01), equals('city:fixture-city'));

      final tiePack = PlacesPack.fromJson({
        'pack_version': 1,
        'snapshot': '261001',
        'attribution': '© OpenStreetMap contributors (ODbL)',
        'places': [
          {
            'id': 'city:zeta',
            'kind': 'city',
            'name': 'Zeta',
            'region': 'test',
            'waypost': {'lat': 10.0, 'lon': 10.0},
            'threshold': 1,
            'bbox': [0, 0, 0, 0],
            'areas': [
              {'key': 'city:zeta:a', 'name': 'A'}
            ],
            'rows': [
              [0, 0, 1, 0]
            ],
          },
          {
            'id': 'city:alpha',
            'kind': 'city',
            'name': 'Alpha',
            'region': 'test',
            'waypost': {'lat': 10.0, 'lon': 10.0},
            'threshold': 1,
            'bbox': [0, 0, 0, 0],
            'areas': [
              {'key': 'city:alpha:a', 'name': 'A'}
            ],
            'rows': [
              [0, 0, 1, 0]
            ],
          },
        ],
      });
      expect(tiePack.nearestCity(10.0, 10.0), equals('city:alpha'));
    });
  });
}
