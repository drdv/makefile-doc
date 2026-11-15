#!/usr/bin/env python3
"""Manage the version and the releases of makefile-doc.

The version is defined in makefile-doc.awk and copied to the README; the release notes are
the message of the annotated tag (see "Releasing" in test/README.md).
"""

import sys

if sys.version_info < (3, 11):  # noqa: UP036 (a clear message instead of a traceback)
    sys.exit(f"Python >= 3.11 is needed (this is Python {sys.version.split()[0]})")

import argparse
import re
import shlex
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
AWK_SCRIPT = "makefile-doc.awk"
README = "README.md"
RELEASE_MESSAGE = "release-message.md"  # the release notes: the message of the tag

# the version lines: the same patterns read and write them (group 2 is the version)
AWK_SCRIPT_VERSION = re.compile(r'^(\s*VERSION = ")([^"]*)(".*)$', re.MULTILINE)
README_VERSION = re.compile(r"^(help: VER := )(\S*)()$", re.MULTILINE)
# a version: v<major>.<minor>, e.g. v1.10
VALID_VERSION = re.compile(r"^v\d+\.\d+$")


class ReleaseError(Exception):
    pass


def read_version(name: str, pattern: re.Pattern) -> str:
    """Read the version in a file.

    The pattern is AWK_SCRIPT_VERSION or README_VERSION (group 2 is the version).
    """
    return pattern.search((ROOT / name).read_text())[2]


def write_version(name: str, pattern: re.Pattern, version: str) -> None:
    """Replace the version in a file.

    The pattern is AWK_SCRIPT_VERSION or README_VERSION (group 2 is the version).
    """
    path = ROOT / name
    path.write_text(pattern.sub(lambda m: m[1] + version + m[3], path.read_text(), count=1))


def git(*args: str) -> str:
    """Run a git command in the repository and return its output.

    A failure raises CalledProcessError (main prints the output of git).
    """
    proc = subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True, check=True)
    return proc.stdout


def notes() -> None:
    """Write a draft of the release notes to release-message.md.

    The draft lists the commits since the last tag; edit it before `bump`. An existing
    release-message.md is not overwritten.
    """
    path = ROOT / RELEASE_MESSAGE
    if path.exists():
        raise ReleaseError(f"{RELEASE_MESSAGE} exists (edit it, or delete it to start over)")

    try:
        last_tag = git("describe", "--tags", "--abbrev=0").strip()
    except subprocess.CalledProcessError:  # no tag yet: all the commits
        last_tag = ""
    commits = git("log", "--pretty=format:- %s (%h)", f"{last_tag}..HEAD" if last_tag else "HEAD")

    since = f" since {last_tag}" if last_tag else ""
    path.write_text(f"A one-line summary of the release\n\n## Changes{since}\n\n{commits}\n")
    print(f"notes: {RELEASE_MESSAGE} written; edit it, then `make bump V=...`")


def bump(version: str) -> None:
    """Set a new version (e.g., v1.10) in the awk script and the README.

    With release-message.md, also commit the two files and create an annotated tag with
    release-message.md as its message, then delete it.
    """
    if not VALID_VERSION.match(version):
        raise ReleaseError(f"invalid version {version!r} (expected e.g. v1.10)")

    old = read_version(AWK_SCRIPT, AWK_SCRIPT_VERSION)
    write_version(AWK_SCRIPT, AWK_SCRIPT_VERSION, version)
    write_version(README, README_VERSION, version)

    message = ROOT / RELEASE_MESSAGE
    if not message.exists():
        if old != version:
            print(f"bump: {version} set in {AWK_SCRIPT} and {README} (not committed)")
        else:
            print(f"bump: {AWK_SCRIPT} and {README} are already at {version} (nothing changed)")
        if git("tag", "--list", version):
            print(f"tag {version} exists; to publish it: git push && git push origin {version}")
        else:
            print(f"to commit and tag {version}:")
            print("  make release-notes")
            print(f"  edit {RELEASE_MESSAGE}")
            print(f"  make bump V={version}")
        return

    # commit only the two files (not other staged changes)
    # --cleanup=whitespace keeps the lines starting with # (git removes them by default)
    git("commit", "-m", f"Release {version}", AWK_SCRIPT, README)
    git("tag", "-a", version, "-F", RELEASE_MESSAGE, "--cleanup=whitespace")
    message.unlink()
    print(f"bump: {version}, committed and tagged ({RELEASE_MESSAGE}, now deleted); now push:")
    print(f"  git push && git push origin {version}")


def check(tag: str) -> None:
    """Verify that the tag, the awk script and the README have the same version.

    Run by .github/workflows/release.yml with the pushed tag.
    """
    script = read_version(AWK_SCRIPT, AWK_SCRIPT_VERSION)
    readme = read_version(README, README_VERSION)
    if not tag == script == readme:
        raise ReleaseError(f"tag {tag}, {AWK_SCRIPT} {script}, {README} {readme}")

    print(f"check: OK ({tag})")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("notes", help=notes.__doc__.splitlines()[0])
    commands.add_parser("bump", help=bump.__doc__.splitlines()[0]).add_argument("version")
    commands.add_parser("check", help=check.__doc__.splitlines()[0]).add_argument("tag")
    args = parser.parse_args()

    try:
        if args.command == "notes":
            notes()
        elif args.command == "bump":
            bump(args.version)
        elif args.command == "check":
            check(args.tag)
    except ReleaseError as e:
        print(f"{Path(__file__).name} {args.command}: {e}", file=sys.stderr)
        return 1
    except subprocess.CalledProcessError as e:
        print(f"{Path(__file__).name} {args.command}: {shlex.join(e.cmd)} failed:", file=sys.stderr)
        print(e.stdout + e.stderr, end="", file=sys.stderr)  # git explains on either
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
