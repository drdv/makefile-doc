#!/usr/bin/env python3
"""Download what the tests need, as described in test/tools/deps.toml.

usage: test/tools/deps.py list
       test/tools/deps.py install VARIANT [VARIANT ...]
       test/tools/deps.py versions

`list` prints the awk variants; `install` builds test/bin/VARIANT (if it does not exist
yet). Downloads are kept in test/bin/ and checked against their sha256. `versions` prints
the version that each installed variant reports, and flags those that differ from the
version in deps.toml (an old build: `install` does not rebuild an existing variant).

Only the Python standard library is used (Python >= 3.11).
"""

import sys

if sys.version_info < (3, 11):  # noqa: UP036 (a clear message instead of a traceback)
    sys.exit(f"Python >= 3.11 is needed (this is Python {sys.version.split()[0]})")

import hashlib
import os
import platform
import re
import shutil
import subprocess
import time
import tomllib
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
BIN = ROOT / "test" / "bin"
DEPS = tomllib.loads((ROOT / "test" / "tools" / "deps.toml").read_text())
AWKS = DEPS["awk"]
BENCH_MAKEFILES = DEPS["bench"]


class DepsError(Exception):
    pass


def fetch(url: str, attempts: int = 4) -> bytes:
    """Download url, retrying with growing pauses on rate limits and server errors."""
    for attempt in range(1, attempts + 1):
        try:
            with urllib.request.urlopen(url, timeout=60) as response:
                return response.read()
        except urllib.error.HTTPError as e:
            if e.code != 429 and e.code < 500 or attempt == attempts:
                raise
            retry_after = e.headers.get("Retry-After", "")
            pause = int(retry_after) if retry_after.isdigit() else 2**attempt
        except urllib.error.URLError:
            if attempt == attempts:
                raise
            pause = 2**attempt
        print(f"  retrying in {pause} s", file=sys.stderr)
        time.sleep(pause)
    raise AssertionError("unreachable")


def download(urls: list[str], path: Path, sha256: str) -> Path:
    """Download path (once), trying the urls in turn, and check its sha256."""
    if path.exists():
        return path
    path.parent.mkdir(parents=True, exist_ok=True)
    errors = []
    for url in urls:
        print(f"downloading {url}", file=sys.stderr)
        try:
            data = fetch(url)
        except (urllib.error.URLError, OSError) as e:
            errors.append(f"{url}: {e}")
            continue
        digest = hashlib.sha256(data).hexdigest()
        if not sha256:  # nothing unverified is installed
            raise DepsError(
                f"no sha256 to check {path.name}: if the download is trusted, "
                f'set sha256 = "{digest}" in test/tools/deps.toml'
            )
        if digest != sha256:
            errors.append(f"{url}: wrong sha256 {digest} (expected {sha256})")
            continue
        tmp = path.with_name(path.name + ".tmp")  # an interrupted write leaves no path
        tmp.write_bytes(data)
        os.replace(tmp, path)
        return path
    raise DepsError(f"cannot download {path.name}:\n  " + "\n  ".join(errors))


def place(source: Path, target: Path) -> None:
    """Copy source to target as an executable. The copy goes through a temporary name, so
    that an interrupted copy does not leave a partial target (it would look installed)."""
    tmp = target.with_name(target.name + ".tmp")
    shutil.copy(source, tmp)
    tmp.chmod(0o755)
    os.replace(tmp, target)


def install(name: str) -> Path:
    """Build test/bin/<name> (if it does not exist yet) and return its path."""
    if name not in AWKS:
        raise DepsError(f"unknown awk variant {name!r} (supported: {' '.join(AWKS)})")
    awk, target = AWKS[name], BIN / name
    if target.exists():
        return target
    if "os" in awk and platform.system() != awk["os"]:
        raise DepsError(f"{name} can only be installed on {awk['os']}")
    if "arch" in awk and platform.machine() not in awk["arch"]:
        raise DepsError(
            f"{name} can only be installed on {' or '.join(awk['arch'])} "
            f"(this is {platform.machine()})"
        )
    BIN.mkdir(parents=True, exist_ok=True)
    if target.is_symlink():  # a link to a system awk that does not exist anymore
        target.unlink()

    if awk.get("system"):
        path = shutil.which(name)
        if not path:
            raise DepsError(f"{name} is not installed")
        target.symlink_to(path)
        return target

    url = awk["url"].format(version=awk["version"])
    if "build" not in awk:  # a prebuilt binary
        place(download([url], BIN / f"{name}-{awk['version']}", awk["sha256"]), target)
        return target

    archive = download([url], BIN / f"{name}-{awk['version']}.tar.gz", awk["sha256"])
    src = BIN / f"{name}-src"
    shutil.rmtree(src, ignore_errors=True)
    src.mkdir()
    try:
        subprocess.run(["tar", "xzf", archive, "-C", src, "--strip-components=1"], check=True)
        subprocess.run(awk["build"], shell=True, cwd=src, check=True)
    except subprocess.CalledProcessError as e:
        raise DepsError(f"cannot build {name}: {e}") from e
    place(src / awk["binary"], target)
    return target


# the options that make an awk print its version, tried in turn: gawk, mawk, nawk, goawk (Go
# flags accept --version) and others answer --version; busybox prints its banner with an
# error; mawk also answers -W version
VERSION_OPTIONS = [["--version"], ["-W", "version"]]
# a version in the output: 5.3.2, 1.3.4 20260302, v1.30.0, 20240728
VERSION = re.compile(r"\bv?\d+\.\d+(?:\.\d+)?(?: \d{8})?\b|\b\d{8}\b")


def reported_version(output: str) -> str:
    """The first version in the output of an awk (e.g., `mawk 1.3.4 20260302` gives
    "1.3.4 20260302", `awk version 20240728` gives "20240728"), or "" if there is none."""
    for line in output.splitlines():
        match = VERSION.search(line)
        if match:
            return match.group()
    return ""


def pinned_version(name: str) -> str:
    """The version of a variant in deps.toml without its prefix (t20260302 gives 20260302),
    or "" for a system awk."""
    return re.sub(r"^[vt](?=\d)", "", AWKS[name].get("version", ""))


def matches(pinned: str, reported: str) -> bool:
    """Whether the reported version is the pinned one (e.g., "20260302" in "1.3.4 20260302",
    "1.30.0" in "v1.30.0")."""
    return (
        bool(pinned) and re.search(rf"(?<![\d.]){re.escape(pinned)}(?![\d.])", reported) is not None
    )


def installed_version(path: Path) -> str:
    """The version that an installed awk reports ("?" if none of VERSION_OPTIONS works)."""
    for options in VERSION_OPTIONS:
        try:
            proc = subprocess.run(
                [path, *options],
                stdin=subprocess.DEVNULL,
                capture_output=True,
                text=True,
                errors="replace",
                timeout=5,
                check=False,
            )
        except (OSError, subprocess.TimeoutExpired):
            continue
        version = reported_version(proc.stdout + "\n" + proc.stderr)
        if version:
            return version
    return "?"


def versions() -> int:
    """Print the installed variants with the version they report; return 1 if one differs
    from the version in deps.toml (a variant that reports no version is not compared)."""
    rows, stale = [], []
    for name in AWKS:
        path, pinned = BIN / name, pinned_version(name)
        if not path.exists():
            rows.append((name, pinned or "system", "not installed", ""))
            continue
        reported = installed_version(path)
        note = f"-> {os.path.realpath(path)}" if path.is_symlink() else ""
        if reported == "?":
            note = "does not report its version"
        elif pinned and not matches(pinned, reported):
            note = f"differs from deps.toml (rebuild: make clean@{name} deps@{name})"
            stale.append(name)
        rows.append((name, pinned or "system", reported, note))
    header = ("variant", "deps.toml", "installed", "")
    widths = [max(len(row[k]) for row in [header, *rows]) for k in range(3)]
    for row in [header, *rows]:
        cells = [cell.ljust(width) for cell, width in zip(row[:3], widths, strict=True)]
        print("  ".join([*cells, row[3]]).rstrip())
    return 1 if stale else 0


def main() -> int:
    command, *names = sys.argv[1:] or [""]
    try:
        if command == "list" and not names:
            print(" ".join(AWKS))
        elif command == "install" and names:
            for name in names:
                install(name)
        elif command == "versions" and not names:
            return versions()
        else:
            sys.exit(__doc__.split("\n\n")[1])
    except DepsError as e:
        sys.exit(f"ERROR: {e}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
