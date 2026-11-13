#!/usr/bin/env python3
"""Benchmark makefile-doc.awk on large real Makefiles.

usage: test/bench.py [--awk VARIANT ...] [--rev REV] [-n N]

Times makefile-doc.awk with each awk variant of test/deps.toml and prints a Markdown
table: one row per awk, fastest first, with its time on each Makefile and the ratio to
the fastest awk. With --rev, each time also shows the change from the script at that git
revision.

The awk variants and the Makefiles (see test/deps.toml) are downloaded once into test/bin/.
The Makefiles contain hardly any makefile-doc docs, so docs are inserted first: before
every k-th target or variable line (some ##!, ##%, multi-line, inline or with backticks),
and a section every m documented anchors. The insertion is deterministic, so every run
measures the same input, and it only adds comments outside define blocks, recipes and
continued lines.

Only the Python standard library is used (Python >= 3.11).
"""

import argparse
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path

sys.dont_write_bytecode = True  # no test/__pycache__/ from importing deps
from deps import AWKS, BENCH_MAKEFILES, BIN, ROOT, DepsError, download, install  # noqa: E402

TARGET = re.compile(r"^([^\s#=][^#=]*?)(?<!:):(?![=])")
VARIABLE = re.compile(
    r"^\s*((override|export|private)\s+)*([A-Za-z_][\w.-]*)\s*(::?=|:::=|\?=|\+=|!=|=)"
)


def annotate(lines: list[str], every: int, section_every: int) -> list[str]:
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
            name = (
                ("var", match.group(3))
                if match.re is VARIABLE
                else ("target", " ".join(match.group(1).split()))
            )
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


def awk_label(name: str) -> str:
    """Return the name of an awk variant with its version, e.g., "mawk 20260302".

    The version of a system awk is read from its `--version`.
    """
    version = AWKS[name].get("version", "")
    if not version:
        out = subprocess.run(
            [BIN / name, "--version"], capture_output=True, text=True, check=False
        ).stdout
        match = re.search(r"\d+\.\d+(\.\d+)?", out.split("\n")[0])
        version = match.group() if match else ""
    version = re.sub(r"^[vt](?=\d)", "", version)  # v1.30.0, t20260302
    return f"{name} {version}".strip()


def cell(ms: float, fastest: float, old: float | None) -> str:
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
        choices=list(AWKS),
        metavar="VARIANT",
        help="awk variant (repeatable; default: those of test/deps.toml without bench = false)",
    )
    parser.add_argument("--rev", help="also show the change from this git revision")
    parser.add_argument("--script", default="makefile-doc.awk", help="script under test")
    parser.add_argument("-n", type=int, default=5, help="runs per measurement (the best is kept)")
    parser.add_argument("--every", type=int, default=5, help="document every k-th anchor")
    parser.add_argument("--section-every", type=int, default=25, help="a section every m docs")
    parser.add_argument(
        "--keep", action="store_true", help="also save the annotated Makefiles in test/bin/"
    )
    args = parser.parse_args()

    names = args.awk or [name for name, awk in AWKS.items() if awk.get("bench", True)]
    try:  # everything is downloaded before any timing
        awks = [(str(install(name)), awk_label(name)) for name in names]
        paths = [
            download(makefile["urls"], BIN / makefile["name"], makefile["sha256"])
            for makefile in BENCH_MAKEFILES
        ]
    except DepsError as e:
        sys.exit(f"ERROR: {e}")
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

        kept = []  # annotated Makefiles saved with --keep
        headers = []
        times: dict[str, list[float]] = {label: [] for _, label in awks}
        old_times: dict[str, list[float]] = {label: [] for _, label in awks}
        for makefile, path in zip(BENCH_MAKEFILES, paths, strict=True):
            lines = path.read_text(errors="replace").splitlines(keepends=True)
            headers.append(f"{makefile['title']} ({round(len(lines) / 1000)}k lines)")
            annotated = Path(tmp) / makefile["name"]
            annotated.write_text("".join(annotate(lines, args.every, args.section_every)))
            if args.keep:
                kept.append(BIN / f"{makefile['name']}.annotated")
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

    def line(row: list[str]) -> str:  # the first column left-aligned, the others right
        cells = [row[0].ljust(widths[0])] + [
            t.rjust(w) for t, w in zip(row[1:], widths[1:], strict=True)
        ]
        return "| " + " | ".join(cells) + " |"

    change = f", change from {args.rev}" if args.rev else ""
    print(
        f"makefile-doc {script_version(new)}, best of {args.n} runs{change}, "
        f"sorted by the {BENCH_MAKEFILES[0]['title']} column\n"
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
