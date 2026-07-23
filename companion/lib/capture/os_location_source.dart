import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'location_source.dart';

/// Real OS Location Source implementation using Geolocator.
/// Uses balanced power accuracy, distance filtering (25m), and platform-specific
/// background configurations (Android Foreground Service / iOS background location)
/// to maintain passive scouting within the <3%/day battery budget.
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

  LocationSettings buildLocationSettings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilterMeters,
        intervalDuration: const Duration(minutes: 2),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: "Tenth Spring",
          notificationText: "Scouting your map",
          enableWakeLock: false,
        ),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return AppleSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilterMeters,
        activityType: ActivityType.other,
        pauseLocationUpdatesAutomatically: true,
        showBackgroundLocationIndicator: false,
        allowBackgroundLocationUpdates: true,
      );
    } else {
      return LocationSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilterMeters,
      );
    }
  }

  @override
  Future<void> start() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled.');
    }

    LocationPermission permission = await Geolocator.checkPermission();

    // Step 1: Request foreground / while-in-use permission if denied
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

    // Step 2: Staged request - if whileInUse granted, attempt background request (Always)
    if (permission == LocationPermission.whileInUse) {
      try {
        permission = await Geolocator.requestPermission();
      } catch (_) {
        // Fallback: If background permission is declined, app continues operating in WhileInUse mode
      }
    }

    final locationSettings = buildLocationSettings();

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
