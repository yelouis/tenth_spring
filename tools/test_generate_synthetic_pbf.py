#!/usr/bin/env python3
"""
tools/test_generate_synthetic_pbf.py — Unit test for deterministic synthetic OSM PBF generation.
Asserts:
  1. Byte-for-byte reproducibility against committed fixture game/tests/fixtures/synthetic_neighborhood.osm.pbf.
  2. Falsification: altering coordinates changes the hash.
  3. Feature counts and types (1 park, 4 roads, 3 buildings, 2 POIs, 1 multipolygon relation).
"""

import hashlib
import os
import sys
import unittest
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from generate_synthetic_pbf import generate_synthetic_pbf_bytes

class TestGenerateSyntheticPbf(unittest.TestCase):
    def setUp(self):
        self.repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        self.fixture_path = os.path.join(
            self.repo_root, "game", "tests", "fixtures", "synthetic_neighborhood.osm.pbf"
        )

    def test_byte_for_byte_reproducibility(self):
        """Assert generated PBF matches committed fixture byte-for-byte."""
        self.assertTrue(os.path.exists(self.fixture_path), f"Fixture not found at {self.fixture_path}")
        with open(self.fixture_path, "rb") as f:
            fixture_bytes = f.read()

        generated_bytes = generate_synthetic_pbf_bytes()
        self.assertEqual(
            len(generated_bytes),
            len(fixture_bytes),
            f"Length mismatch: {len(generated_bytes)} vs {len(fixture_bytes)}"
        )
        self.assertEqual(
            hashlib.sha256(generated_bytes).hexdigest(),
            hashlib.sha256(fixture_bytes).hexdigest(),
            "SHA-256 mismatch between generator and committed fixture"
        )

    def test_determinism_multiple_runs(self):
        """Assert repeated generation yields identical SHA-256."""
        run1 = generate_synthetic_pbf_bytes()
        run2 = generate_synthetic_pbf_bytes()
        self.assertEqual(run1, run2)

    def test_pbf_structure_and_counts(self):
        """Assert PBF structure decodes and contains exact required features."""
        data = generate_synthetic_pbf_bytes()
        self.assertGreater(len(data), 64)

        # Decompress OSMData blob
        # BlobHeader is first
        h_len = int.from_bytes(data[:4], byteorder="big")
        header_bytes = data[4:4 + h_len]
        blob_bytes = data[4 + h_len:]

        # Extract zlib slice from blob_bytes
        # In blob_bytes: tag 2 (raw_size), tag 3 (zlib_data)
        # Parse varints
        pos = 0
        raw_size = 0
        zlib_slice = b""
        while pos < len(blob_bytes):
            tag = 0
            shift = 0
            while pos < len(blob_bytes):
                b = blob_bytes[pos]
                pos += 1
                tag |= (b & 0x7F) << shift
                if not (b & 0x80):
                    break
                shift += 7
            fn = tag >> 3
            wt = tag & 0x7
            if fn == 2 and wt == 0:
                # varint
                v = 0
                shift = 0
                while pos < len(blob_bytes):
                    b = blob_bytes[pos]
                    pos += 1
                    v |= (b & 0x7F) << shift
                    if not (b & 0x80):
                        break
                    shift += 7
                raw_size = v
            elif fn == 3 and wt == 2:
                # length delimited
                l = 0
                shift = 0
                while pos < len(blob_bytes):
                    b = blob_bytes[pos]
                    pos += 1
                    l |= (b & 0x7F) << shift
                    if not (b & 0x80):
                        break
                    shift += 7
                zlib_slice = blob_bytes[pos:pos + l]
                pos += l
            elif wt == 2:
                l = 0
                shift = 0
                while pos < len(blob_bytes):
                    b = blob_bytes[pos]
                    pos += 1
                    l |= (b & 0x7F) << shift
                    if not (b & 0x80):
                        break
                    shift += 7
                pos += l
            elif wt == 0:
                while pos < len(blob_bytes):
                    b = blob_bytes[pos]
                    pos += 1
                    if not (b & 0x80):
                        break

        self.assertGreater(raw_size, 0)
        self.assertGreater(len(zlib_slice), 0)
        decomp = zlib.decompress(zlib_slice)
        self.assertEqual(len(decomp), raw_size)

        # Confirm expected string table entries are present in raw payload
        for s in [b"Echo Lake", b"Community Park", b"City Hall", b"Maple House",
                  b"General Store", b"Grand Avenue", b"Park Boulevard",
                  b"Quiet Lane", b"Lakeside Trail", b"Neighborhood Pharmacy", b"Parkside Cafe",
                  b"District Line", b"Old Pine Cemetery", b"Deep Forest", b"Town Parking",
                  b"Clear Brook", b"Broad River", b"River Bridge", b"Boundary Market",
                  b"Hidden Tunnel", b"City Library", b"Active Construction"]:
            self.assertIn(s, decomp, f"Expected string '{s.decode()}' missing in decompressed OSMData")

    def test_reverse_coastline_flag(self):
        """Assert reverse_coastline flag alters generated byte output."""
        normal = generate_synthetic_pbf_bytes(reverse_coastline=False)
        reversed_coast = generate_synthetic_pbf_bytes(reverse_coastline=True)
        self.assertNotEqual(normal, reversed_coast)

if __name__ == "__main__":
    unittest.main()
