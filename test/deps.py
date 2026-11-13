#!/usr/bin/env python3
"""Download what the tests need, as described in test/deps.toml.

usage: test/deps.py list
       test/deps.py install VARIANT [VARIANT ...]

`list` prints the awk variants; `install` builds test/bin/VARIANT (if it does not exist
yet). Downloads are kept in test/bin/ and checked against their sha256.

Only the Python standard library is used (Python >= 3.11).
"""

import hashlib
import platform
import shutil
import subprocess
import sys
import time
import tomllib
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BIN = ROOT / "test" / "bin"
DEPS = tomllib.loads((ROOT / "test" / "deps.toml").read_text())
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
        if not sha256:
            print(f"WARNING: no sha256 to check {path.name} (it is {digest})", file=sys.stderr)
        elif digest != sha256:
            errors.append(f"{url}: wrong sha256 {digest} (expected {sha256})")
            continue
        path.write_bytes(data)
        return path
    raise DepsError(f"cannot download {path.name}:\n  " + "\n  ".join(errors))


def install(name: str) -> Path:
    """Build test/bin/<name> (if it does not exist yet) and return its path."""
    if name not in AWKS:
        raise DepsError(f"unknown awk variant {name!r} (supported: {' '.join(AWKS)})")
    awk, target = AWKS[name], BIN / name
    if target.exists():
        return target
    if "os" in awk and platform.system() != awk["os"]:
        raise DepsError(f"{name} can only be installed on {awk['os']}")
    BIN.mkdir(parents=True, exist_ok=True)

    if awk.get("system"):
        path = shutil.which(name)
        if not path:
            raise DepsError(f"{name} is not installed")
        target.symlink_to(path)
        return target

    url = awk["url"].format(version=awk["version"])
    if "build" not in awk:  # a prebuilt binary
        shutil.copy(download([url], BIN / f"{name}-{awk['version']}", awk["sha256"]), target)
        target.chmod(0o755)
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
    shutil.copy(src / awk["binary"], target)
    return target


def main() -> int:
    command, *names = sys.argv[1:] or [""]
    try:
        if command == "list" and not names:
            print(" ".join(AWKS))
        elif command == "install" and names:
            for name in names:
                install(name)
        else:
            sys.exit(__doc__.split("\n\n")[1])
    except DepsError as e:
        sys.exit(f"ERROR: {e}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
