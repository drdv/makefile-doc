"""Tests of test/tools/release.py (standard library only; see test_run.py for how to run them)."""

import contextlib
import importlib.util
import io
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

TOOLS = Path(__file__).resolve().parent

# release.py is not a package: load it from its file
_spec = importlib.util.spec_from_file_location("release", TOOLS / "release.py")
release = importlib.util.module_from_spec(_spec)
sys.modules.setdefault("release", release)
_spec.loader.exec_module(release)

SCRIPT = 'BEGIN {\n  VERSION = "v1.9" # the only place where the version is defined\n}\n'
README = "help: VER := v1.9\nhelp: URL := https://...\n"
GIT_ENV = {
    "GIT_AUTHOR_NAME": "t",
    "GIT_AUTHOR_EMAIL": "t@t",
    "GIT_COMMITTER_NAME": "t",
    "GIT_COMMITTER_EMAIL": "t@t",
}


class TestRelease(unittest.TestCase):
    """Each test has its own git repository (release.ROOT) with the awk script and the README
    at v1.9, committed."""

    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        root, release.ROOT = release.ROOT, self.root
        self.addCleanup(setattr, release, "ROOT", root)
        patcher = mock.patch.dict(os.environ, GIT_ENV)
        patcher.start()
        self.addCleanup(patcher.stop)

        (self.root / release.AWK_SCRIPT).write_text(SCRIPT)
        (self.root / release.README).write_text(README)
        self.git("init", "-q", "-b", "main")
        self.git("add", ".")
        self.git("commit", "-q", "-m", "Release v1.9")

    def git(self, *args: str) -> str:
        return subprocess.run(
            ["git", *args], cwd=self.root, capture_output=True, text=True, check=True
        ).stdout

    def text(self, name: str) -> str:
        return (self.root / name).read_text()

    def output(self, function, *args) -> str:
        """The output of a function of release.py."""
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            function(*args)
        return out.getvalue()

    def test_bump(self) -> None:
        out = self.output(release.bump, "v1.10")
        self.assertEqual(self.text(release.AWK_SCRIPT), SCRIPT.replace("v1.9", "v1.10"))
        self.assertEqual(self.text(release.README), README.replace("v1.9", "v1.10"))
        self.assertIn("v1.10 set in makefile-doc.awk and README.md (not committed)", out)
        self.assertIn("make release-notes; edit release-message.md; make bump V=v1.10", out)
        # nothing was committed or tagged
        self.assertEqual(self.git("log", "-1", "--format=%s").strip(), "Release v1.9")
        self.assertEqual(self.git("tag", "--list"), "")

    def test_bump_same_version(self) -> None:
        out = self.output(release.bump, "v1.9")
        self.assertIn("already at v1.9 (nothing changed)", out)
        self.assertIn("make bump V=v1.9", out)

        self.git("tag", "-a", "v1.9", "-m", "v1.9")
        out = self.output(release.bump, "v1.9")
        self.assertIn("tag v1.9 exists; next: git push -u origin main v1.9", out)

    def test_bump_invalid_version(self) -> None:
        for version in ["1.10", "v1.10.1", "v1", ""]:
            with self.subTest(version=version):
                with self.assertRaisesRegex(release.ReleaseError, "invalid version"):
                    release.bump(version)
        self.assertEqual(self.text(release.AWK_SCRIPT), SCRIPT)  # nothing was written

    def test_bump_with_release_message(self) -> None:
        notes = "Summary\n\n## Changes\n\n- Fix a bug\n"
        (self.root / release.RELEASE_MESSAGE).write_text(notes)
        (self.root / "staged").write_text("x")
        self.git("add", "staged")

        out = self.output(release.bump, "v1.10")
        self.assertEqual(self.git("log", "-1", "--format=%s").strip(), "Release v1.10")
        committed = self.git("show", "--name-only", "--format=", "HEAD").split()
        self.assertEqual(sorted(committed), [release.README, release.AWK_SCRIPT])
        # the message of the annotated tag, with its Markdown heading
        self.assertEqual(self.git("tag", "-l", "--format=%(contents)", "v1.10"), notes + "\n")
        self.assertEqual(self.git("cat-file", "-t", "v1.10").strip(), "tag")
        self.assertFalse((self.root / release.RELEASE_MESSAGE).exists())
        self.assertIn("next: git push -u origin main v1.10", out)

    def test_notes(self) -> None:
        self.git("tag", "-a", "v1.9", "-m", "v1.9")
        (self.root / "other").write_text("x")
        self.git("add", "other")
        self.git("commit", "-q", "-m", "Fix a bug")

        self.output(release.notes)
        text = self.text(release.RELEASE_MESSAGE)
        self.assertIn("## Changes since v1.9", text)
        self.assertIn("- Fix a bug (", text)
        self.assertNotIn("Release v1.9", text)  # only the commits since the last tag
        with self.assertRaisesRegex(release.ReleaseError, "exists"):
            release.notes()

    def test_check(self) -> None:
        self.output(release.check, "v1.9")
        with self.assertRaisesRegex(release.ReleaseError, "tag v1.10, makefile-doc.awk v1.9"):
            release.check("v1.10")

        (self.root / release.README).write_text(README.replace("v1.9", "v1.8"))
        with self.assertRaisesRegex(release.ReleaseError, "README.md v1.8"):
            release.check("v1.9")


if __name__ == "__main__":
    unittest.main()
