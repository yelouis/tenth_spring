#!/usr/bin/env python3
"""
tools/generate_synthetic_pbf.py — Deterministic synthetic OSM PBF generator.
Generates game/tests/fixtures/synthetic_neighborhood.osm.pbf.
Contains synthetic, made-up coordinates only near (0.01, 0.01) covering 4 cells.
Contains:
  - 1 park polygon
  - 4 road ways (primary, secondary, residential, path)
  - 3 building footprints
  - 2 POI place nodes (medical, grocery)
  - 1 multipolygon lake relation (with outer ring and inner island)
Uses Python 3 stdlib only (struct, zlib, math).
"""

import argparse
import math
import os
import struct
import sys
import zlib

WM_R = 6378137.0
CELL_WM = 256.0
TILE_WM = 16.0

def wm_to_latlon(x: float, y: float) -> tuple[float, float]:
    lat = math.degrees(2.0 * math.atan(math.exp(y / WM_R)) - math.pi / 2.0)
    lon = math.degrees(x / WM_R)
    return lat, lon

def cell_local_to_latlon(cx: int, cy: int, u: float, v: float) -> tuple[float, float]:
    x = cx * CELL_WM + u * TILE_WM
    y = cy * CELL_WM + v * TILE_WM
    return wm_to_latlon(x, y)

def encode_varint(val: int) -> bytes:
    if val < 0:
        val = (1 << 64) + val
    buf = bytearray()
    while True:
        b = val & 0x7F
        val >>= 7
        if val:
            buf.append(b | 0x80)
        else:
            buf.append(b)
            break
    return bytes(buf)

def encode_sint64(val: int) -> int:
    return (val << 1) ^ (val >> 63)

def make_tag(field_num: int, wire_type: int) -> bytes:
    return encode_varint((field_num << 3) | wire_type)

def make_bytes_field(field_num: int, data: bytes) -> bytes:
    return make_tag(field_num, 2) + encode_varint(len(data)) + data

def make_varint_field(field_num: int, val: int) -> bytes:
    return make_tag(field_num, 0) + encode_varint(val)

def make_string_field(field_num: int, s: str) -> bytes:
    return make_bytes_field(field_num, s.encode("utf-8"))

def make_packed_varints(field_num: int, values: list[int]) -> bytes:
    payload = b"".join(encode_varint(v) for v in values)
    return make_tag(field_num, 2) + encode_varint(len(payload)) + payload

def make_blob_record(blob_type: str, raw_data: bytes) -> bytes:
    # Fixed zlib compression level 6 for byte-for-byte reproducibility
    compressor = zlib.compressobj(level=6, wbits=15)
    zlib_data = compressor.compress(raw_data) + compressor.flush()
    blob_msg = make_varint_field(2, len(raw_data)) + make_bytes_field(3, zlib_data)
    header_msg = make_string_field(1, blob_type) + make_varint_field(3, len(blob_msg))
    return struct.pack(">I", len(header_msg)) + header_msg + blob_msg

class StringTable:
    def __init__(self):
        self.strings = [""]
        self.index = {"": 0}

    def get(self, s: str) -> int:
        if s not in self.index:
            idx = len(self.strings)
            self.strings.append(s)
            self.index[s] = idx
            return idx
        return self.index[s]

    def serialize(self) -> bytes:
        payload = bytearray()
        for s in self.strings:
            b = s.encode("utf-8")
            payload.extend(make_bytes_field(1, b))
        return bytes(payload)

def generate_synthetic_pbf_bytes(reverse_coastline: bool = False) -> bytes:
    st = StringTable()

    # Pre-register common tags for deterministic string table layout
    known_strings = [
        "natural", "water", "lake", "leisure", "park",
        "building", "yes", "residential", "retail", "commercial",
        "highway", "primary", "secondary", "path",
        "amenity", "pharmacy", "cafe", "library", "parking",
        "type", "multipolygon", "outer", "inner", "name",
        "coastline", "railway", "rail", "landuse", "cemetery",
        "forest", "waterway", "stream", "river", "bridge",
        "tunnel", "construction"
    ]
    for s in known_strings:
        st.get(s)

    nodes = []
    ways = []
    relations = []
    next_node_id = 1

    # 1. Park Polygon in Cell (5, 4): u in [2, 10], v in [2, 10]
    park_pts = [(2.0, 2.0), (10.0, 2.0), (10.0, 10.0), (2.0, 10.0)]
    park_node_ids = []
    for u, v in park_pts:
        nid = next_node_id
        next_node_id += 1
        lat, lon = cell_local_to_latlon(5, 4, u, v)
        nodes.append((nid, lat, lon, {}))
        park_node_ids.append(nid)
    park_node_ids.append(park_node_ids[0])
    ways.append({
        "id": 101,
        "tags": {"leisure": "park", "name": "Community Park"},
        "refs": park_node_ids
    })

    # 2. Building 1 in Cell (4, 4): u in [3, 7], v in [3, 7]
    b1_pts = [(3.0, 3.0), (7.0, 3.0), (7.0, 7.0), (3.0, 7.0)]
    b1_node_ids = []
    for u, v in b1_pts:
        nid = next_node_id
        next_node_id += 1
        lat, lon = cell_local_to_latlon(4, 4, u, v)
        nodes.append((nid, lat, lon, {}))
        b1_node_ids.append(nid)
    b1_node_ids.append(b1_node_ids[0])
    ways.append({
        "id": 102,
        "tags": {"building": "yes", "name": "City Hall"},
        "refs": b1_node_ids
    })

    # 3. Building 2 in Cell (5, 4): u in [11, 15], v in [3, 7]
    b2_pts = [(11.0, 3.0), (15.0, 3.0), (15.0, 7.0), (11.0, 7.0)]
    b2_node_ids = []
    for u, v in b2_pts:
        nid = next_node_id
        next_node_id += 1
        lat, lon = cell_local_to_latlon(5, 4, u, v)
        nodes.append((nid, lat, lon, {}))
        b2_node_ids.append(nid)
    b2_node_ids.append(b2_node_ids[0])
    ways.append({
        "id": 103,
        "tags": {"building": "residential", "name": "Maple House"},
        "refs": b2_node_ids
    })

    # 4. Building 3 in Cell (4, 5): u in [4, 8], v in [4, 8]
    b3_pts = [(4.0, 4.0), (8.0, 4.0), (8.0, 8.0), (4.0, 8.0)]
    b3_node_ids = []
    for u, v in b3_pts:
        nid = next_node_id
        next_node_id += 1
        lat, lon = cell_local_to_latlon(4, 5, u, v)
        nodes.append((nid, lat, lon, {}))
        b3_node_ids.append(nid)
    b3_node_ids.append(b3_node_ids[0])
    ways.append({
        "id": 104,
        "tags": {"building": "retail", "name": "General Store"},
        "refs": b3_node_ids
    })

    # 5. Lake Multipolygon in Cell (5, 5):
    # Outer ring: u in [2, 14], v in [2, 14]
    lake_outer_pts = [(2.0, 2.0), (14.0, 2.0), (14.0, 14.0), (2.0, 14.0)]
    lake_outer_node_ids = []
    for u, v in lake_outer_pts:
        nid = next_node_id
        next_node_id += 1
        lat, lon = cell_local_to_latlon(5, 5, u, v)
        nodes.append((nid, lat, lon, {}))
        lake_outer_node_ids.append(nid)
    lake_outer_node_ids.append(lake_outer_node_ids[0])
    ways.append({
        "id": 105,
        "tags": {},
        "refs": lake_outer_node_ids
    })

    # Inner ring (island): u in [6, 10], v in [6, 10]
    lake_inner_pts = [(6.0, 6.0), (10.0, 6.0), (10.0, 10.0), (6.0, 10.0)]
    lake_inner_node_ids = []
    for u, v in lake_inner_pts:
        nid = next_node_id
        next_node_id += 1
        lat, lon = cell_local_to_latlon(5, 5, u, v)
        nodes.append((nid, lat, lon, {}))
        lake_inner_node_ids.append(nid)
    lake_inner_node_ids.append(lake_inner_node_ids[0])
    ways.append({
        "id": 106,
        "tags": {},
        "refs": lake_inner_node_ids
    })

    relations.append({
        "id": 201,
        "tags": {
            "type": "multipolygon",
            "natural": "water",
            "water": "lake",
            "name": "Echo Lake"
        },
        "members": [
            (105, "outer", 1), # 1 = WAY
            (106, "inner", 1)
        ]
    })

    # 6. Road 1 in Cell (4, 4): highway=primary
    r1_pts = [(1.0, 8.0), (5.0, 8.0), (10.0, 8.0), (15.0, 8.0)]
    r1_node_ids = []
    for u, v in r1_pts:
        nid = next_node_id
        next_node_id += 1
        lat, lon = cell_local_to_latlon(4, 4, u, v)
        nodes.append((nid, lat, lon, {}))
        r1_node_ids.append(nid)
    ways.append({
        "id": 107,
        "tags": {"highway": "primary", "name": "Grand Avenue"},
        "refs": r1_node_ids
    })

    # 7. Road 2 in Cell (5, 4): highway=secondary
    r2_pts = [(8.0, 1.0), (8.0, 6.0), (8.0, 11.0), (8.0, 15.0)]
    r2_node_ids = []
    for u, v in r2_pts:
        nid = next_node_id
        next_node_id += 1
        lat, lon = cell_local_to_latlon(5, 4, u, v)
        nodes.append((nid, lat, lon, {}))
        r2_node_ids.append(nid)
    ways.append({
        "id": 108,
        "tags": {"highway": "secondary", "name": "Park Boulevard"},
        "refs": r2_node_ids
    })

    # 8. Road 3 in Cell (4, 5): highway=residential
    r3_pts = [(2.0, 2.0), (6.0, 2.0), (10.0, 2.0), (14.0, 2.0)]
    r3_node_ids = []
    for u, v in r3_pts:
        nid = next_node_id
        next_node_id += 1
        lat, lon = cell_local_to_latlon(4, 5, u, v)
        nodes.append((nid, lat, lon, {}))
        r3_node_ids.append(nid)
    ways.append({
        "id": 109,
        "tags": {"highway": "residential", "name": "Quiet Lane"},
        "refs": r3_node_ids
    })

    # 9. Road 4 in Cell (5, 5): highway=path
    r4_pts = [(1.0, 1.0), (5.0, 1.0), (10.0, 1.0), (15.0, 1.0)]
    r4_node_ids = []
    for u, v in r4_pts:
        nid = next_node_id
        next_node_id += 1
        lat, lon = cell_local_to_latlon(5, 5, u, v)
        nodes.append((nid, lat, lon, {}))
        r4_node_ids.append(nid)
    ways.append({
        "id": 110,
        "tags": {"highway": "path", "name": "Lakeside Trail"},
        "refs": r4_node_ids
    })

    # 10. POI 1 in Cell (4, 4): amenity=pharmacy
    poi1_id = next_node_id
    next_node_id += 1
    lat1, lon1 = cell_local_to_latlon(4, 4, 5.0, 5.0)
    nodes.append((poi1_id, lat1, lon1, {"amenity": "pharmacy", "name": "Neighborhood Pharmacy"}))

    # 11. POI 2 in Cell (5, 4): amenity=cafe
    poi2_id = next_node_id
    next_node_id += 1
    lat2, lon2 = cell_local_to_latlon(5, 4, 12.0, 12.0)
    nodes.append((poi2_id, lat2, lon2, {"amenity": "cafe", "name": "Parkside Cafe"}))

    # 12. Coastline: oriented with land to west, sea to east
    coast_pts = [
        cell_local_to_latlon(5, 4, 15.0, 1.0),
        cell_local_to_latlon(5, 4, 15.0, 15.0),
        cell_local_to_latlon(5, 5, 15.0, 15.0),
    ]
    coast_node_ids = []
    for lat, lon in coast_pts:
        nid = next_node_id
        next_node_id += 1
        nodes.append((nid, lat, lon, {}))
        coast_node_ids.append(nid)
    if reverse_coastline:
        coast_node_ids.reverse()
    ways.append({
        "id": 111,
        "tags": {"natural": "coastline"},
        "refs": coast_node_ids
    })

    # 13. Railway crossing a road (Grand Avenue in cell (4, 4) at v=8.0)
    rail_pts = [
        cell_local_to_latlon(4, 4, 7.0, 1.0),
        cell_local_to_latlon(4, 4, 7.0, 8.0),
        cell_local_to_latlon(4, 4, 7.0, 15.0),
    ]
    rail_node_ids = []
    for lat, lon in rail_pts:
        nid = next_node_id
        next_node_id += 1
        nodes.append((nid, lat, lon, {}))
        rail_node_ids.append(nid)
    ways.append({
        "id": 112,
        "tags": {"railway": "rail", "name": "District Line"},
        "refs": rail_node_ids
    })

    # 14. Named Cemetery polygon in Cell (4, 5)
    cemetery_pts = [(10.0, 10.0), (14.0, 10.0), (14.0, 14.0), (10.0, 14.0)]
    cemetery_node_ids = []
    for u, v in cemetery_pts:
        nid = next_node_id
        next_node_id += 1
        lat, lon = cell_local_to_latlon(4, 5, u, v)
        nodes.append((nid, lat, lon, {}))
        cemetery_node_ids.append(nid)
    cemetery_node_ids.append(cemetery_node_ids[0])
    ways.append({
        "id": 113,
        "tags": {"landuse": "cemetery", "name": "Old Pine Cemetery"},
        "refs": cemetery_node_ids
    })

    # 15. Forest polygon in Cell (4, 5)
    forest_pts = [(1.0, 10.0), (5.0, 10.0), (5.0, 14.0), (1.0, 14.0)]
    forest_node_ids = []
    for u, v in forest_pts:
        nid = next_node_id
        next_node_id += 1
        lat, lon = cell_local_to_latlon(4, 5, u, v)
        nodes.append((nid, lat, lon, {}))
        forest_node_ids.append(nid)
    forest_node_ids.append(forest_node_ids[0])
    ways.append({
        "id": 114,
        "tags": {"landuse": "forest", "name": "Deep Forest"},
        "refs": forest_node_ids
    })

    # 16. Parking lot in Cell (4, 4)
    parking_pts = [(10.0, 1.0), (14.0, 1.0), (14.0, 5.0), (10.0, 5.0)]
    parking_node_ids = []
    for u, v in parking_pts:
        nid = next_node_id
        next_node_id += 1
        lat, lon = cell_local_to_latlon(4, 4, u, v)
        nodes.append((nid, lat, lon, {}))
        parking_node_ids.append(nid)
    parking_node_ids.append(parking_node_ids[0])
    ways.append({
        "id": 115,
        "tags": {"amenity": "parking", "name": "Town Parking"},
        "refs": parking_node_ids
    })

    # 17. Stream crossing Quiet Lane in Cell (4, 5) without bridge tag
    stream_pts = [
        cell_local_to_latlon(4, 5, 8.0, 1.0),
        cell_local_to_latlon(4, 5, 8.0, 6.0),
    ]
    stream_node_ids = []
    for lat, lon in stream_pts:
        nid = next_node_id
        next_node_id += 1
        nodes.append((nid, lat, lon, {}))
        stream_node_ids.append(nid)
    ways.append({
        "id": 116,
        "tags": {"waterway": "stream", "name": "Clear Brook"},
        "refs": stream_node_ids
    })

    # 18. River crossed by a bridge=yes road in Cell (5, 4)
    river_pts = [
        cell_local_to_latlon(5, 4, 4.0, 1.0),
        cell_local_to_latlon(5, 4, 4.0, 15.0),
    ]
    river_node_ids = []
    for lat, lon in river_pts:
        nid = next_node_id
        next_node_id += 1
        nodes.append((nid, lat, lon, {}))
        river_node_ids.append(nid)
    ways.append({
        "id": 117,
        "tags": {"waterway": "river", "name": "Broad River"},
        "refs": river_node_ids
    })

    bridge_pts = [
        cell_local_to_latlon(5, 4, 1.0, 10.0),
        cell_local_to_latlon(5, 4, 7.0, 10.0),
    ]
    bridge_node_ids = []
    for lat, lon in bridge_pts:
        nid = next_node_id
        next_node_id += 1
        nodes.append((nid, lat, lon, {}))
        bridge_node_ids.append(nid)
    ways.append({
        "id": 118,
        "tags": {"highway": "primary", "bridge": "yes", "name": "River Bridge"},
        "refs": bridge_node_ids
    })

    # 19. Building straddling cell boundary x=1280 between Cell 4 and Cell 5
    straddle_pts_wm = [
        (1260.0, 1200.0),
        (1300.0, 1200.0),
        (1300.0, 1240.0),
        (1260.0, 1240.0),
    ]
    straddle_node_ids = []
    for x, y in straddle_pts_wm:
        nid = next_node_id
        next_node_id += 1
        lat, lon = wm_to_latlon(x, y)
        nodes.append((nid, lat, lon, {}))
        straddle_node_ids.append(nid)
    straddle_node_ids.append(straddle_node_ids[0])
    ways.append({
        "id": 119,
        "tags": {"building": "commercial", "name": "Boundary Market"},
        "refs": straddle_node_ids
    })

    # 20. Tunnel=yes road in Cell (4, 4) — excluded from store
    tunnel_pts = [
        cell_local_to_latlon(4, 4, 2.0, 14.0),
        cell_local_to_latlon(4, 4, 6.0, 14.0),
    ]
    tunnel_node_ids = []
    for lat, lon in tunnel_pts:
        nid = next_node_id
        next_node_id += 1
        nodes.append((nid, lat, lon, {}))
        tunnel_node_ids.append(nid)
    ways.append({
        "id": 120,
        "tags": {"highway": "residential", "tunnel": "yes", "name": "Hidden Tunnel"},
        "refs": tunnel_node_ids
    })

    # 21. Residential polygon with no buildings in Cell (4, 4)
    res_pts = [(1.0, 9.0), (5.0, 9.0), (5.0, 12.0), (1.0, 12.0)]
    res_node_ids = []
    for u, v in res_pts:
        nid = next_node_id
        next_node_id += 1
        lat, lon = cell_local_to_latlon(4, 4, u, v)
        nodes.append((nid, lat, lon, {}))
        res_node_ids.append(nid)
    res_node_ids.append(res_node_ids[0])
    ways.append({
        "id": 121,
        "tags": {"landuse": "residential"},
        "refs": res_node_ids
    })

    # 22. Named library POI inside Building 1 (City Hall) in Cell (4, 4)
    poi3_id = next_node_id
    next_node_id += 1
    lat3, lon3 = cell_local_to_latlon(4, 4, 5.0, 5.0)
    nodes.append((poi3_id, lat3, lon3, {"amenity": "library", "name": "City Library"}))

    # 23. Construction polygon in Cell (5, 4) — excluded per Decision 20
    const_pts = [(1.0, 12.0), (5.0, 12.0), (5.0, 15.0), (1.0, 15.0)]
    const_node_ids = []
    for u, v in const_pts:
        nid = next_node_id
        next_node_id += 1
        lat, lon = cell_local_to_latlon(5, 4, u, v)
        nodes.append((nid, lat, lon, {}))
        const_node_ids.append(nid)
    const_node_ids.append(const_node_ids[0])
    ways.append({
        "id": 122,
        "tags": {"landuse": "construction", "name": "Active Construction"},
        "refs": const_node_ids
    })

    nodes.sort(key=lambda n: n[0])

    header_block = (
        make_string_field(4, "OsmSchema-V0.6") +
        make_string_field(4, "DenseNodes") +
        make_string_field(16, "TenthSpring")
    )
    pbf_bytes = bytearray()
    pbf_bytes.extend(make_blob_record("OSMHeader", header_block))

    dense_id_deltas = []
    dense_lat_deltas = []
    dense_lon_deltas = []
    dense_keys_vals = []

    last_id = 0
    last_lat = 0
    last_lon = 0

    for nid, lat, lon, tags in nodes:
        lat_int = int(round(lat * 1e7))
        lon_int = int(round(lon * 1e7))

        dense_id_deltas.append(encode_sint64(nid - last_id))
        dense_lat_deltas.append(encode_sint64(lat_int - last_lat))
        dense_lon_deltas.append(encode_sint64(lon_int - last_lon))

        last_id = nid
        last_lat = lat_int
        last_lon = lon_int

        if tags:
            for k, v in sorted(tags.items()):
                dense_keys_vals.append(st.get(k))
                dense_keys_vals.append(st.get(v))
            dense_keys_vals.append(0)
        else:
            dense_keys_vals.append(0)

    dense_msg = (
        make_packed_varints(1, dense_id_deltas) +
        make_packed_varints(8, dense_lat_deltas) +
        make_packed_varints(9, dense_lon_deltas) +
        make_packed_varints(10, dense_keys_vals)
    )

    ways_bytes = bytearray()
    for w in sorted(ways, key=lambda x: x["id"]):
        w_keys = []
        w_vals = []
        for k, v in sorted(w["tags"].items()):
            w_keys.append(st.get(k))
            w_vals.append(st.get(v))
        ref_deltas = []
        last_ref = 0
        for r in w["refs"]:
            ref_deltas.append(encode_sint64(r - last_ref))
            last_ref = r

        way_msg = make_varint_field(1, w["id"])
        if w_keys:
            way_msg += make_packed_varints(2, w_keys)
            way_msg += make_packed_varints(3, w_vals)
        way_msg += make_packed_varints(8, ref_deltas)
        ways_bytes.extend(make_bytes_field(3, way_msg))

    rel_bytes = bytearray()
    for r in sorted(relations, key=lambda x: x["id"]):
        r_keys = []
        r_vals = []
        for k, v in sorted(r["tags"].items()):
            r_keys.append(st.get(k))
            r_vals.append(st.get(v))
        roles = []
        memids = []
        types = []
        last_mid = 0
        for mid, role, mtype in r["members"]:
            roles.append(st.get(role))
            memids.append(encode_sint64(mid - last_mid))
            last_mid = mid
            types.append(mtype)

        rel_msg = make_varint_field(1, r["id"])
        if r_keys:
            rel_msg += make_packed_varints(2, r_keys)
            rel_msg += make_packed_varints(3, r_vals)
        rel_msg += make_packed_varints(8, roles)
        rel_msg += make_packed_varints(9, memids)
        rel_msg += make_packed_varints(10, types)
        rel_bytes.extend(make_bytes_field(4, rel_msg))

    group_msg = make_bytes_field(2, dense_msg) + ways_bytes + rel_bytes
    st_bytes = st.serialize()
    block_msg = make_bytes_field(1, st_bytes) + make_bytes_field(2, group_msg)

    pbf_bytes.extend(make_blob_record("OSMData", block_msg))
    return bytes(pbf_bytes)

def main():
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    default_out = os.path.join(repo_root, "game", "tests", "fixtures", "synthetic_neighborhood.osm.pbf")

    parser = argparse.ArgumentParser(description="Generate deterministic synthetic OSM PBF fixture.")
    parser.add_argument("--out", default=default_out, help="Output path for .osm.pbf file")
    parser.add_argument("--reverse-coastline", action="store_true", help="Reverse coastline way orientation for falsification test")
    args = parser.parse_args()

    data = generate_synthetic_pbf_bytes(reverse_coastline=args.reverse_coastline)
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "wb") as f:
        f.write(data)
    print(f"Generated {len(data)} bytes to {args.out}")

if __name__ == "__main__":
    main()
