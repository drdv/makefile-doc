#!/usr/bin/env python3
"""Benchmark makefile-doc.awk on large real Makefiles.

usage: test/bench.py --awk PATH[=LABEL] [--awk ...] [--rev REV] [-n N]

Times makefile-doc.awk with each given awk and prints a Markdown table: one row per awk,
fastest first, with its time on each Makefile and the ratio to the fastest awk. With
--rev, each time also shows the change from the script at that git revision.

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
from typing import Dict, List, Optional, Tuple

ROOT = Path(__file__).resolve().parent.parent
DOWNLOAD_DIR = ROOT / "test" / "bin"

MAKEFILES = [
    {
        "name": "gcc-14.2.0-Makefile.in",
        "title": "GCC Makefile.in",
        "urls": [
            "https://raw.githubusercontent.com/gcc-mirror/gcc/releases/gcc-14.2.0/Makefile.in",
        ],
        "sha256": "7dd6a4a1248be8e8f41ce87fd07b2cf5616ee9fb35f447408655fe396d379366",
    },
    {
        "name": "linux-6.12-Makefile",
        "title": "Linux Makefile",
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
    """Return the best of n run times of `awk -f script makefile`, in milliseconds."""
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
    return 1000 * min(times)


def awk_label(spec: str) -> Tuple[str, str]:
    """Split PATH[=LABEL] into the path and a label with a version, e.g., "mawk 20260302".

    Without a version in the label (e.g., the system gawk), it is read from `--version`.
    """
    path, _, label = spec.partition("=")
    label = label.split() or [Path(path).name]
    if len(label) == 1:
        try:
            out = subprocess.run(
                [path, "--version"], capture_output=True, text=True, check=False
            ).stdout
        except OSError:
            out = ""
        version = re.search(r"\d+\.\d+(\.\d+)?", out.split("\n")[0])
        label += [version.group()] if version else []
    label[1:] = [re.sub(r"^[vt](?=\d)", "", v) for v in label[1:]]  # v1.30.0, t20260302
    return path, " ".join(label)


def cell(ms: float, fastest: float, old: Optional[float]) -> str:
    """Format a time, its ratio to the fastest and its change from old (if any)."""
    text = f"{ms:.0f} ms" if ms >= 100 else f"{ms:.1f} ms"
    text += f" ({ms / fastest:.1f}×)"
    if old is not None:
        change = round(100 * (ms - old) / old)
        text += f" {change:+d}%" if change else " ±0%"
    return text


def script_version(script: Path) -> str:
    match = re.search(r"^# Version: (\S+)", script.read_text(), re.MULTILINE)
    return match.group(1) if match else "?"


def progress(text: str) -> None:
    if sys.stderr.isatty():
        print(f"\r\033[K{text}", end="", file=sys.stderr, flush=True)


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "--awk",
        action="append",
        required=True,
        metavar="PATH[=LABEL]",
        help='awk binary, with an optional label, e.g., "test/bin/mawk=mawk 20260302" '
        "(repeatable)",
    )
    parser.add_argument("--rev", help="also show the change from this git revision")
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

    awks = [awk_label(spec) for spec in args.awk]
    new = ROOT / args.script
    with tempfile.TemporaryDirectory() as tmp:
        old = None
        if args.rev:
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

        paths = [download(makefile) for makefile in MAKEFILES]  # before any timing
        kept = []  # annotated Makefiles saved with --keep
        headers = []
        times: Dict[str, List[float]] = {label: [] for _, label in awks}
        old_times: Dict[str, List[float]] = {label: [] for _, label in awks}
        for makefile, path in zip(MAKEFILES, paths):
            lines = path.read_text(errors="replace").splitlines(keepends=True)
            headers.append(f"{makefile['title']} ({round(len(lines) / 1000)}k lines)")
            annotated = Path(tmp) / makefile["name"]
            annotated.write_text("".join(annotate(lines, args.every, args.section_every)))
            if args.keep:
                kept.append(DOWNLOAD_DIR / f"{makefile['name']}.annotated")
                kept[-1].write_bytes(annotated.read_bytes())
            for awk, label in awks:
                progress(f"timing {label} on {makefile['title']}")
                times[label].append(best_time(awk, new, annotated, args.n))
                if old:
                    old_times[label].append(best_time(awk, old, annotated, args.n))
        progress("")

    fastest = [min(t[k] for t in times.values()) for k in range(len(headers))]
    rows = []
    for label in sorted(times, key=lambda label: times[label]):  # the first Makefile first
        rows.append(
            [label]
            + [
                cell(ms, fastest[k], old_times[label][k] if old else None)
                for k, ms in enumerate(times[label])
            ]
        )
    header = ["awk"] + headers
    widths = [max(len(row[k]) for row in rows + [header]) for k in range(len(header))]

    def line(row: List[str]) -> str:  # the first column left-aligned, the others right
        cells = [row[0].ljust(widths[0])] + [t.rjust(w) for t, w in zip(row[1:], widths[1:])]
        return "| " + " | ".join(cells) + " |"

    change = f", change from {args.rev}" if args.rev else ""
    print(
        f"makefile-doc {script_version(new)}, best of {args.n} runs{change}, "
        f"sorted by the {MAKEFILES[0]['title']} column\n"
    )
    print(line(header))
    print("|-" + "-" * widths[0] + "-|" + "|".join("-" * (w + 1) + ":" for w in widths[1:]) + "|")
    for row in rows:
        print(line(row))
    if kept:
        print("\nsaved " + ", ".join(str(path.relative_to(ROOT)) for path in kept))
    return 0


if __name__ == "__main__":
    sys.exit(main())
