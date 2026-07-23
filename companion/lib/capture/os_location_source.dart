import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'location_source.dart';

/// Real OS Location Source implementation using Geolocator.
/// Uses balanced power accuracy and distance filtering (25m) to maintain
/// background capture within the <3%/day battery budget.
class OsLocationSource implements LocationSource {
  final LocationAccuracy accuracy;
  final int distanceFilterMeters;
  StreamSubscription<Position>? _positionSubscription;
  final _fixController = StreamController<Fix>.broadcast();

  OsLocationSource({
    this.accuracy = LocationAccuracy.medium,
    this.distanceFilterMeters = 25,
  });

  @override
  Stream<Fix> fixes() => _fixController.stream;

  @override
  Stream<OsVisit>? nativeVisits() => null;

  @override
  Future<void> start() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled.');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permissions are denied.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception(
          'Location permissions are permanently denied, cannot request permissions.');
    }

    late LocationSettings locationSettings;

    locationSettings = LocationSettings(
      accuracy: accuracy,
      distanceFilter: distanceFilterMeters,
    );

    _positionSubscription?.cancel();
    _positionSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings)
            .listen((Position position) {
      final fix = Fix(
        lat: position.latitude,
        lon: position.longitude,
        accuracyM: position.accuracy,
        tsUtcMs: position.timestamp.millisecondsSinceEpoch,
        speedMps: position.speed,
      );
      _fixController.add(fix);
    });
  }

  @override
  Future<void> stop() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  void dispose() {
    stop();
    _fixController.close();
  }
}
