import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:companion/capture/os_location_source.dart';

void main() {
  test('OsLocationSource configures background settings per platform', () {
    final source = OsLocationSource(
      accuracy: LocationAccuracy.medium,
      distanceFilterMeters: 25,
    );

    final settings = source.buildLocationSettings();

    if (defaultTargetPlatform == TargetPlatform.android) {
      expect(settings, isA<AndroidSettings>());
      final androidSettings = settings as AndroidSettings;
      expect(androidSettings.foregroundNotificationConfig, isNotNull);
      expect(androidSettings.foregroundNotificationConfig?.notificationTitle,
          equals('Tenth Spring'));
    } else if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      expect(settings, isA<AppleSettings>());
      final appleSettings = settings as AppleSettings;
      expect(appleSettings.allowBackgroundLocationUpdates, isTrue);
    }
  });
}
