import sys
import unittest
from decimal import Decimal
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "lib"))

from sbc_shared.coverage import CoverageError, find_line_coverage, percentage


class CoverageCalculationTest(unittest.TestCase):
    def test_finds_nested_line_coverage(self):
        value = find_line_coverage({"result": {"line": 91.25}})

        self.assertEqual(value, Decimal("91.25"))

    def test_rejects_negative_percentage(self):
        with self.assertRaises(CoverageError):
            percentage("-0.1", "COVERAGE_TOLERANCE")


if __name__ == "__main__":
    unittest.main()
