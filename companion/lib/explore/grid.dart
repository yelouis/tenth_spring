import 'dart:math' as math;

/// Shared Web Mercator (EPSG:3857) projection and 256 WM-m cell grid.
/// Matches `game/world/grid.gd` and `tools/grid.py` on all cross-language vectors.
class Grid {
  static const double earthRadiusM = 6378137.0;
  static const double maxLatDeg = 85.05112878;
  static const double cellMeters = 256.0;
  static const double tileMeters = 8.0;
  static const int tilesPerCell = 32;

  static double _degToRad(double deg) => deg * (math.pi / 180.0);
  static double _radToDeg(double rad) => rad * (180.0 / math.pi);

  /// Projects (latDeg, lonDeg) to Web Mercator (x, y) meters.
  static ({double x, double y}) latlonToWm(double latDeg, double lonDeg) {
    final latClamped = latDeg.clamp(-maxLatDeg, maxLatDeg);
    final x = earthRadiusM * _degToRad(lonDeg);
    final latRad = _degToRad(latClamped);
    final y = earthRadiusM * math.log(math.tan(math.pi / 4.0 + latRad / 2.0));
    return (x: x, y: y);
  }

  /// Inverse Web Mercator projection from (x, y) meters to (lat, lon) degrees.
  static ({double lat, double lon}) wmToLatlon(double x, double y) {
    final lonDeg = _radToDeg(x / earthRadiusM);
    final latRad = 2.0 * math.atan(math.exp(y / earthRadiusM)) - math.pi / 2.0;
    final latDeg = _radToDeg(latRad);
    return (lat: latDeg, lon: lonDeg);
  }

  /// Returns the 256 WM-m cell (cx, cy) containing Web Mercator (x, y).
  static ({int cx, int cy}) wmToCell(double x, double y) {
    return (
      cx: (x / cellMeters).floor(),
      cy: (y / cellMeters).floor(),
    );
  }

  /// Returns the SW origin (x, y) of cell (cx, cy) in Web Mercator meters.
  static ({double x, double y}) cellOriginWm(int cx, int cy) {
    return (
      x: cx * cellMeters,
      y: cy * cellMeters,
    );
  }

  /// Returns the center (x, y) of cell (cx, cy) in Web Mercator meters.
  static ({double x, double y}) cellCenterWm(int cx, int cy) {
    return (
      x: (cx + 0.5) * cellMeters,
      y: (cy + 0.5) * cellMeters,
    );
  }

  /// Projects (latDeg, lonDeg) to its 256 WM-m cell (cx, cy).
  static ({int cx, int cy}) latlonToCell(double latDeg, double lonDeg) {
    final wm = latlonToWm(latDeg, lonDeg);
    return wmToCell(wm.x, wm.y);
  }

  /// Decomposes Web Mercator (x, y) into cell (cx, cy) and tile (tx, ty) in 0..31.
  /// Tile (0, 0) is the NW corner of the cell; tx increases east, ty increases south.
  static ({int cx, int cy, int tx, int ty}) wmToCellTile(double x, double y) {
    final cell = wmToCell(x, y);
    final origin = cellOriginWm(cell.cx, cell.cy);
    final localX = x - origin.x;
    final localY = y - origin.y;
    final tx = (localX / tileMeters).floor().clamp(0, tilesPerCell - 1);
    final tyFromSouth =
        (localY / tileMeters).floor().clamp(0, tilesPerCell - 1);
    final ty = (tilesPerCell - 1) - tyFromSouth;
    return (cx: cell.cx, cy: cell.cy, tx: tx, ty: ty);
  }

  /// Ground scale factor cos(lat) at a given latitude.
  static double groundScaleAtLat(double latDeg) {
    final latClamped = latDeg.clamp(-maxLatDeg, maxLatDeg);
    return math.cos(_degToRad(latClamped));
  }

  /// Approximate ground distance in meters between two Web Mercator points.
  static double groundDistanceM(double x1, double y1, double x2, double y2) {
    final dx = x2 - x1;
    final dy = y2 - y1;
    final wmDist = math.sqrt(dx * dx + dy * dy);
    final midLat = wmToLatlon((x1 + x2) * 0.5, (y1 + y2) * 0.5).lat;
    return wmDist * groundScaleAtLat(midLat);
  }
}
