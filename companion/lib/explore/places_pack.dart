import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'grid.dart';

class AreaEntry {
  final String key;
  final String name;
  final String kind;
  final String placeId;
  final int cellCount;

  const AreaEntry({
    required this.key,
    required this.name,
    required this.kind,
    required this.placeId,
    required this.cellCount,
  });
}

class PlaceEntry {
  final String id;
  final String kind; // 'city' or 'site'
  final String name;
  final String region;
  final double waypostLat;
  final double waypostLon;
  final int threshold;
  final List<int> bbox; // [cxMin, cyMin, cxMax, cyMax]
  final List<AreaEntry> areas;
  final List<List<int>> rows;

  const PlaceEntry({
    required this.id,
    required this.kind,
    required this.name,
    required this.region,
    required this.waypostLat,
    required this.waypostLon,
    required this.threshold,
    required this.bbox,
    required this.areas,
    required this.rows,
  });
}

/// Reader and binary-search cell lookup for `places_pack_v1.json.gz`.
/// Mirrors `game/world/places_pack.gd`.
class PlacesPack {
  final int packVersion;
  final String snapshot;
  final String attribution;
  final List<PlaceEntry> places;
  final Map<String, PlaceEntry> placesById;
  final Map<String, AreaEntry> areasByKey;
  final Map<String, List<({int cx, int cy})>> _cellsByAreaCache = {};

  PlacesPack._({
    required this.packVersion,
    required this.snapshot,
    required this.attribution,
    required this.places,
    required this.placesById,
    required this.areasByKey,
  });

  /// Loads the bundled `assets/places_pack_v1.json.gz` from Flutter assets,
  /// falling back to disk for standalone Dart tests.
  static Future<PlacesPack> loadAsset([
    String assetPath = 'assets/places_pack_v1.json.gz',
  ]) async {
    try {
      final byteData = await rootBundle.load(assetPath);
      final bytes = byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );
      return fromGzippedBytes(bytes);
    } catch (_) {
      final file = File(assetPath);
      if (file.existsSync()) {
        return fromGzippedBytes(file.readAsBytesSync());
      }
      rethrow;
    }
  }

  /// Loads a pack from a `.json.gz` file on disk (e.g. test fixtures).
  static PlacesPack loadFile(String filePath) {
    final bytes = File(filePath).readAsBytesSync();
    return fromGzippedBytes(bytes);
  }

  /// Parses a gzipped JSON places pack.
  static PlacesPack fromGzippedBytes(List<int> gzBytes) {
    final decompressed = gzip.decode(gzBytes);
    final jsonStr = utf8.decode(decompressed);
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    return fromJson(data);
  }

  /// Parses a decoded JSON places pack map.
  static PlacesPack fromJson(Map<String, dynamic> data) {
    final packVersion = (data['pack_version'] as num?)?.toInt() ?? 1;
    final snapshot = (data['snapshot'] as String?) ?? '261001';
    final attribution =
        (data['attribution'] as String?) ?? '© OpenStreetMap contributors (ODbL)';

    final rawPlaces = (data['places'] as List<dynamic>?) ?? const [];
    final places = <PlaceEntry>[];
    final placesById = <String, PlaceEntry>{};
    final areasByKey = <String, AreaEntry>{};

    for (final rawPlace in rawPlaces) {
      final pMap = rawPlace as Map<String, dynamic>;
      final pid = pMap['id'] as String;
      final pKind = pMap['kind'] as String;
      final pName = pMap['name'] as String;
      final pRegion = (pMap['region'] as String?) ?? '';
      final wp = (pMap['waypost'] as Map<String, dynamic>?) ?? const {};
      final wpLat = (wp['lat'] as num?)?.toDouble() ?? 0.0;
      final wpLon = (wp['lon'] as num?)?.toDouble() ?? 0.0;
      final threshold = (pMap['threshold'] as num?)?.toInt() ?? 1;
      final bbox = ((pMap['bbox'] as List<dynamic>?) ?? const [0, 0, -1, -1])
          .map((e) => (e as num).toInt())
          .toList();

      final rawRows = (pMap['rows'] as List<dynamic>?) ?? const [];
      final rows = <List<int>>[];
      final rawAreas = (pMap['areas'] as List<dynamic>?) ?? const [];
      final cellCounts = List<int>.filled(rawAreas.length, 0);

      for (final r in rawRows) {
        final rowInts =
            (r as List<dynamic>).map((e) => (e as num).toInt()).toList();
        rows.add(rowInts);
        for (int i = 1; i + 2 < rowInts.length; i += 3) {
          final runLen = rowInts[i + 1];
          final areaIdx = rowInts[i + 2];
          if (areaIdx >= 0 && areaIdx < cellCounts.length) {
            cellCounts[areaIdx] += runLen;
          }
        }
      }

      final areaKind = pKind == 'city' ? 'neighbourhood' : 'site';
      final areas = <AreaEntry>[];
      for (int idx = 0; idx < rawAreas.length; idx++) {
        final aMap = rawAreas[idx] as Map<String, dynamic>;
        final entry = AreaEntry(
          key: aMap['key'] as String,
          name: aMap['name'] as String,
          kind: areaKind,
          placeId: pid,
          cellCount: cellCounts[idx],
        );
        areas.add(entry);
        areasByKey[entry.key] = entry;
      }

      final placeEntry = PlaceEntry(
        id: pid,
        kind: pKind,
        name: pName,
        region: pRegion,
        waypostLat: wpLat,
        waypostLon: wpLon,
        threshold: threshold,
        bbox: bbox,
        areas: areas,
        rows: rows,
      );
      places.add(placeEntry);
      placesById[pid] = placeEntry;
    }

    return PlacesPack._(
      packVersion: packVersion,
      snapshot: snapshot,
      attribution: attribution,
      places: places,
      placesById: placesById,
      areasByKey: areasByKey,
    );
  }

  /// Looks up cell (cx, cy) via bbox prefilter and binary search over rows and runs.
  /// Returns `(placeId: ..., areaKey: ...)` or `null` if outside all places.
  ({String placeId, String areaKey})? lookupCell(int cx, int cy) {
    for (final p in places) {
      if (p.bbox.length < 4) continue;
      if (cx < p.bbox[0] ||
          cy < p.bbox[1] ||
          cx > p.bbox[2] ||
          cy > p.bbox[3]) {
        continue;
      }
      final rows = p.rows;
      int lo = 0;
      int hi = rows.length - 1;
      List<int>? matchedRow;
      while (lo <= hi) {
        final mid = (lo + hi) >> 1;
        final rCy = rows[mid][0];
        if (rCy == cy) {
          matchedRow = rows[mid];
          break;
        } else if (rCy < cy) {
          lo = mid + 1;
        } else {
          hi = mid - 1;
        }
      }
      if (matchedRow == null) continue;

      final numRuns = (matchedRow.length - 1) ~/ 3;
      int rLo = 0;
      int rHi = numRuns - 1;
      while (rLo <= rHi) {
        final rMid = (rLo + rHi) >> 1;
        final base = 1 + rMid * 3;
        final cx0 = matchedRow[base];
        final len = matchedRow[base + 1];
        final areaIdx = matchedRow[base + 2];
        if (cx < cx0) {
          rHi = rMid - 1;
        } else if (cx >= cx0 + len) {
          rLo = rMid + 1;
        } else {
          if (areaIdx >= 0 && areaIdx < p.areas.length) {
            return (placeId: p.id, areaKey: p.areas[areaIdx].key);
          }
          break;
        }
      }
    }
    return null;
  }

  /// Returns metadata for `areaKey`, or `null` if unknown.
  AreaEntry? area(String areaKey) => areasByKey[areaKey];

  /// Returns metadata for `placeId`, or `null` if unknown.
  PlaceEntry? place(String placeId) => placesById[placeId];

  /// Returns all areas belonging to `placeId`.
  List<AreaEntry> areasOf(String placeId) =>
      placesById[placeId]?.areas ?? const [];

  /// Returns the city unlock threshold `T` for `placeId` (1 for sites).
  int threshold(String placeId) => placesById[placeId]?.threshold ?? 1;

  /// Returns the Waypost `(lat, lon)` for `placeId`, or `null` if unknown.
  ({double lat, double lon})? waypost(String placeId) {
    final p = placesById[placeId];
    if (p == null) return null;
    return (lat: p.waypostLat, lon: p.waypostLon);
  }

  /// Returns all `(cx, cy)` cells belonging to `areaKey`.
  List<({int cx, int cy})> cellsOf(String areaKey) {
    final cached = _cellsByAreaCache[areaKey];
    if (cached != null) return cached;
    final a = areasByKey[areaKey];
    if (a == null) return const [];
    final p = placesById[a.placeId];
    if (p == null) return const [];

    int targetIdx = -1;
    for (int i = 0; i < p.areas.length; i++) {
      if (p.areas[i].key == areaKey) {
        targetIdx = i;
        break;
      }
    }
    if (targetIdx < 0) return const [];

    final cells = <({int cx, int cy})>[];
    for (final row in p.rows) {
      final cy = row[0];
      for (int i = 1; i + 2 < row.length; i += 3) {
        final cx0 = row[i];
        final len = row[i + 1];
        final aIdx = row[i + 2];
        if (aIdx == targetIdx) {
          for (int k = 0; k < len; k++) {
            cells.add((cx: cx0 + k, cy: cy));
          }
        }
      }
    }
    _cellsByAreaCache[areaKey] = cells;
    return cells;
  }

  /// Returns the `placeId` of the famous city whose Waypost is nearest `(lat, lon)`
  /// in ground distance (`Grid.groundDistanceM`), breaking ties by lower `placeId`.
  String nearestCity(double lat, double lon) {
    final originWm = Grid.latlonToWm(lat, lon);
    String bestId = '';
    double bestDist = double.infinity;

    for (final p in places) {
      if (p.kind != 'city') continue;
      final wpWm = Grid.latlonToWm(p.waypostLat, p.waypostLon);
      final d = Grid.groundDistanceM(originWm.x, originWm.y, wpWm.x, wpWm.y);
      if (bestId.isEmpty ||
          d < bestDist ||
          (d == bestDist && p.id.compareTo(bestId) < 0)) {
        bestDist = d;
        bestId = p.id;
      }
    }
    return bestId;
  }
}
