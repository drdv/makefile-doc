"""Tests of test/tools/release.py (standard library only; see test_run.py for how to run them)."""

import contextlib
import importlib.util
import io
import sys
import tempfile
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parent

# release.py is not a package: load it from its file
_spec = importlib.util.spec_from_file_location("release", TOOLS / "release.py")
release = importlib.util.module_from_spec(_spec)
sys.modules.setdefault("release", release)
_spec.loader.exec_module(release)

SCRIPT = 'BEGIN {\n  VERSION = "v1.9" # the only place where the version is defined\n}\n'
README = "help: VER := v1.9\nhelp: URL := https://...\n"


class TestRelease(unittest.TestCase):
    """Each test has its own copies of the awk script and the README (release.ROOT)."""

    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        (self.root / release.AWK_SCRIPT).write_text(SCRIPT)
        (self.root / release.README).write_text(README)
        root, release.ROOT = release.ROOT, self.root
        self.addCleanup(setattr, release, "ROOT", root)

    def text(self, name: str) -> str:
        return (self.root / name).read_text()

    def run_quietly(self, function, *args) -> None:
        with contextlib.redirect_stdout(io.StringIO()):
            function(*args)

    def test_bump(self) -> None:
        self.run_quietly(release.bump, "v1.10")
        self.assertEqual(self.text(release.AWK_SCRIPT), SCRIPT.replace("v1.9", "v1.10"))
        self.assertEqual(self.text(release.README), README.replace("v1.9", "v1.10"))

    def test_bump_invalid_version(self) -> None:
        for version in ["1.10", "v1.10.1", "v1", ""]:
            with self.subTest(version=version):
                with self.assertRaisesRegex(release.ReleaseError, "invalid version"):
                    release.bump(version)
        self.assertEqual(self.text(release.AWK_SCRIPT), SCRIPT)  # nothing was written

    def test_check(self) -> None:
        self.run_quietly(release.check, "v1.9")
        with self.assertRaisesRegex(release.ReleaseError, "tag v1.10, makefile-doc.awk v1.9"):
            release.check("v1.10")

        (self.root / release.README).write_text(README.replace("v1.9", "v1.8"))
        with self.assertRaisesRegex(release.ReleaseError, "README.md v1.8"):
            release.check("v1.9")


if __name__ == "__main__":
    unittest.main()
