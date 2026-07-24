import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:companion/capture/os_location_source.dart';

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('OsLocationSource constructs AndroidSettings with full spec on Android', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final source = OsLocationSource(
      accuracy: LocationAccuracy.medium,
      distanceFilterMeters: 25,
    );

    final settings = source.buildLocationSettings();
    expect(settings, isA<AndroidSettings>());
    final androidSettings = settings as AndroidSettings;
    expect(androidSettings.accuracy, equals(LocationAccuracy.medium));
    expect(androidSettings.distanceFilter, equals(25));
    expect(androidSettings.intervalDuration, equals(const Duration(minutes: 2)));
    expect(androidSettings.foregroundNotificationConfig, isNotNull);
    expect(androidSettings.foregroundNotificationConfig?.notificationTitle,
        equals('Tenth Spring'));
    expect(androidSettings.foregroundNotificationConfig?.notificationText,
        equals('Scouting your map'));
    expect(androidSettings.foregroundNotificationConfig?.enableWakeLock, isFalse);
  });

  test('OsLocationSource constructs AppleSettings with full spec on iOS', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final source = OsLocationSource(
      accuracy: LocationAccuracy.medium,
      distanceFilterMeters: 25,
    );

    final settings = source.buildLocationSettings();
    expect(settings, isA<AppleSettings>());
    final appleSettings = settings as AppleSettings;
    expect(appleSettings.accuracy, equals(LocationAccuracy.medium));
    expect(appleSettings.distanceFilter, equals(25));
    expect(appleSettings.allowBackgroundLocationUpdates, isTrue);
    expect(appleSettings.pauseLocationUpdatesAutomatically, isTrue);
    expect(appleSettings.showBackgroundLocationIndicator, isFalse);
    expect(appleSettings.activityType, equals(ActivityType.other));
  });
}
