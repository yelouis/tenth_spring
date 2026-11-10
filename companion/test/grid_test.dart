import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:companion/explore/grid.dart';

File _resolveVectorsFile() {
  final candidates = [
    File('../tools/testdata/grid_vectors.json'),
    File('tools/testdata/grid_vectors.json'),
  ];
  for (final f in candidates) {
    if (f.existsSync()) return f;
  }
  throw StateError('Could not locate tools/testdata/grid_vectors.json');
}

void main() {
  group('Grid cross-language vectors', () {
    late List<dynamic> vectors;

    setUpAll(() {
      final raw = _resolveVectorsFile().readAsStringSync();
      vectors = jsonDecode(raw) as List<dynamic>;
    });

    test('vector count and regional coverage', () {
      expect(vectors.length, greaterThanOrEqualTo(40));
      final names = vectors.map((v) => v['name'] as String).toSet();
      expect(names.any((n) => n.contains('alaska')), isTrue);
      expect(names.any((n) => n.contains('hawaii')), isTrue);
      expect(names.any((n) => n.contains('puerto_rico')), isTrue);
      expect(names.any((n) => n.contains('cell_edge')), isTrue);
    });

    test('all shared vectors match Python and GDScript projections', () {
      for (final raw in vectors) {
        final v = raw as Map<String, dynamic>;
        final name = v['name'] as String;
        final lat = (v['lat'] as num).toDouble();
        final lon = (v['lon'] as num).toDouble();
        final expectedWmX = (v['wm_x'] as num).toDouble();
        final expectedWmY = (v['wm_y'] as num).toDouble();
        final expectedCx = (v['cell_x'] as num).toInt();
        final expectedCy = (v['cell_y'] as num).toInt();

        final wm = Grid.latlonToWm(lat, lon);
        final cell = Grid.latlonToCell(lat, lon);

        expect(
          wm.x,
          closeTo(expectedWmX, 1e-6),
          reason: 'wm_x mismatch on $name',
        );
        expect(
          wm.y,
          closeTo(expectedWmY, 1e-6),
          reason: 'wm_y mismatch on $name',
        );
        expect(cell.cx, equals(expectedCx), reason: 'cell_x mismatch on $name');
        expect(cell.cy, equals(expectedCy), reason: 'cell_y mismatch on $name');

        final rt = Grid.wmToLatlon(wm.x, wm.y);
        expect(rt.lat, closeTo(lat, 1e-6), reason: 'rt_lat mismatch on $name');
        expect(rt.lon, closeTo(lon, 1e-6), reason: 'rt_lon mismatch on $name');
      }
    });

    test('groundDistanceM and cellCenterWm', () {
      final cell = Grid.latlonToCell(47.6000, -122.3300);
      final c1 = Grid.cellCenterWm(cell.cx, cell.cy);
      final c2 = Grid.cellCenterWm(cell.cx + 1, cell.cy);
      final dist = Grid.groundDistanceM(c1.x, c1.y, c2.x, c2.y);
      expect(dist, closeTo(172.6, 1.0));
    });
  });
}
