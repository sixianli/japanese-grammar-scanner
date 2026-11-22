import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from require_version_not_lower import problem


class RequireVersionNotLowerTests(unittest.TestCase):
    def test_lower_than_existing_is_rejected(self):
        message = problem("1.0", ["1.1", "1.3", "1.0"])
        self.assertIsNotNone(message)
        self.assertIn("1.3", message)

    def test_equal_to_highest_is_allowed(self):
        self.assertIsNone(problem("1.3", ["1.1", "1.3"]))

    def test_higher_is_allowed(self):
        self.assertIsNone(problem("1.4", ["1.0", "1.3"]))

    def test_compares_numerically_not_as_text(self):
        self.assertIsNone(problem("1.10", ["1.9"]))
        self.assertIsNotNone(problem("1.9", ["1.10"]))

    def test_no_existing_versions_is_allowed(self):
        self.assertIsNone(problem("1.0", []))


if __name__ == "__main__":
    unittest.main()
