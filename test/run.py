#!/usr/bin/env python3
"""Test runner for makefile-doc.

usage: test/run.py SUITE --awk AWK [options]

Suites:
  unit   run each test/unit/test_*.awk file in its own awk process and check its TAP
         output (see test/unit/harness.awk)

Each test file is run once with the given awk. A test file fails if a check fails, if the
TAP plan is missing or does not match the number of checks, or if awk exits with a non-zero
status (e.g., a crash or a syntax error). Checks of known bugs (TAP `# TODO issue N`) are
expected to fail: the test file fails if one of them passes (the bug has been fixed).

Only the Python standard library is used (Python >= 3.8).
"""

import argparse
import os
import re
import shlex
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Dict, List, Tuple

ROOT = Path(__file__).resolve().parent.parent  # paths are relative to the project root
UNIT_DIR = Path("test/unit")
HARNESS = UNIT_DIR / "harness.awk"


@dataclass
class Result:
    name: str
    passed: bool
    summary: str  # one line, e.g. "17 checks"
    details: str = ""  # the full output (shown with --verbose)
    checks: int = 0  # number of checks (unit tests)
    relevant: str = ""  # the part of the output that explains a failure


def run_awk(awk: str, args: List[str]) -> subprocess.CompletedProcess:
    return subprocess.run(
        [awk, *args],
        cwd=ROOT,
        stdin=subprocess.DEVNULL,
        capture_output=True,
        text=True,
        errors="replace",
    )


# ------------------------------------------------------------------------------------------
# unit tests
# ------------------------------------------------------------------------------------------
TAP_RESULT = re.compile(r"^(ok|not ok) (\d+)\b")
TAP_TODO = re.compile(r"#\s*TODO\b\s*(.*)$", re.IGNORECASE)
TAP_PLAN = re.compile(r"^1\.\.(\d+)$")


def check_tap(stdout: str, returncode: int) -> Tuple[bool, str, int]:
    """Return (passed, summary, number of checks) for the TAP output of one test file."""
    numbers, failed, known_bugs, fixed, plan = [], 0, 0, [], None
    for line in stdout.splitlines():
        m = TAP_RESULT.match(line)
        if m:
            numbers.append(int(m.group(2)))
            todo = TAP_TODO.search(line)
            if not todo:
                failed += m.group(1) == "not ok"
            elif m.group(1) == "not ok":
                known_bugs += 1
            else:
                fixed.append(f"check {m.group(2)} ({todo.group(1) or 'no issue'})")
        elif TAP_PLAN.match(line):
            plan = int(TAP_PLAN.match(line).group(1))
        elif line.startswith("Bail out!"):
            return False, line, 0

    n = len(numbers)
    if plan is None:
        return False, f"no TAP plan after {n} checks (did the test file crash?)", n
    if plan != n or numbers != list(range(1, n + 1)):
        return False, f"TAP plan 1..{plan} does not match the {n} checks", n
    problems = []
    if failed:
        problems.append(f"{failed} of {n} checks failed")
    if fixed:
        problems.append(f"FIXED: {', '.join(fixed)}: replace check_bug with check")
    if returncode != 0 and not failed:
        problems.append(f"awk exited with status {returncode}")
    if problems:
        return False, "; ".join(problems), n
    return True, f"{n} checks" + (f", known bugs: {known_bugs}" if known_bugs else ""), n


def relevant_tap_lines(stdout: str) -> str:
    """The lines of TAP output that explain a failure: failed checks (with their diagnostics),
    passing checks of known bugs, and the last check if the plan is missing (a crash)."""
    lines, keep, last_check = [], False, None
    for line in stdout.splitlines():
        m = TAP_RESULT.match(line)
        if m:
            todo = TAP_TODO.search(line)
            keep = (m.group(1) == "not ok") != bool(todo)  # failed, or a fixed known bug
            last_check = line
        elif not line.startswith("#"):
            keep = False
        if keep or line.startswith("Bail out!"):
            lines.append(line)
    if not any(TAP_PLAN.match(line) for line in stdout.splitlines()) and last_check:
        lines.append(f"(last check before the end of the output) {last_check}")
    return "\n".join(lines) + "\n" if lines else ""


def run_unit_file(awk: str, awk_flags: List[str], script: str, test_file: Path) -> Result:
    with tempfile.TemporaryDirectory() as tmp:
        stderr_file = Path(tmp) / "stderr"
        stderr_file.touch()
        proc = run_awk(
            awk,
            [
                *awk_flags,
                "-v", "UNIT_TEST=1",
                "-v", f"STDERR={stderr_file}",
                "-f", str(HARNESS),
                "-f", script,
                "-f", str(test_file),
                "/dev/null",
            ],
        )
    passed, summary, checks = check_tap(proc.stdout, proc.returncode)
    stderr = f"[awk stderr]\n{proc.stderr}" if proc.stderr else ""
    return Result(test_file.stem, passed, summary, proc.stdout + stderr, checks,
                  relevant_tap_lines(proc.stdout) + stderr)


def suite_unit(args: argparse.Namespace) -> List[Callable[[], Result]]:
    files = sorted((ROOT / UNIT_DIR).glob("test_*.awk"))
    files = [UNIT_DIR / f.name for f in files if not args.k or args.k in f.stem]
    return [
        (lambda f=f: run_unit_file(args.awk, args.awk_flags, args.script, f))
        for f in files
    ]


# ------------------------------------------------------------------------------------------
# main
# ------------------------------------------------------------------------------------------
SUITES: Dict[str, Callable[[argparse.Namespace], List[Callable[[], Result]]]] = {
    "unit": suite_unit,
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("suite", choices=SUITES)
    parser.add_argument("--awk", required=True, help="awk binary (e.g., test/bin/mawk)")
    parser.add_argument(
        "--awk-flags",
        default="",
        type=shlex.split,
        help="extra awk flags (e.g., goawk coverage options)",
    )
    parser.add_argument("--script", default="makefile-doc.awk", help="script under test")
    parser.add_argument("-k", metavar="PATTERN", help="run only tests whose name contains PATTERN")
    parser.add_argument(
        "-j", "--jobs", type=int, default=os.cpu_count() or 1, help="parallel jobs"
    )
    parser.add_argument(
        "-v", "--verbose", action="store_true", help="show the output of passing tests too"
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    tests = SUITES[args.suite](args)
    if not tests:
        print(f"no {args.suite} tests found", file=sys.stderr)
        return 1

    awk_name = Path(args.awk).name
    with ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
        results = list(pool.map(lambda test: test(), tests))

    def indent(text: str) -> str:
        return "    " + text.rstrip("\n").replace("\n", "\n    ")

    for r in results:
        if r.passed:
            print(f"[{awk_name}] passed {r.name} ({r.summary})")
        else:
            print(f"[{awk_name}] FAILED {r.name}")
        output = r.details if args.verbose else ("" if r.passed else r.relevant)
        if output:
            print(indent(output))

    failed = [r for r in results if not r.passed]
    n_checks = sum(r.checks for r in results)
    if failed:
        print()
        for r in failed:  # repeated at the end, so that it is not lost in the output above
            print(f"[{awk_name}] FAILED {r.name} ({r.summary})")
        print(f"[{awk_name}] {len(failed)} of {len(results)} {args.suite} test files failed")
        return 1
    print(f"[{awk_name}] all {len(results)} {args.suite} test files passed ({n_checks} checks)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
