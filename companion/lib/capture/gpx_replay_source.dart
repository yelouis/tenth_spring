import 'dart:async';
import 'package:xml/xml.dart';
import 'fuzz.dart';
import 'location_source.dart';

/// Debug-only GPX Replay LocationSource.
/// Parses a GPX document and emits track points and waypoints as Fix objects.
/// Supports both recorded GPX (with <time> tags) and hand-drawn GPX (plan §3).
class GpxReplaySource implements LocationSource {
  static const int handDrawnEpochMs = 1770000000000;
  static const double walkingSpeedMps = 1.4;
  static const int waypointDwellSeconds = 600;

  final String gpxXml;
  final double timeScale;
  final bool instant;
  final double defaultAccuracyM;

  final _fixController = StreamController<Fix>.broadcast();
  bool _isRunning = false;
  Fix? _lastEmittedFix;

  GpxReplaySource(
    this.gpxXml, {
    this.timeScale = 1.0,
    this.instant = false,
    this.defaultAccuracyM = 10.0,
  });

  @override
  Stream<Fix> fixes() => _fixController.stream;

  @override
  Stream<OsVisit>? nativeVisits() => null;

  @override
  Future<Fix?> currentFix() async => _lastEmittedFix;

  @override
  Future<void> start() async {
    _isRunning = true;
    final document = XmlDocument.parse(gpxXml);

    final hasTimeTags = document.findAllElements('time').isNotEmpty;
    if (hasTimeTags) {
      await _replayRecordedGpx(document);
    } else {
      await _replayHandDrawnGpx(document);
    }
  }

  Future<void> _replayRecordedGpx(XmlDocument document) async {
    final trkpts = document.findAllElements('trkpt');

    int? firstPointTimeMs;
    final startTimeMs = DateTime.now().millisecondsSinceEpoch;

    for (final node in trkpts) {
      if (!_isRunning) break;

      final latStr = node.getAttribute('lat');
      final lonStr = node.getAttribute('lon');
      if (latStr == null || lonStr == null) continue;

      final lat = double.parse(latStr);
      final lon = double.parse(lonStr);

      final timeNode = node.findElements('time').firstOrNull;
      int ts;
      if (timeNode != null) {
        ts = DateTime.parse(timeNode.innerText).millisecondsSinceEpoch;
      } else {
        ts = DateTime.now().millisecondsSinceEpoch;
      }

      firstPointTimeMs ??= ts;

      if (!instant && timeScale > 0) {
        final pointOffsetMs = (ts - firstPointTimeMs) / timeScale;
        final targetWallTimeMs = startTimeMs + pointOffsetMs;
        final now = DateTime.now().millisecondsSinceEpoch;
        final delayMs = (targetWallTimeMs - now).round();

        if (delayMs > 0) {
          await Future.delayed(Duration(milliseconds: delayMs));
        }
      }

      final fix = Fix(
        lat: lat,
        lon: lon,
        accuracyM: defaultAccuracyM,
        tsUtcMs: ts,
      );

      _lastEmittedFix = fix;
      _fixController.add(fix);
    }
  }

  Future<void> _replayHandDrawnGpx(XmlDocument document) async {
    // Hand-drawn route synthesis rules (plan §3.1):
    // 1. <trkpt>: corridor movement at 1.4 m/s.
    // 2. <wpt>: visit with 10-minute dwell (600 s).
    // 3. First point starts at t0 = 1770000000000 ms.
    // 4. Delta t = round(d / 1.4) * 1000 ms.
    // 5. Point timestamp = t_prev + delta t.

    final fixesToEmit = <Fix>[];

    final wpts = document.findAllElements('wpt');
    final trkpts = document.findAllElements('trkpt');

    double? lastLat;
    double? lastLon;
    int currentTsMs = handDrawnEpochMs;

    // Process waypoints first as visits with 10-minute dwell
    for (final node in wpts) {
      final latStr = node.getAttribute('lat');
      final lonStr = node.getAttribute('lon');
      if (latStr == null || lonStr == null) continue;

      final lat = double.parse(latStr);
      final lon = double.parse(lonStr);

      if (lastLat != null && lastLon != null) {
        final distM = haversineMeters(lastLat, lastLon, lat, lon);
        final deltaSec = (distM / walkingSpeedMps).round();
        final deltaMs = deltaSec > 0 ? deltaSec * 1000 : 1000;
        currentTsMs += deltaMs;
      }

      final arriveTs = currentTsMs;
      fixesToEmit.add(Fix(
        lat: lat,
        lon: lon,
        accuracyM: defaultAccuracyM,
        tsUtcMs: arriveTs,
      ));

      // Dwell for 10 minutes (600s = 600,000ms)
      currentTsMs = arriveTs + (waypointDwellSeconds * 1000);
      fixesToEmit.add(Fix(
        lat: lat,
        lon: lon,
        accuracyM: defaultAccuracyM,
        tsUtcMs: currentTsMs,
      ));

      lastLat = lat;
      lastLon = lon;
    }

    // Process trackpoints as corridor movement
    for (final node in trkpts) {
      final latStr = node.getAttribute('lat');
      final lonStr = node.getAttribute('lon');
      if (latStr == null || lonStr == null) continue;

      final lat = double.parse(latStr);
      final lon = double.parse(lonStr);

      if (lastLat != null && lastLon != null) {
        final distM = haversineMeters(lastLat, lastLon, lat, lon);
        final deltaSec = (distM / walkingSpeedMps).round();
        final deltaMs = deltaSec > 0 ? deltaSec * 1000 : 1000;
        currentTsMs += deltaMs;
      }

      fixesToEmit.add(Fix(
        lat: lat,
        lon: lon,
        accuracyM: defaultAccuracyM,
        tsUtcMs: currentTsMs,
      ));

      lastLat = lat;
      lastLon = lon;
    }

    int? firstPointTimeMs;
    final startTimeMs = DateTime.now().millisecondsSinceEpoch;

    for (final fix in fixesToEmit) {
      if (!_isRunning) break;

      firstPointTimeMs ??= fix.tsUtcMs;

      if (!instant && timeScale > 0) {
        final pointOffsetMs = (fix.tsUtcMs - firstPointTimeMs) / timeScale;
        final targetWallTimeMs = startTimeMs + pointOffsetMs;
        final now = DateTime.now().millisecondsSinceEpoch;
        final delayMs = (targetWallTimeMs - now).round();

        if (delayMs > 0) {
          await Future.delayed(Duration(milliseconds: delayMs));
        }
      }

      _lastEmittedFix = fix;
      _fixController.add(fix);
    }
  }

  @override
  Future<void> stop() async {
    _isRunning = false;
  }

  void dispose() {
    _fixController.close();
  }
}
