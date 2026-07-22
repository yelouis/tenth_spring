import 'dart:async';
import 'package:xml/xml.dart';
import 'location_source.dart';

/// Debug-only GPX Replay LocationSource.
/// Parses a GPX document and emits track points as Fix objects.
class GpxReplaySource implements LocationSource {
  final String gpxXml;
  final double timeScale;
  final bool instant;
  final double defaultAccuracyM;

  final _fixController = StreamController<Fix>.broadcast();
  bool _isRunning = false;

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
  Future<void> start() async {
    _isRunning = true;
    final document = XmlDocument.parse(gpxXml);
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
