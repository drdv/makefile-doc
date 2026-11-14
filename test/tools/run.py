#!/usr/bin/env python3
"""Test runner for makefile-doc.

usage: test/tools/run.py SUITE --awk AWK [options] [NAME ...]

Suites:
  unit         run each test/unit/test_*.awk file in its own awk process and check its
               TAP output (see test/unit/harness.awk)
  integration  run each test/integration/*.test case and compare the output with the
               expected output (see test/README.md); --update rewrites the expected output
  bugs         run the cases of known bugs (marked with `#: bug: N`)
  lint         run each integration case (known bugs included) with `gawk --lint` and print
               each distinct lint warning once; the output of makefile-doc.awk is discarded
               (it is not compared), and the suite fails if there is a warning that is not
               expected in test/tools/lint.toml or by a `# lint: ignore[RULE, ...]` comment at
               its line of makefile-doc.awk (--awk: gawk)

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
import fnmatch
import os
import re
import shlex
import subprocess
import tempfile
import tomllib
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from pathlib import Path
from typing import TypeVar

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
    files = [UNIT_DIR / f.name for f in sorted((ROOT / UNIT_DIR).glob("test_*.awk"))]
    # test/unit/test_parsing.awk is selected by `parsing` or `test_parsing`
    files = select(args, files, lambda f: [f.stem, f.stem.removeprefix("test_")])
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


def read_cases(args: argparse.Namespace, bugs: bool | None) -> list[Case]:
    """The selected integration cases: with bugs=False, those without a `#: bug:` line, with
    bugs=True, those with one, and with bugs=None, all of them."""
    paths = sorted((ROOT / INTEGRATION_DIR).glob("*.test"))
    cases = [Case.read(INTEGRATION_DIR / p.name) for p in paths]
    cases = [c for c in cases if bugs is None or (c.bug is not None) == bugs]
    return select(args, cases, lambda c: [c.name])


def suite_integration(args: argparse.Namespace) -> list[Callable[[], Result]]:
    return [(lambda c=c: c.run(args)) for c in read_cases(args, bugs=False)]


def suite_bugs(args: argparse.Namespace) -> list[Callable[[], Result]]:
    return [(lambda c=c: c.run(args)) for c in read_cases(args, bugs=True)]


# ------------------------------------------------------------------------------------------
# lint
# ------------------------------------------------------------------------------------------
# stdout is discarded and the messages of makefile-doc.awk go to /dev/null (STDERR), so the
# stderr of gawk holds only its lint warnings
LINT_FLAGS = ["--lint", "-v", "STDERR=/dev/null"]
LINT_CONFIG = Path("test/tools/lint.toml")  # the expected warnings
# the input position in a warning, e.g. "(FILENAME=test/fixtures/Makefile.misc FNR=5) "
LINT_POSITION = re.compile(r"\(FILENAME=.*? FNR=\d+\) ")
# e.g. "gawk: makefile-doc.awk:1012: warning: ..." (some warnings have no file and line)
LINT_WARNING = re.compile(r"^gawk: (?:[^:]+:(?P<line>\d+): )?warning: (?P<message>.*)$")
# the rules: a regex for the message of each kind of warning; the group `name` is what the
# `allow` lists of lint.toml match (for uninit-element, the name of the array)
LINT_RULES = {
    "uninit-variable": re.compile(r"reference to uninitialized variable `(?P<name>[^']*)'"),
    "uninit-argument": re.compile(r"reference to uninitialized argument `(?P<name>[^']*)'"),
    "uninit-element": re.compile(r"reference to uninitialized element `(?P<name>[^\[']*)\[.*\]'"),
    "substr-start": re.compile(r"substr: start index \S+ is invalid, using 1"),
    "substr-past-end": re.compile(r"substr: start index \S+ is past end of string"),
    "substr-empty": re.compile(r"substr: source string is zero length"),
    "substr-length": re.compile(r"substr: length \S+ is not >= 1"),
    "no-close": re.compile(r"no explicit close of file `[^']*' provided"),
}
LINT_UNKNOWN = "unknown"  # a line that matches no rule (it is always reported)
# a comment in makefile-doc.awk that expects the warnings of rules at its line, e.g.
# `# lint: ignore[substr-start]` or `# lint: ignore[substr-start, uninit-argument]`; alone on
# its line (a long line has no room for it), it applies to the next line
LINT_INLINE = re.compile(r"#\s*lint:\s*ignore\[([^\]]*)\]")


@dataclass
class LintWarning:
    rule: str
    name: str | None  # the name matched by `allow` (rules with a `name` group)
    text: str  # the line without "gawk: " and "warning: ", e.g. "makefile-doc.awk:1012: ..."
    line: int  # the line of makefile-doc.awk (0 if there is none)

    @property
    def key(self) -> str:
        """What is reported once: the line, rule and name (e.g. "makefile-doc.awk:1012:
        uninit-argument is_variable"), so that the warnings about the elements of an array
        (one per key) or about substr (one per index) are grouped; an unknown warning as is."""
        if self.rule == LINT_UNKNOWN:
            return f"{LINT_UNKNOWN}: {self.text}"
        where = f"makefile-doc.awk:{self.line}: " if self.line else ""
        return where + self.rule + (f" {self.name}" if self.name is not None else "")

    @classmethod
    def parse(cls, line: str) -> "LintWarning":
        m = LINT_WARNING.match(line)
        if m:
            text = (f"makefile-doc.awk:{m['line']}: " if m["line"] else "") + m["message"]
            for rule, regex in LINT_RULES.items():
                r = regex.fullmatch(m["message"])
                if r:
                    return cls(rule, r.groupdict().get("name"), text, int(m["line"] or 0))
        return cls(LINT_UNKNOWN, None, m and text or line, int(m and m["line"] or 0))


def is_strings(value: object) -> bool:
    return isinstance(value, list) and all(isinstance(v, str) for v in value)


@dataclass
class LintConfig:
    ignore: list[str]  # rules that are never reported
    allow: dict[str, list[str]]  # rule -> the expected names (shell-style patterns)
    inline: dict[int, list[str]]  # line of makefile-doc.awk -> rules (`# lint: ignore[...]`)

    @classmethod
    def read(cls, path: Path, script: Path) -> "LintConfig":
        """Read lint.toml and the `# lint: ignore[...]` comments of the script; a key, rule
        or `allow` that is not valid is an error, so that a typo does not silently expect
        nothing."""
        try:
            data = tomllib.loads((ROOT / path).read_text())
        except (OSError, tomllib.TOMLDecodeError) as e:
            sys.exit(f"{path}: {e}")
        named = [rule for rule, regex in LINT_RULES.items() if "name" in regex.groupindex]
        errors = []
        ignore = data.pop("ignore", [])
        if not is_strings(ignore):
            errors.append("ignore: a list of rules is expected")
            ignore = []
        errors += [f"ignore: unknown rule {r!r}" for r in ignore if r not in LINT_RULES]
        allow = {}
        for key, table in data.items():
            if key not in LINT_RULES:
                errors.append(f"unknown rule or key {key!r}")
            elif key not in named:
                errors.append(f"[{key}]: the warnings of this rule have no names (use ignore)")
            elif not isinstance(table, dict) or set(table) != {"allow"}:
                errors.append(f"[{key}]: only `allow = [...]` is expected")
            elif not is_strings(table["allow"]):
                errors.append(f"[{key}]: allow: a list of names is expected")
            else:
                allow[key] = table["allow"]
        if errors:
            sys.exit("\n".join(f"{path}: {e}" for e in errors))

        inline = {}
        for number, line in enumerate((ROOT / script).read_text().splitlines(), 1):
            m = LINT_INLINE.search(line)
            if m:
                rules = [r.strip() for r in m.group(1).split(",")]
                errors += [
                    f"{script}:{number}: unknown rule {r!r}" for r in rules if r not in LINT_RULES
                ]
                alone = line.lstrip().startswith("#")  # alone on its line: for the next line
                inline[number + alone] = rules
        if errors:
            sys.exit("\n".join(errors))
        return cls(ignore, allow, inline)

    def expects(self, w: LintWarning) -> str | None:
        """The entry of lint.toml that expects the warning, if any (e.g. "ignore no-close" or
        "[uninit-variable] allow COLOR_*")."""
        if w.rule in self.ignore:
            return f"ignore {w.rule}"
        if w.rule in self.inline.get(w.line, []):
            return f"makefile-doc.awk:{w.line}: ignore[{w.rule}]"
        for pattern in self.allow.get(w.rule, []):
            if w.name is not None and fnmatch.fnmatchcase(w.name, pattern):
                return f"[{w.rule}] allow {pattern}"
        return None

    def entries(self) -> list[str]:
        return (
            [f"ignore {r}" for r in self.ignore]
            + [f"[{rule}] allow {p}" for rule, patterns in self.allow.items() for p in patterns]
            + [
                f"makefile-doc.awk:{line}: ignore[{rule}]"
                for line, rules in self.inline.items()
                for rule in rules
            ]
        )


def lint_case(case: Case, args: argparse.Namespace) -> Result:
    """Run a case with gawk --lint; its warnings (without input positions) are the details."""
    try:
        proc = run_awk(
            args.awk,
            [*LINT_FLAGS, *args.awk_flags, "-f", args.script, *shlex.split(case.args)],
            args.timeout,
            env=case.env,
        )
    except subprocess.TimeoutExpired:
        return timed_out(case.name, args.timeout)
    warnings = "".join(LINT_POSITION.sub("", line) + "\n" for line in proc.stderr.splitlines())
    return Result(case.name, True, "", details=warnings)


def suite_lint(args: argparse.Namespace) -> list[Callable[[], Result]]:
    return [(lambda c=c: lint_case(c, args)) for c in read_cases(args, bugs=None)]


def report_lint(results: list[Result], config: LintConfig, args: argparse.Namespace) -> int:
    """Print each distinct warning that lint.toml does not expect once (ordered by line of
    makefile-doc.awk), with its rule, the number of times it occurs and in how many cases
    (with --verbose, also the names of the cases). After a run of all the cases, the entries
    of lint.toml that expect no warning are reported too (they are stale)."""
    awk_name = Path(args.awk).name
    parsed: dict[str, LintWarning] = {}  # each distinct line of stderr is parsed once
    occurrences: dict[str, int] = {}  # key -> number of unexpected warnings
    cases: dict[str, set[str]] = {}  # key -> the cases with such warnings
    order: dict[str, int] = {}  # key -> line of makefile-doc.awk
    expected: set[str] = set()  # the keys of the expected warnings
    used: set[str] = set()  # the entries of lint.toml that expect a warning
    for r in results:
        for line in r.details.splitlines():
            w = parsed.get(line) or parsed.setdefault(line, LintWarning.parse(line))
            entry = config.expects(w)
            if entry:
                used.add(entry)
                expected.add(w.key)
                continue
            occurrences[w.key] = occurrences.get(w.key, 0) + 1
            cases.setdefault(w.key, set()).add(r.name)
            order[w.key] = w.line

    for key in sorted(occurrences, key=lambda key: (order[key], key)):
        n = len(cases[key])
        print(f"[{awk_name}] {key} ({occurrences[key]}x, {n} case{'s' * (n != 1)})")
        if args.verbose:
            print("    " + " ".join(sorted(cases[key])))

    stale = [] if args.names else [e for e in config.entries() if e not in used]
    for entry in stale:
        where = "" if entry.startswith("makefile-doc.awk:") else f"{LINT_CONFIG}: "
        print(f"[{awk_name}] {where}`{entry}` expects no warning (remove it)")
    failed = [r for r in results if not r.passed]
    for r in failed:
        print(f"[{awk_name}] FAILED {r.name} ({r.summary})")
    print(
        f"[{awk_name}] {len(occurrences)} unexpected lint warnings in {len(results)} "
        f"case{'s' * (len(results) != 1)} "
        f"({len(expected)} expected, see {LINT_CONFIG})"
    )
    return 1 if occurrences or stale or failed else 0


# ------------------------------------------------------------------------------------------
# main
# ------------------------------------------------------------------------------------------
T = TypeVar("T")


def select(args: argparse.Namespace, items: list[T], names: Callable[[T], list[str]]) -> list[T]:
    """The items with a name that matches a NAME argument (all the items if there is none). A
    NAME is an exact name or a shell-style pattern (* ? [...]); one that matches no item is an
    error, so that a typo does not pass as an empty run."""
    if not args.names:
        return items
    patterns = [n.removesuffix(".test").removesuffix(".awk") for n in args.names]
    matched, chosen = set(), []
    for item in items:
        hits = {p for p in patterns if any(fnmatch.fnmatchcase(n, p) for n in names(item))}
        matched |= hits
        if hits:
            chosen.append(item)
    unknown = [p for p in patterns if p not in matched]
    if unknown:
        sys.exit(f"no {args.suite} test matches: {' '.join(unknown)}")
    return chosen


SUITES: dict[str, Callable[[argparse.Namespace], list[Callable[[], Result]]]] = {
    "unit": suite_unit,
    "integration": suite_integration,
    "bugs": suite_bugs,
    "lint": suite_lint,
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
    parser.add_argument(
        "names",
        nargs="*",
        metavar="NAME",
        help="run only these tests: exact names (e.g., misc, parsing) or shell-style patterns "
        "(e.g., 'options-*'); a NAME that matches no test is an error",
    )
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
    return parser.parse_intermixed_args()  # NAME arguments can follow the options


def main() -> int:
    args = parse_args()
    tests = SUITES[args.suite](args)
    if not tests:
        if args.suite == "bugs" and not args.names:
            print(f"[{Path(args.awk).name}] no known bugs")
            return 0
        print(f"no {args.suite} tests found", file=sys.stderr)
        return 1

    awk_name = Path(args.awk).name
    lint_config = LintConfig.read(LINT_CONFIG, Path(args.script)) if args.suite == "lint" else None
    with ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
        results = list(pool.map(lambda test: test(), tests))

    if lint_config is not None:
        return report_lint(results, lint_config, args)

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
