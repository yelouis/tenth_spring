#!/usr/bin/env python3
"""
Unit and regression verification for F22: Test Save Isolation.

Validates that GDScript DB tests never touch the production save path
('user://tenth_spring.db'), that assert_test_safe() exists and guards it,
and that all DB test files configure isolated test paths and restore defaults.
"""

import os
import sys
import unittest

GAME_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

class TestF22SaveIsolation(unittest.TestCase):
    def test_db_gd_has_isolation_methods(self):
        db_path = os.path.join(GAME_DIR, "autoloads", "db.gd")
        with open(db_path, "r", encoding="utf-8") as f:
            code = f.read()

        self.assertIn("var DB_PATH:", code, "DB_PATH must be an instance variable")
        self.assertIn("var DB_TMP_PATH:", code, "DB_TMP_PATH must be an instance variable")
        self.assertIn("func configure_paths(", code, "configure_paths() method must exist")
        self.assertIn("func assert_test_safe(", code, "assert_test_safe() method must exist")
        self.assertIn("DEFAULT_DB_PATH", code, "assert_test_safe must guard against DEFAULT_DB_PATH")
        self.assertIn("DEFAULT_DB_TMP_PATH", code, "assert_test_safe must guard against DEFAULT_DB_TMP_PATH")

    def test_db_test_gd_isolated(self):
        test_path = os.path.join(GAME_DIR, "tests", "db_test.gd")
        with open(test_path, "r", encoding="utf-8") as f:
            code = f.read()

        self.assertIn("DB.configure_paths(", code, "db_test.gd must call DB.configure_paths()")
        self.assertIn("DB.assert_test_safe()", code, "db_test.gd must call DB.assert_test_safe()")
        self.assertIn("DB.configure_paths(DB.DEFAULT_DB_PATH, DB.DEFAULT_DB_TMP_PATH)", code)

    def test_idempotent_sync_test_gd_isolated(self):
        test_path = os.path.join(GAME_DIR, "tests", "idempotent_sync_test.gd")
        with open(test_path, "r", encoding="utf-8") as f:
            code = f.read()

        self.assertIn("DB.configure_paths(", code, "idempotent_sync_test.gd must call DB.configure_paths()")
        self.assertIn("DB.assert_test_safe()", code, "idempotent_sync_test.gd must call DB.assert_test_safe()")
        self.assertIn("DB.configure_paths(DB.DEFAULT_DB_PATH, DB.DEFAULT_DB_TMP_PATH)", code)

    def test_db_migration_test_gd_isolated(self):
        test_path = os.path.join(GAME_DIR, "tests", "db_migration_test.gd")
        with open(test_path, "r", encoding="utf-8") as f:
            code = f.read()

        self.assertIn("DB.configure_paths(", code, "db_migration_test.gd must call DB.configure_paths()")
        self.assertIn("DB.assert_test_safe()", code, "db_migration_test.gd must call DB.assert_test_safe()")
        self.assertIn("DB.configure_paths(DB.DEFAULT_DB_PATH, DB.DEFAULT_DB_TMP_PATH)", code)

    def test_db_legacy_import_test_gd_isolated(self):
        test_path = os.path.join(GAME_DIR, "tests", "db_legacy_import_test.gd")
        with open(test_path, "r", encoding="utf-8") as f:
            code = f.read()

        self.assertIn("DB.configure_paths(", code, "db_legacy_import_test.gd must call DB.configure_paths()")
        self.assertIn("DB.assert_test_safe()", code, "db_legacy_import_test.gd must call DB.assert_test_safe()")
        self.assertIn("DB.configure_paths(DB.DEFAULT_DB_PATH, DB.DEFAULT_DB_TMP_PATH)", code)

if __name__ == "__main__":
    unittest.main()
