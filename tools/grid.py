#!/usr/bin/env python3
"""
tools/grid.py — Web-Mercator Grid Projection & Ground-Distance Utilities (F42 / EPSG:3857)
Contract: docs/implementation_plan_explore_here.md §1.1 & game/world/grid.gd
Line-for-line port of game/world/grid.gd (EPSG:3857, 256 WM-m cells; north is +y).
"""

import math
from typing import List, Tuple

WM_R: float = 6378137.0
EARTH_MEAN_R: float = 6371008.8
CELL_WM: float = 256.0
TILE_WM: float = 8.0
MAX_LAT: float = 85.05112878


def _clamp(val: float, low: float, high: float) -> float:
    return max(low, min(high, val))


def latlon_to_wm(lat: float, lon: float) -> Tuple[float, float]:
    clamped_lat = _clamp(float(lat), -MAX_LAT, MAX_LAT)
    x = WM_R * math.radians(float(lon))
    y = WM_R * math.log(math.tan(math.pi / 4.0 + math.radians(clamped_lat) / 2.0))
    return (x, y)


def wm_to_latlon(wm_x: float, wm_y: float) -> Tuple[float, float]:
    lat = math.degrees(2.0 * math.atan(math.exp(float(wm_y) / WM_R)) - math.pi / 2.0)
    lon = math.degrees(float(wm_x) / WM_R)
    return (lat, lon)


def wm_to_cell(wm_x: float, wm_y: float) -> Tuple[int, int]:
    return (int(math.floor(float(wm_x) / CELL_WM)), int(math.floor(float(wm_y) / CELL_WM)))


def latlon_to_cell(lat: float, lon: float) -> Tuple[int, int]:
    x, y = latlon_to_wm(lat, lon)
    return wm_to_cell(x, y)


def wm_to_tile(wm_x: float, wm_y: float) -> Tuple[int, int]:
    return (int(math.floor(float(wm_x) / TILE_WM)), int(math.floor(float(wm_y) / TILE_WM)))


def latlon_to_tile(lat: float, lon: float) -> Tuple[int, int]:
    x, y = latlon_to_wm(lat, lon)
    return wm_to_tile(x, y)


def cell_center_latlon(cell_x: int, cell_y: int) -> Tuple[float, float]:
    cx = (float(cell_x) + 0.5) * CELL_WM
    cy = (float(cell_y) + 0.5) * CELL_WM
    return wm_to_latlon(cx, cy)


def ground_distance_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    phi1 = math.radians(float(lat1))
    phi2 = math.radians(float(lat2))
    delta_phi = math.radians(float(lat2) - float(lat1))
    delta_lambda = math.radians(float(lon2) - float(lon1))

    a = (
        math.sin(delta_phi / 2.0) * math.sin(delta_phi / 2.0)
        + math.cos(phi1) * math.cos(phi2) * math.sin(delta_lambda / 2.0) * math.sin(delta_lambda / 2.0)
    )
    c = 2.0 * math.atan2(math.sqrt(a), math.sqrt(max(0.0, 1.0 - a)))
    return EARTH_MEAN_R * c


def cells_within_ground_radius(
    lat: float, lon: float, radius_m: float = 60.0
) -> List[Tuple[int, int]]:
    primary_x, primary_y = latlon_to_cell(lat, lon)
    wm_px, wm_py = latlon_to_wm(lat, lon)
    result: List[Tuple[int, int]] = []

    if radius_m >= 0.0:
        result.append((primary_x, primary_y))

    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if dx == 0 and dy == 0:
                continue
            cx = primary_x + dx
            cy = primary_y + dy
            min_x = float(cx) * CELL_WM
            max_x = float(cx + 1) * CELL_WM
            min_y = float(cy) * CELL_WM
            max_y = float(cy + 1) * CELL_WM
            closest_x = _clamp(wm_px, min_x, max_x)
            closest_y = _clamp(wm_py, min_y, max_y)
            c_lat, c_lon = wm_to_latlon(closest_x, closest_y)
            dist = ground_distance_m(lat, lon, c_lat, c_lon)
            if dist <= radius_m:
                result.append((cx, cy))

    return result
