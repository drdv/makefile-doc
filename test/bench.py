#!/usr/bin/env python3
"""Benchmark makefile-doc.awk on large real Makefiles.

usage: test/bench.py --awk AWK [--awk AWK ...] [--rev REV] [-n N]

Compares the speed of makefile-doc.awk in the working tree with its version at the git
revision REV (default: HEAD), with each given awk.

The Makefiles are downloaded once into test/bin/ (pinned versions, checked against their
SHA256). They contain hardly any makefile-doc docs, so docs are inserted first: before
every k-th target or variable line (some ##!, ##%, multi-line, inline or with backticks),
and a section every m documented anchors. The insertion is deterministic, so every run
measures the same input, and it only adds comments outside define blocks, recipes and
continued lines.

Only the Python standard library is used (Python >= 3.8).
"""

import argparse
import hashlib
import re
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import List

ROOT = Path(__file__).resolve().parent.parent
DOWNLOAD_DIR = ROOT / "test" / "bin"

MAKEFILES = [
    {
        "name": "gcc-14.2.0-Makefile.in",
        "urls": [
            "https://raw.githubusercontent.com/gcc-mirror/gcc/releases/gcc-14.2.0/Makefile.in",
        ],
        "sha256": "7dd6a4a1248be8e8f41ce87fd07b2cf5616ee9fb35f447408655fe396d379366",
    },
    {
        "name": "linux-6.12-Makefile",
        "urls": [
            "https://raw.githubusercontent.com/torvalds/linux/v6.12/Makefile",
            "https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/plain/"
            "Makefile?h=v6.12",
        ],
        "sha256": "96ec6a92139d7af01fa3c4be4f8f521f86f48d249861c578dc00f4ff38df1b61",
    },
]

TARGET = re.compile(r"^([^\s#=][^#=]*?)(?<!:):(?![=])")
VARIABLE = re.compile(
    r"^\s*((override|export|private)\s+)*([A-Za-z_][\w.-]*)\s*(::?=|:::=|\?=|\+=|!=|=)"
)


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


def download(makefile: dict) -> Path:
    """Download a Makefile into test/bin/ (once), trying its URLs in turn."""
    path = DOWNLOAD_DIR / makefile["name"]
    if path.exists():
        return path
    DOWNLOAD_DIR.mkdir(parents=True, exist_ok=True)
    errors = []
    for url in makefile["urls"]:
        print(f"downloading {url}", file=sys.stderr)
        try:
            data = fetch(url)
        except (urllib.error.URLError, OSError) as e:
            errors.append(f"{url}: {e}")
            continue
        digest = hashlib.sha256(data).hexdigest()
        if digest != makefile["sha256"]:
            errors.append(f"{url}: wrong SHA256 {digest}")
            continue
        path.write_bytes(data)
        return path
    sys.exit(f"cannot download {makefile['name']}:\n  " + "\n  ".join(errors))


def annotate(lines: List[str], every: int, section_every: int) -> List[str]:
    """Insert makefile-doc docs before every `every`-th target or variable line."""
    out, candidates, documented, seen = [], 0, 0, set()
    in_define = continued = False
    for line in lines:
        stripped = line.rstrip("\n")
        match = (
            not in_define
            and not continued
            and not line.startswith("\t")
            and not stripped.endswith("\\")
            and (VARIABLE.match(stripped) or TARGET.match(stripped))
        )
        # each name is documented once at most: twice would be a redefinition
        name = None
        if match:  # variables and targets have separate names
            name = ("var", match.group(3)) if match.re is VARIABLE else (
                "target", " ".join(match.group(1).split()))
        is_candidate = bool(match) and name not in seen
        seen.add(name)
        if re.match(r"^\s*((override|export)\s+)*define\b", stripped):
            in_define = True
        elif in_define and re.match(r"^\s*endef\b", stripped):
            in_define = False
        continued = stripped.endswith("\\")

        if is_candidate:
            candidates += 1
            if candidates % every == 0:
                documented += 1
                n = documented
                if n % section_every == 0:
                    out += ["##@\n", f"##@ Section {n // section_every}\n", "##@\n"]
                tag = "##!" if n % 10 == 3 else "##%" if n % 10 == 7 else "##"
                text = f"Doc {n} with `backticks`" if n % 3 == 0 else f"Doc {n}"
                if n % 6 == 2 and "#" not in stripped and ";" not in stripped:
                    line = f"{stripped} {tag} {text} (inline)\n"
                else:
                    out.append(f"{tag} {text}\n")
                    if n % 4 == 1:
                        out.append("## second line of the doc\n")
        out.append(line)
    return out


def best_time(awk: str, script: Path, makefile: Path, n: int) -> float:
    times = []
    for _ in range(n):
        start = time.perf_counter()
        subprocess.run(
            [awk, "-f", str(script), str(makefile)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        times.append(time.perf_counter() - start)
    return min(times)


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "--awk", action="append", required=True, help="awk binary (repeatable)"
    )
    parser.add_argument("--rev", default="HEAD", help="git revision to compare with")
    parser.add_argument("--script", default="makefile-doc.awk", help="script under test")
    parser.add_argument(
        "-n", type=int, default=5, help="runs per measurement (the best is kept)"
    )
    parser.add_argument("--every", type=int, default=5, help="document every k-th anchor")
    parser.add_argument("--section-every", type=int, default=25, help="a section every m docs")
    parser.add_argument(
        "--keep", action="store_true", help="also save the annotated Makefiles in test/bin/"
    )
    args = parser.parse_args()

    with tempfile.TemporaryDirectory() as tmp:
        old = Path(tmp) / "old.awk"
        try:
            old.write_bytes(
                subprocess.run(
                    ["git", "show", f"{args.rev}:{args.script}"],
                    cwd=ROOT,
                    capture_output=True,
                    check=True,
                ).stdout
            )
        except subprocess.CalledProcessError as e:
            sys.exit(e.stderr.decode().strip())
        new = ROOT / args.script

        paths = [download(makefile) for makefile in MAKEFILES]  # before any timing
        kept = []  # annotated Makefiles saved with --keep

        print(f"best of {args.n} runs, in milliseconds; {args.rev} vs working tree")
        rev = args.rev[:10]
        print(f"{'makefile':26} {'lines':>6} {'awk':8} {rev:>10} {'now':>8} {'change':>7}")
        for makefile, path in zip(MAKEFILES, paths):
            lines = path.read_text(errors="replace").splitlines(keepends=True)
            annotated = Path(tmp) / makefile["name"]
            annotated.write_text("".join(annotate(lines, args.every, args.section_every)))
            if args.keep:
                kept.append(DOWNLOAD_DIR / f"{makefile['name']}.annotated")
                kept[-1].write_bytes(annotated.read_bytes())
            for awk in args.awk:
                t_old = best_time(awk, old, annotated, args.n) * 1000
                t_new = best_time(awk, new, annotated, args.n) * 1000
                print(
                    f"{makefile['name']:26} {len(lines):6} {Path(awk).name:8} "
                    f"{t_old:10.1f} {t_new:8.1f} {100 * (t_new - t_old) / t_old:+6.0f}%"
                )
        for path in kept:
            print(f"saved {path.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
