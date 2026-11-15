#!/usr/bin/env python3
"""Manage the version of makefile-doc: it is defined in makefile-doc.awk (`VERSION = "v1.9"`),
and the install snippet of the README (`help: VER := v1.9`) is a copy of it.

usage: test/tools/release.py bump VERSION
       test/tools/release.py check TAG

`bump` sets a new version (e.g., v1.10) in the awk script and the README; `check` verifies
that the tag, the awk script and the README have the same version (run by
.github/workflows/release.yml).

A release: `make bump V=v1.10`, commit, create an annotated tag (`git tag -a v1.10 -m
v1.10`), push the commit and the tag. The tag runs the tests, `check`, and creates a draft
GitHub release with makefile-doc.awk and its checksum, to publish on GitHub.

Only the Python standard library is used (Python >= 3.11).
"""

import sys

if sys.version_info < (3, 11):  # noqa: UP036 (a clear message instead of a traceback)
    sys.exit(f"Python >= 3.11 is needed (this is Python {sys.version.split()[0]})")

import argparse
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
AWK_SCRIPT = "makefile-doc.awk"
README = "README.md"

# the version lines: the same patterns read and write them (group 2 is the version)
AWK_SCRIPT_VERSION = re.compile(r'^(\s*VERSION = ")([^"]*)(".*)$', re.MULTILINE)
README_VERSION = re.compile(r"^(help: VER := )(\S*)()$", re.MULTILINE)
# a version: v<major>.<minor>, e.g. v1.10
VALID_VERSION = re.compile(r"^v\d+\.\d+$")


class ReleaseError(Exception):
    pass


def read_version(name: str, pattern: re.Pattern) -> str:
    """The version in a file."""
    return pattern.search((ROOT / name).read_text())[2]


def write_version(name: str, pattern: re.Pattern, version: str) -> None:
    """Replace the version in a file."""
    path = ROOT / name
    path.write_text(pattern.sub(lambda m: m[1] + version + m[3], path.read_text(), count=1))


def bump(version: str) -> None:
    """Set a new version (e.g., v1.10) in the awk script and the README."""
    if not VALID_VERSION.match(version):
        raise ReleaseError(f"invalid version {version!r} (expected e.g. v1.10)")

    write_version(AWK_SCRIPT, AWK_SCRIPT_VERSION, version)
    write_version(README, README_VERSION, version)
    print(f"bump: {version} ({AWK_SCRIPT}, {README}); now commit, tag and push")


def check(tag: str) -> None:
    """Verify that the tag, the awk script and the README have the same version."""
    script = read_version(AWK_SCRIPT, AWK_SCRIPT_VERSION)
    readme = read_version(README, README_VERSION)
    if not tag == script == readme:
        raise ReleaseError(f"tag {tag}, {AWK_SCRIPT} {script}, {README} {readme}")

    print(f"check: OK ({tag})")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("bump", help=bump.__doc__).add_argument("version")
    commands.add_parser("check", help=check.__doc__).add_argument("tag")
    args = parser.parse_args()

    try:
        if args.command == "bump":
            bump(args.version)
        elif args.command == "check":
            check(args.tag)
    except ReleaseError as e:
        print(f"{Path(__file__).name} {args.command}: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
