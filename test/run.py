#!/usr/bin/env python3
"""Test runner for makefile-doc.

usage: test/run.py SUITE --awk AWK [options]

Suites:
  unit         run each test/unit/test_*.awk file in its own awk process and check its
               TAP output (see test/unit/harness.awk)
  integration  run each test/integration/test-* recipe and compare the output with the
               expected output (see test/README.md); --update rewrites the expected output
  bugs         run the recipes of known bugs (marked with `#: bug: N`)

Each test file is run once with the given awk. A test file fails if a check fails, if the
TAP plan is missing or does not match the number of checks, or if awk exits with a non-zero
status (e.g., a crash or a syntax error). Checks of known bugs (TAP `# TODO issue N`) are
expected to fail: the test file fails if one of them passes (the bug has been fixed).

A recipe passes if the output of makefile-doc.awk (stderr, then stdout, then `exit: N` for
a non-zero exit status) is exactly the expected output. A recipe with a `#: bug: N` line
(issue N) holds the correct output of a known bug: it is skipped by the integration suite,
and the bugs suite fails once its output is correct (the bug has been fixed).

Only the Python standard library is used (Python >= 3.8).
"""

import argparse
import difflib
import os
import re
import shlex
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Dict, List, Optional, Tuple

ROOT = Path(__file__).resolve().parent.parent  # paths are relative to the project root
UNIT_DIR = Path("test/unit")
HARNESS = UNIT_DIR / "harness.awk"
INTEGRATION_DIR = Path("test/integration")


@dataclass
class Result:
    name: str
    passed: bool
    summary: str  # one line, e.g. "17 checks"
    details: str = ""  # the full output (shown with --verbose)
    checks: int = 0  # number of checks (unit tests)
    label: str = ""  # replaces "passed" in the report (e.g., "known bug")
    relevant: str = ""  # the part of the output that explains a failure


# NO_COLOR would turn off the colors that the tests expect
AWK_ENV = {k: v for k, v in os.environ.items() if k != "NO_COLOR"}


def run_awk(awk: str, args: List[str], text: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run(
        [awk, *args],
        cwd=ROOT,
        env=AWK_ENV,
        stdin=subprocess.DEVNULL,
        capture_output=True,
        **({"text": True, "errors": "replace"} if text else {}),
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
    files = [UNIT_DIR / f.name for f in files if selected(args, f.stem)]
    return [
        (lambda f=f: run_unit_file(args.awk, args.awk_flags, args.script, f))
        for f in files
    ]


# ------------------------------------------------------------------------------------------
# integration tests
# ------------------------------------------------------------------------------------------
RECIPE_BUG = re.compile(rb"^#: bug:(.*)$")


@dataclass
class Recipe:
    metadata: List[bytes]  # the leading `#:` lines (with their newline)
    args: str  # the awk arguments (shell syntax)
    expected: bytes
    bug: Optional[str]  # the value of the `#: bug:` line (the issue number), if any


def read_recipe(path: Path) -> Recipe:
    lines = (ROOT / path).read_bytes().splitlines(keepends=True)
    k = 0
    while k < len(lines) and lines[k].startswith(b"#:"):
        k += 1
    args = lines[k].decode().rstrip("\n") if k < len(lines) else ""
    bug = None
    for line in lines[:k]:
        m = RECIPE_BUG.match(line.rstrip(b"\n"))
        if m:
            bug = m.group(1).decode().strip()
    return Recipe(lines[:k], args, b"".join(lines[k + 1 :]), bug)


def visible(data: bytes) -> List[str]:
    """Lines for a diff: escape characters are shown as ^[ (as in `cat -v`), and blanks at
    the end of a line and a missing final newline are marked."""
    lines = data.decode(errors="replace").replace("\x1b", "^[").splitlines(keepends=True)
    marked = []
    for line in lines:
        body = line.rstrip("\n")
        if body != body.rstrip(" \t"):
            body += "<-- blanks at the end of the line"
        marked.append(body + "\n")
    if lines and not lines[-1].endswith("\n"):
        marked.append("\\ No newline at end of file\n")
    return marked


def run_recipe(args: argparse.Namespace, path: Path) -> Result:
    recipe = read_recipe(path)
    if recipe.bug is not None and not recipe.bug.isdigit():
        return Result(path.name, False, "the `#: bug:` line needs an issue number")
    if recipe.bug is not None and args.update:
        return Result(path.name, False, "the expected output of a known bug is not updated")

    proc = run_awk(
        args.awk,
        ["-f", args.script, *args.awk_flags, *shlex.split(recipe.args)],
        text=False,
    )
    actual = proc.stderr + proc.stdout
    if proc.returncode != 0:
        actual += f"exit: {proc.returncode}\n".encode()

    diff = "".join(
        difflib.unified_diff(
            visible(recipe.expected), visible(actual), "expected", "actual", lineterm="\n"
        )
    )
    if diff and not diff.endswith("\n"):
        diff += "\n"

    if args.update:
        if actual != recipe.expected:
            new = b"".join(recipe.metadata) + recipe.args.encode() + b"\n" + actual
            (ROOT / path).write_bytes(new)
            return Result(path.name, True, "updated", diff, relevant=diff)
        return Result(path.name, True, "unchanged")

    if recipe.bug is not None:
        if actual == recipe.expected:
            fixed = f"FIXED: replace `#: bug: {recipe.bug}` with `#: issue: {recipe.bug}`"
            return Result(path.name, False, fixed)
        return Result(path.name, True, f"issue {recipe.bug}", diff, label="known bug")
    if actual == recipe.expected:
        return Result(path.name, True, "")
    return Result(path.name, False, "output differs", diff, relevant=diff)


def recipes(args: argparse.Namespace, bugs: bool) -> List[Callable[[], Result]]:
    """The recipes to run: with or without a `#: bug:` line (all recipes selected by
    --name are run, each in its own mode)."""
    paths = sorted(p for p in (ROOT / INTEGRATION_DIR).iterdir() if p.is_file())
    paths = [
        INTEGRATION_DIR / p.name
        for p in paths
        if selected(args, p.name)
        and (args.name or (read_recipe(INTEGRATION_DIR / p.name).bug is not None) == bugs)
    ]
    return [(lambda p=p: run_recipe(args, p)) for p in paths]


def suite_integration(args: argparse.Namespace) -> List[Callable[[], Result]]:
    return recipes(args, bugs=False)


def suite_bugs(args: argparse.Namespace) -> List[Callable[[], Result]]:
    return recipes(args, bugs=True)


# ------------------------------------------------------------------------------------------
# main
# ------------------------------------------------------------------------------------------
def selected(args: argparse.Namespace, name: str) -> bool:
    if args.name:
        return name in args.name
    return not args.k or args.k in name


SUITES: Dict[str, Callable[[argparse.Namespace], List[Callable[[], Result]]]] = {
    "unit": suite_unit,
    "integration": suite_integration,
    "bugs": suite_bugs,
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
        "--name", action="append", help="run only the test with this exact name (repeatable)"
    )
    parser.add_argument(
        "--update", action="store_true", help="integration: rewrite the expected outputs"
    )
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
        if args.suite == "bugs" and not args.name and not args.k:
            print(f"[{Path(args.awk).name}] no known bugs")
            return 0
        print(f"no {args.suite} tests found", file=sys.stderr)
        return 1

    awk_name = Path(args.awk).name
    with ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
        results = list(pool.map(lambda test: test(), tests))

    def indent(text: str) -> str:
        return "    " + text.rstrip("\n").replace("\n", "\n    ")

    for r in results:
        if args.update and r.passed:
            print(f"[{awk_name}] {r.summary} {r.name}")
            output = r.relevant  # the diff of an updated recipe
        else:
            summary = f" ({r.summary})" if r.summary and r.passed else ""
            status = (r.label or "passed") if r.passed else "FAILED"
            print(f"[{awk_name}] {status} {r.name}{summary}")
            output = r.details if args.verbose else ("" if r.passed else r.relevant)
        if output:
            print(indent(output))

    failed = [r for r in results if not r.passed]
    n_checks = sum(r.checks for r in results)
    noun = {"unit": "unit test files", "integration": "integration tests", "bugs": "bug tests"}[
        args.suite
    ]
    if failed:
        print()
        for r in failed:  # repeated at the end, so that it is not lost in the output above
            print(f"[{awk_name}] FAILED {r.name} ({r.summary})")
        print(f"[{awk_name}] {len(failed)} of {len(results)} {noun} failed")
        return 1
    if args.suite == "bugs":
        print(f"[{awk_name}] {len(results)} known bugs, none fixed")
    elif not args.update:
        checks = f" ({n_checks} checks)" if n_checks else ""
        print(f"[{awk_name}] all {len(results)} {noun} passed{checks}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
