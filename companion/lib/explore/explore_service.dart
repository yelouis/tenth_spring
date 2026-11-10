import 'dart:async';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'explore_store.dart';
import 'grid.dart';
import 'places_pack.dart';

/// Canonical permission rationale from `design_privacy_and_location.md` §3
/// and `implementation_plan_explore_here.md` §3.4.
const String kPermissionRationale =
    'Tenth Spring checks your location once, only when you tap Explore Here or Set home. '
    'Your phone looks it up on a map of famous places and then forgets it. '
    'Only the name of the place you unlocked is sent to your own PC.';

const String kSetHomeExplanation =
    "We use this once to find the famous city nearest you. Only the city's name is saved.";

/// Abstraction over single-shot OS location queries so tests can inject a fake
/// without touching platform channels.
abstract class PositionSource {
  Future<LocationPermission> checkPermission();
  Future<LocationPermission> requestPermission();
  Future<Position> getCurrentPosition();
  Future<bool> openAppSettings();
}

/// Production [PositionSource] backed by `package:geolocator` ("while in use" only).
class GeolocatorPositionSource implements PositionSource {
  const GeolocatorPositionSource();

  @override
  Future<LocationPermission> checkPermission() => Geolocator.checkPermission();

  @override
  Future<LocationPermission> requestPermission() =>
      Geolocator.requestPermission();

  @override
  Future<Position> getCurrentPosition() {
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 10),
      ),
    );
  }

  @override
  Future<bool> openAppSettings() => Geolocator.openAppSettings();
}

enum ExploreOutcomeKind {
  permissionDenied,
  timeout,
  fuzzy,
  notInAnyPlace,
  alreadyExplored,
  newNeighbourhood,
  newNeighbourhoodCityRevealed,
  newSiteRevealed,
  homeSet,
}

class ExploreResult {
  final ExploreOutcomeKind kind;
  final String message;
  final String? primaryMessage;
  final String? secondaryMessage;
  final bool unlockedNew;
  final bool permissionDenied;
  final String? placeId;
  final String? areaKey;
  final int? exploredCount;
  final int? threshold;

  const ExploreResult({
    required this.kind,
    required this.message,
    this.primaryMessage,
    this.secondaryMessage,
    required this.unlockedNew,
    this.permissionDenied = false,
    this.placeId,
    this.areaKey,
    this.exploredCount,
    this.threshold,
  });
}

enum _ReadingFailure {
  permissionDenied,
  timeout,
  fuzzy,
}

/// The one place in the companion where a coordinate exists, and only in memory:
/// one reading -> lookup -> result -> the reading discarded.
class ExploreService {
  final ExploreStore store;
  final PlacesPack pack;
  final PositionSource positionSource;
  final int Function() _clockMs;
  final Future<void> Function()? onVibrate;

  ExploreService({
    required this.store,
    required this.pack,
    PositionSource? positionSource,
    int Function()? clockMs,
    Future<void> Function()? vibrate,
  })  : positionSource = positionSource ?? const GeolocatorPositionSource(),
        _clockMs =
            clockMs ?? (() => DateTime.now().toUtc().millisecondsSinceEpoch),
        onVibrate = vibrate;

  /// Checks and requests "while in use" location permission once if currently denied.
  Future<bool> _ensureWhileInUsePermission() async {
    var perm = await positionSource.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await positionSource.requestPermission();
    }
    return perm == LocationPermission.whileInUse ||
        perm == LocationPermission.always;
  }

  /// Takes one GPS reading, projects it to a `(cx, cy)` cell, and lets the
  /// [Position] object go out of scope immediately.
  Future<({({int cx, int cy})? cell, _ReadingFailure? failure})>
      _readOneCell() async {
    final allowed = await _ensureWhileInUsePermission();
    if (!allowed) {
      return (cell: null, failure: _ReadingFailure.permissionDenied);
    }

    final Position position;
    try {
      position = await positionSource.getCurrentPosition();
    } on TimeoutException {
      return (cell: null, failure: _ReadingFailure.timeout);
    } catch (_) {
      return (cell: null, failure: _ReadingFailure.timeout);
    }

    if (position.accuracy > 100.0) {
      return (cell: null, failure: _ReadingFailure.fuzzy);
    }

    final cell = Grid.latlonToCell(position.latitude, position.longitude);
    // `position` goes out of scope here and is never stored or logged.
    return (cell: cell, failure: null);
  }

  /// Takes one GPS reading, finds the nearest city ID in [pack], and lets the
  /// [Position] object go out of scope immediately.
  Future<({String? cityId, _ReadingFailure? failure})>
      _readNearestCityId() async {
    final allowed = await _ensureWhileInUsePermission();
    if (!allowed) {
      return (cityId: null, failure: _ReadingFailure.permissionDenied);
    }

    final Position position;
    try {
      position = await positionSource.getCurrentPosition();
    } on TimeoutException {
      return (cityId: null, failure: _ReadingFailure.timeout);
    } catch (_) {
      return (cityId: null, failure: _ReadingFailure.timeout);
    }

    if (position.accuracy > 100.0) {
      return (cityId: null, failure: _ReadingFailure.fuzzy);
    }

    final cityId = pack.nearestCity(position.latitude, position.longitude);
    // `position` goes out of scope here and is never stored or logged.
    return (cityId: cityId, failure: null);
  }

  ExploreResult _failureResult(_ReadingFailure failure) {
    switch (failure) {
      case _ReadingFailure.permissionDenied:
        return const ExploreResult(
          kind: ExploreOutcomeKind.permissionDenied,
          message:
              'Explore Here needs your location once, only when you tap. You can allow it in Settings.',
          unlockedNew: false,
          permissionDenied: true,
        );
      case _ReadingFailure.timeout:
        return const ExploreResult(
          kind: ExploreOutcomeKind.timeout,
          message: "Couldn't find your location — try again in the open.",
          unlockedNew: false,
        );
      case _ReadingFailure.fuzzy:
        return const ExploreResult(
          kind: ExploreOutcomeKind.fuzzy,
          message:
              'Your location is too fuzzy here — try again in the open.',
          unlockedNew: false,
        );
    }
  }

  /// Executes the §3.3 Explore Here flow.
  Future<ExploreResult> exploreHere() async {
    final reading = await _readOneCell();
    if (reading.failure != null) {
      return _failureResult(reading.failure!);
    }

    final cell = reading.cell!;
    final hit = pack.lookupCell(cell.cx, cell.cy);
    if (hit == null) {
      return const ExploreResult(
        kind: ExploreOutcomeKind.notInAnyPlace,
        message:
            "This spot isn't on Tenth Spring's map. The map covers 27 famous cities and 60 parks and wonders.",
        unlockedNew: false,
      );
    }

    final place = pack.place(hit.placeId);
    final area = pack.area(hit.areaKey);
    if (place == null || area == null) {
      return const ExploreResult(
        kind: ExploreOutcomeKind.notInAnyPlace,
        message:
            "This spot isn't on Tenth Spring's map. The map covers 27 famous cities and 60 parks and wonders.",
        unlockedNew: false,
      );
    }

    final already = await store.isAreaExplored(hit.areaKey);
    if (already) {
      if (place.kind == 'city') {
        final k = await store.countExploredAreasForPlace(place.id);
        final t = place.threshold;
        return ExploreResult(
          kind: ExploreOutcomeKind.alreadyExplored,
          message:
              'Already explored — ${area.name}. $k of $t neighbourhoods explored in ${place.name}.',
          unlockedNew: false,
          placeId: place.id,
          areaKey: area.key,
          exploredCount: k,
          threshold: t,
        );
      } else {
        return ExploreResult(
          kind: ExploreOutcomeKind.alreadyExplored,
          message: 'Already explored — ${place.name}.',
          unlockedNew: false,
          placeId: place.id,
          areaKey: area.key,
          exploredCount: 1,
          threshold: 1,
        );
      }
    }

    final nowMs = _clockMs();
    await store.recordExploreUnlock(
      areaKey: area.key,
      placeId: place.id,
      tsUtcMs: nowMs,
      packVersion: pack.packVersion,
    );

    if (onVibrate != null) {
      await onVibrate!();
    } else {
      try {
        unawaited(HapticFeedback.mediumImpact().catchError((_) {}));
      } catch (_) {}
    }

    if (place.kind == 'city') {
      final k = await store.countExploredAreasForPlace(place.id);
      final t = place.threshold;
      final line1 =
          'New neighbourhood — ${area.name}, ${place.name}! $k of $t to reveal the whole city.';
      if (k == t) {
        final line2 =
            'City revealed — ${place.name}! You can Distort there from home.';
        return ExploreResult(
          kind: ExploreOutcomeKind.newNeighbourhoodCityRevealed,
          message: '$line1\n$line2',
          primaryMessage: line1,
          secondaryMessage: line2,
          unlockedNew: true,
          placeId: place.id,
          areaKey: area.key,
          exploredCount: k,
          threshold: t,
        );
      }
      return ExploreResult(
        kind: ExploreOutcomeKind.newNeighbourhood,
        message: line1,
        primaryMessage: line1,
        unlockedNew: true,
        placeId: place.id,
        areaKey: area.key,
        exploredCount: k,
        threshold: t,
      );
    } else {
      final line =
          '${place.name} revealed! You can Distort there from home.';
      return ExploreResult(
        kind: ExploreOutcomeKind.newSiteRevealed,
        message: line,
        primaryMessage: line,
        unlockedNew: true,
        placeId: place.id,
        areaKey: area.key,
        exploredCount: 1,
        threshold: 1,
      );
    }
  }

  /// Executes the §3.5 Set home flow.
  Future<ExploreResult> setHome() async {
    final reading = await _readNearestCityId();
    if (reading.failure != null) {
      return _failureResult(reading.failure!);
    }

    final cityId = reading.cityId ?? '';
    final city = pack.place(cityId);
    if (city == null) {
      return const ExploreResult(
        kind: ExploreOutcomeKind.notInAnyPlace,
        message:
            "This spot isn't on Tenth Spring's map. The map covers 27 famous cities and 60 parks and wonders.",
        unlockedNew: false,
      );
    }

    final wpCell = Grid.latlonToCell(city.waypostLat, city.waypostLon);
    final wpHit = pack.lookupCell(wpCell.cx, wpCell.cy);
    String? waypostAreaKey;
    if (wpHit != null && wpHit.placeId == city.id) {
      waypostAreaKey = wpHit.areaKey;
    } else if (city.areas.isNotEmpty) {
      waypostAreaKey = city.areas.first.key;
    }

    final nowMs = _clockMs();
    await store.recordSetHome(
      cityId: city.id,
      waypostAreaKey: waypostAreaKey,
      tsUtcMs: nowMs,
      packVersion: pack.packVersion,
    );

    final k = await store.countExploredAreasForPlace(city.id);
    final msg = 'Your starting city is ${city.name}. Only its name is saved.';
    return ExploreResult(
      kind: ExploreOutcomeKind.homeSet,
      message: msg,
      primaryMessage: msg,
      unlockedNew: true,
      placeId: city.id,
      areaKey: waypostAreaKey,
      exploredCount: k,
      threshold: city.threshold,
    );
  }
}
