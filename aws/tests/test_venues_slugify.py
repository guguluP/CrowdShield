"""
Unit tests for the venues Lambda's slugify() function.

Imports the REAL app.py module (mocking boto3 and setting the required
env var first) rather than duplicating the regex logic in the test file —
a duplicated copy would silently drift out of sync if app.py's slugify
implementation ever changes, defeating the point of the test.

Run: python3 -m pytest test_venues_slugify.py -v
     (or: python3 -m unittest test_venues_slugify.py -v)
"""

import os
import sys
import unittest
from unittest.mock import MagicMock, patch


class TestSlugify(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # app.py does `table = dynamodb.Table(os.environ["VENUES_TABLE"])`
        # at module import time, so both the env var and a mocked boto3
        # must be in place BEFORE the import happens.
        os.environ["VENUES_TABLE"] = "test-venues-table"

        src_dir = os.path.join(
            os.path.dirname(os.path.abspath(__file__)), "..", "src", "venues"
        )
        shared_dir = os.path.join(
            os.path.dirname(os.path.abspath(__file__)), "..", "src", "shared"
        )
        sys.path.insert(0, src_dir)
        sys.path.insert(0, shared_dir)

        cls._boto3_patcher = patch("boto3.resource", return_value=MagicMock())
        cls._boto3_patcher.start()

        import app  # noqa: E402  (import after path/env/mock setup is intentional)
        cls.app = app

    @classmethod
    def tearDownClass(cls):
        cls._boto3_patcher.stop()

    def test_simple_name(self):
        self.assertEqual(self.app.slugify("TechNova Festival Grounds"), "technova-festival-grounds")

    def test_extra_whitespace_collapsed(self):
        self.assertEqual(self.app.slugify("  Extra   Spaces  "), "extra-spaces")

    def test_punctuation_stripped(self):
        self.assertEqual(self.app.slugify("Café & Bar!!"), "caf-bar")

    def test_numbers_preserved(self):
        self.assertEqual(self.app.slugify("123 Main St."), "123-main-st")

    def test_symbols_only_produces_empty_string(self):
        # This is the exact input that _create() must reject with a 400 —
        # slugify() itself just returns "", the caller does the rejecting.
        self.assertEqual(self.app.slugify("___"), "")

    def test_single_character(self):
        self.assertEqual(self.app.slugify("a"), "a")

    def test_empty_string(self):
        self.assertEqual(self.app.slugify(""), "")

    def test_already_valid_slug_is_idempotent(self):
        # Running slugify on its own output should be a no-op — important
        # since venue names and existing venueIds may end up compared or
        # re-slugified in future code paths.
        once = self.app.slugify("Main Entrance Gate A")
        twice = self.app.slugify(once)
        self.assertEqual(once, twice)

    def test_leading_and_trailing_hyphens_stripped(self):
        self.assertEqual(self.app.slugify("-leading and trailing-"), "leading-and-trailing")

    def test_mixed_case_normalized_to_lowercase(self):
        self.assertEqual(self.app.slugify("UPPER lower MiXeD"), "upper-lower-mixed")

    def test_result_is_url_and_dynamodb_key_safe(self):
        # No character in the output should ever need URL escaping or
        # cause DynamoDB key issues — confirms the regex genuinely only
        # ever produces [a-z0-9-].
        import re
        result = self.app.slugify("Weird!!Name@@With##Symbols%%2026")
        self.assertRegex(result, r"^[a-z0-9-]*$")


if __name__ == "__main__":
    unittest.main()
