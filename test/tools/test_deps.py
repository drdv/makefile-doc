"""Tests of test/tools/deps.py (standard library only; see test_run.py for how to run them)."""

import importlib.util
import sys
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parent

# deps.py is not a package: load it from its file
_spec = importlib.util.spec_from_file_location("deps", TOOLS / "deps.py")
deps = importlib.util.module_from_spec(_spec)
sys.modules["deps"] = deps
_spec.loader.exec_module(deps)


class TestReportedVersion(unittest.TestCase):
    def test_outputs_of_awk_variants(self) -> None:
        cases = {
            "GNU Awk 5.3.2, API 4.0, PMA Avon 8-g1, (GNU MPFR 4.2.1, GNU MP 6.3.0)": "5.3.2",
            "mawk 1.3.4 20260302\nCopyright 2008-2025,2026, Thomas E. Dickey": "1.3.4 20260302",
            "awk version 20240728": "20240728",
            "v1.30.0": "v1.30.0",
            "awk: unrecognized option '--version'\nBusyBox v1.35.0 multi-call binary.": "v1.35.0",
        }
        for output, version in cases.items():
            with self.subTest(output=output):
                self.assertEqual(deps.reported_version(output), version)

    def test_no_version(self) -> None:
        self.assertEqual(deps.reported_version("usage: awk [-F fs] prog [file ...]\n"), "")


class TestMatches(unittest.TestCase):
    def test_same_version(self) -> None:
        self.assertTrue(deps.matches("20260302", "1.3.4 20260302"))
        self.assertTrue(deps.matches("1.30.0", "v1.30.0"))
        self.assertTrue(deps.matches("20240728", "20240728"))

    def test_other_version(self) -> None:
        self.assertFalse(deps.matches("20260302", "1.3.4 20240123"))
        self.assertFalse(deps.matches("1.35.0", "v1.36.1"))
        # not a prefix or a part of another version
        self.assertFalse(deps.matches("1.3", "1.3.4 20260302"))
        self.assertFalse(deps.matches("1.30.0", "v1.30.01"))

    def test_system_awk_has_no_pinned_version(self) -> None:
        self.assertFalse(deps.matches("", "5.3.2"))


class TestPinnedVersion(unittest.TestCase):
    def test_prefix_is_removed(self) -> None:
        for name, awk in deps.AWKS.items():
            with self.subTest(name=name):
                pinned = deps.pinned_version(name)
                if awk.get("system"):
                    self.assertEqual(pinned, "")
                else:
                    self.assertRegex(pinned, r"^\d")


if __name__ == "__main__":
    unittest.main()
