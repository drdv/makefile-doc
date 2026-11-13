#!/usr/bin/env python3
"""Test runner for makefile-doc.

usage: test/tools/run.py SUITE --awk AWK [options]

Suites:
  unit         run each test/unit/test_*.awk file in its own awk process and check its
               TAP output (see test/unit/harness.awk)
  integration  run each test/integration/*.test case and compare the output with the
               expected output (see test/README.md); --update rewrites the expected output
  bugs         run the cases of known bugs (marked with `#: bug: N`)

Each test file is run once with the given awk. A test file fails if a check fails, if the
TAP plan is missing or does not match the number of checks, if awk exits with a non-zero
status (e.g., a crash or a syntax error), or if awk runs for longer than --timeout seconds.
Checks of known bugs (TAP `# TODO issue N`) are expected to fail: the test file fails if one
of them passes (the bug has been fixed).

A case passes if the output of makefile-doc.awk is exactly the expected output: stderr
after a `#: stderr` line, stdout after a `#: stdout` line (a stream without output has no
such line), then `#: exit: N` for a non-zero exit status. A case with a `#: bug: N` line
(issue N) holds the correct output of a known bug: it is skipped by the integration suite,
and the bugs suite fails once its output is correct (the bug has been fixed).

Only the Python standard library is used (Python >= 3.11).
"""

import sys

if sys.version_info < (3, 11):  # noqa: UP036 (a clear message instead of a traceback)
    sys.exit(f"Python >= 3.11 is needed (this is Python {sys.version.split()[0]})")

import argparse
import difflib
import os
import re
import shlex
import subprocess
import tempfile
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent  # paths are relative to the project root
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


def run_awk(
    awk: str,
    args: list[str],
    timeout: float,
    text: bool = True,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess:
    """Run awk (it is killed, and subprocess.TimeoutExpired raised, after timeout seconds).
    The variables of env are added to the environment."""
    return subprocess.run(
        [awk, *args],
        cwd=ROOT,
        env={**AWK_ENV, **(env or {})},
        stdin=subprocess.DEVNULL,
        capture_output=True,
        timeout=timeout,
        **({"text": True, "errors": "replace"} if text else {}),
    )


def timed_out(name: str, timeout: float) -> Result:
    return Result(name, False, f"timed out after {timeout:g} s")


# ------------------------------------------------------------------------------------------
# unit tests
# ------------------------------------------------------------------------------------------
TAP_RESULT = re.compile(r"^(ok|not ok) (\d+)\b")
TAP_TODO = re.compile(r"#\s*TODO\b\s*(.*)$", re.IGNORECASE)
TAP_PLAN = re.compile(r"^1\.\.(\d+)$")


def check_tap(stdout: str, returncode: int) -> tuple[bool, str, int]:
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


def run_unit_file(
    awk: str, awk_flags: list[str], script: str, test_file: Path, timeout: float
) -> Result:
    with tempfile.TemporaryDirectory() as tmp:
        stderr_file = Path(tmp) / "stderr"
        stderr_file.touch()
        args = [
            *awk_flags,
            "-v",
            "UNIT_TEST=1",
            "-v",
            f"STDERR={stderr_file}",
            "-f",
            str(HARNESS),
            "-f",
            script,
            "-f",
            str(test_file),
            "/dev/null",
        ]
        try:
            proc = run_awk(awk, args, timeout)
        except subprocess.TimeoutExpired:
            return timed_out(test_file.stem, timeout)
    passed, summary, checks = check_tap(proc.stdout, proc.returncode)
    stderr = f"[awk stderr]\n{proc.stderr}" if proc.stderr else ""
    return Result(
        test_file.stem,
        passed,
        summary,
        proc.stdout + stderr,
        checks,
        relevant_tap_lines(proc.stdout) + stderr,
    )


def suite_unit(args: argparse.Namespace) -> list[Callable[[], Result]]:
    files = sorted((ROOT / UNIT_DIR).glob("test_*.awk"))
    files = [UNIT_DIR / f.name for f in files if selected(args, f.stem)]
    return [
        (lambda f=f: run_unit_file(args.awk, args.awk_flags, args.script, f, args.timeout))
        for f in files
    ]


# ------------------------------------------------------------------------------------------
# integration tests
# ------------------------------------------------------------------------------------------
CASE_BUG = re.compile(rb"^#: bug:(.*)$")
CASE_ENV = re.compile(rb"^#: env:\s*([A-Za-z_][A-Za-z0-9_]*)=(.*)$")


def visible(data: bytes) -> list[str]:
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


def render_output(stderr: bytes, stdout: bytes, returncode: int) -> bytes:
    """The output of one run as it is stored in a case: each stream after a marker line (a
    stream without output has no marker), then the exit status if it is not 0."""
    out = b""
    if stderr:
        out += b"#: stderr\n" + stderr
    if stdout:
        out += b"#: stdout\n" + stdout
    if returncode != 0:
        out += f"#: exit: {returncode}\n".encode()
    return out


@dataclass
class Case:
    """An integration test: a test/integration/*.test file."""

    path: Path  # relative to ROOT
    metadata: list[bytes]  # the leading `#:` lines (with their newline)
    args: str  # the awk arguments (shell syntax)
    expected: bytes
    bug: str | None  # the value of the `#: bug:` line (the issue number), if any
    env: dict[str, str]  # the environment variables of the `#: env: NAME=value` lines

    @classmethod
    def read(cls, path: Path) -> "Case":
        lines = (ROOT / path).read_bytes().splitlines(keepends=True)
        k = 0
        while k < len(lines) and lines[k].startswith(b"#:"):
            k += 1
        args = lines[k].decode().rstrip("\n") if k < len(lines) else ""
        bug = None
        env = {}
        for line in lines[:k]:
            m = CASE_BUG.match(line.rstrip(b"\n"))
            if m:
                bug = m.group(1).decode().strip()
            m = CASE_ENV.match(line.rstrip(b"\n"))
            if m:
                env[m.group(1).decode()] = m.group(2).decode()
        return cls(path, lines[:k], args, b"".join(lines[k + 1 :]), bug, env)

    @property
    def name(self) -> str:
        return self.path.stem  # without the .test extension

    def run(self, args: argparse.Namespace) -> Result:
        """Run makefile-doc.awk and compare its output with the expected output (or, with
        --update, rewrite the expected output)."""
        if self.bug is not None and not self.bug.isdigit():
            return Result(self.name, False, "the `#: bug:` line needs an issue number")
        if self.bug is not None and args.update:
            return Result(self.name, False, "the expected output of a known bug is not updated")

        try:
            proc = run_awk(
                args.awk,
                [*args.awk_flags, "-f", args.script, *shlex.split(self.args)],
                args.timeout,
                text=False,
                env=self.env,
            )
        except subprocess.TimeoutExpired:
            return timed_out(self.name, args.timeout)
        actual = render_output(proc.stderr, proc.stdout, proc.returncode)

        diff = "".join(
            difflib.unified_diff(
                visible(self.expected), visible(actual), "expected", "actual", lineterm="\n"
            )
        )
        if diff and not diff.endswith("\n"):
            diff += "\n"

        if args.update:
            if actual != self.expected:
                new = b"".join(self.metadata) + self.args.encode() + b"\n" + actual
                (ROOT / self.path).write_bytes(new)
                return Result(self.name, True, "updated", diff, relevant=diff)
            return Result(self.name, True, "unchanged")

        if self.bug is not None:
            if actual == self.expected:
                fixed = f"FIXED: replace `#: bug: {self.bug}` with `#: issue: {self.bug}`"
                return Result(self.name, False, fixed)
            return Result(self.name, True, f"issue {self.bug}", diff, label="known bug")
        if actual == self.expected:
            return Result(self.name, True, "")
        return Result(self.name, False, "output differs", diff, relevant=diff)


def read_cases(args: argparse.Namespace) -> list[Case]:
    """The selected integration cases (each file is read once)."""
    paths = sorted((ROOT / INTEGRATION_DIR).glob("*.test"))
    return [Case.read(INTEGRATION_DIR / p.name) for p in paths if selected(args, p.stem)]


def suite_integration(args: argparse.Namespace) -> list[Callable[[], Result]]:
    return [(lambda c=c: c.run(args)) for c in read_cases(args) if c.bug is None]


def suite_bugs(args: argparse.Namespace) -> list[Callable[[], Result]]:
    return [(lambda c=c: c.run(args)) for c in read_cases(args) if c.bug is not None]


# ------------------------------------------------------------------------------------------
# main
# ------------------------------------------------------------------------------------------
def selected(args: argparse.Namespace, name: str) -> bool:
    return not args.k or args.k in name


SUITES: dict[str, Callable[[argparse.Namespace], list[Callable[[], Result]]]] = {
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
        "--timeout",
        type=float,
        default=30,
        metavar="SECONDS",
        help="fail a test whose awk process runs for longer (default: 30)",
    )
    parser.add_argument(
        "--update", action="store_true", help="integration: rewrite the expected outputs"
    )
    parser.add_argument("-j", "--jobs", type=int, default=os.cpu_count() or 1, help="parallel jobs")
    parser.add_argument(
        "-v", "--verbose", action="store_true", help="show the output of passing tests too"
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    tests = SUITES[args.suite](args)
    if not tests:
        if args.suite == "bugs" and not args.k:
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
            output = r.relevant  # the diff of an updated case
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
