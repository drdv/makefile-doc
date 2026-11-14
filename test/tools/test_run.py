"""Tests of test/tools/run.py (standard library only).

usage: python3 -m unittest discover -s test/tools -p 'test_*.py'   (or `make test-tools`)

The unit tests need no awk. The end-to-end tests of the lint suite run run.py with gawk (the
environment variable GAWK, or gawk in PATH) on a copy of makefile-doc.awk with an injected
problem; they are skipped if there is no gawk.
"""

import argparse
import contextlib
import importlib.util
import io
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
ROOT = TOOLS.parent.parent

# run.py is not a package: load it from its file (registered in sys.modules for dataclasses)
_spec = importlib.util.spec_from_file_location("run", TOOLS / "run.py")
run = importlib.util.module_from_spec(_spec)
sys.modules["run"] = run
_spec.loader.exec_module(run)

GAWK = os.environ.get("GAWK") or shutil.which("gawk")
SCRIPT = "makefile-doc.awk"


def parse(line: str) -> "run.LintWarning":
    return run.LintWarning.parse(line)


class TempDir(unittest.TestCase):
    """A test with a temporary directory (self.tmp) that is removed afterwards."""

    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = Path(tmp.name)

    def write(self, name: str, text: str) -> Path:
        path = self.tmp / name
        path.write_text(text)
        return path  # absolute: ROOT / path is path


# ------------------------------------------------------------------------------------------
# lint: warnings
# ------------------------------------------------------------------------------------------
class TestLintWarning(unittest.TestCase):
    def test_rule_name_file_line(self) -> None:
        w = parse("gawk: makefile-doc.awk:12: warning: reference to uninitialized variable `FOO'")
        self.assertEqual((w.rule, w.name, w.file, w.line), ("uninit-variable", "FOO", SCRIPT, 12))
        self.assertEqual(w.key, "makefile-doc.awk:12: uninit-variable FOO")

    def test_elements_of_an_array_are_grouped(self) -> None:
        a = parse('gawk: f.awk:3: warning: reference to uninitialized element `ARR["a"]\'')
        b = parse('gawk: f.awk:3: warning: reference to uninitialized element `ARR["b c"]\'')
        self.assertEqual((a.rule, a.name), ("uninit-element", "ARR"))
        self.assertEqual(a.key, b.key)

    def test_substr_indexes_are_grouped(self) -> None:
        a = parse("gawk: f.awk:7: warning: substr: start index 4 is past end of string")
        b = parse("gawk: f.awk:7: warning: substr: start index 11 is past end of string")
        self.assertEqual(a.rule, "substr-past-end")
        self.assertIsNone(a.name)
        self.assertEqual(a.key, b.key)
        self.assertEqual(a.key, "f.awk:7: substr-past-end")

    def test_warning_without_file(self) -> None:
        w = parse("gawk: warning: function `helper' defined but never called directly")
        self.assertEqual((w.rule, w.name, w.file, w.line), ("unused-function", "helper", "", 0))
        self.assertEqual(w.key, "unused-function helper")

    def test_unknown_message(self) -> None:
        w = parse("gawk: makefile-doc.awk:3: warning: statement has no effect")
        self.assertEqual((w.rule, w.file, w.line), (run.LINT_UNKNOWN, SCRIPT, 3))
        self.assertEqual(w.key, "unknown: makefile-doc.awk:3: statement has no effect")

    def test_line_that_is_not_a_warning(self) -> None:
        w = parse("gawk: fatal: cannot open file `x'")
        self.assertEqual(
            (w.rule, w.file, w.text), (run.LINT_UNKNOWN, "", "gawk: fatal: cannot open file `x'")
        )

    def test_check_line(self) -> None:
        w = parse("check: test/unit/test_x.awk: test-global leaked")
        self.assertEqual(
            (w.rule, w.name, w.file), ("test-global", "leaked", "test/unit/test_x.awk")
        )
        self.assertEqual(w.key, "test/unit/test_x.awk: test-global leaked")

    def test_check_line_with_unknown_rule(self) -> None:
        self.assertEqual(parse("check: f.awk: no-such-check x").rule, run.LINT_UNKNOWN)

    def test_lint_lines_removes_input_positions(self) -> None:
        stderr = "gawk: f.awk:1: (FILENAME=Makefile FNR=5) warning: substr: x\n"
        self.assertEqual(run.lint_lines(stderr), "gawk: f.awk:1: warning: substr: x\n")


# ------------------------------------------------------------------------------------------
# lint: configuration (lint.toml and inline comments)
# ------------------------------------------------------------------------------------------
VALID_TOML = """\
ignore = ["no-close"]

[uninit-variable]
allow = ["COLOR_*", "VARS"]
"""

SCRIPT_WITH_COMMENTS = """\
BEGIN { x = 1 }
y = substr(s, 0) # lint: ignore[substr-start, substr-empty]
# lint: ignore[uninit-element] (for the next line)
z = a["k"]
"""


class TestLintConfig(TempDir):
    def read(self, toml: str = VALID_TOML, script: str = SCRIPT_WITH_COMMENTS) -> "run.LintConfig":
        return run.LintConfig.read(self.write("lint.toml", toml), str(self.write("s.awk", script)))

    def assert_error(self, message: str, toml: str = VALID_TOML, script: str = "") -> None:
        with self.assertRaises(SystemExit) as cm:
            self.read(toml, script)
        self.assertIn(message, str(cm.exception.code))

    def test_valid(self) -> None:
        config = self.read()
        self.assertEqual(config.ignore, ["no-close"])
        self.assertEqual(config.allow, {"uninit-variable": ["COLOR_*", "VARS"]})
        # a trailing comment is for its line, a comment alone on its line for the next line
        self.assertEqual(
            config.inline, {2: ["substr-start", "substr-empty"], 4: ["uninit-element"]}
        )

    def test_errors(self) -> None:
        self.assert_error("unknown rule or key 'typo'", toml="[typo]\nallow = []\n")
        self.assert_error("ignore: unknown rule 'nope'", toml='ignore = ["nope"]\n')
        self.assert_error("ignore: a list of rules is expected", toml='ignore = "no-close"\n')
        self.assert_error("have no names (use ignore)", toml='[substr-start]\nallow = ["x"]\n')
        self.assert_error(
            "allow: a list of names is expected", toml='[uninit-variable]\nallow = "X"\n'
        )
        self.assert_error(
            "only `allow = [...]` is expected", toml='[uninit-variable]\nalow = ["X"]\n'
        )
        self.assert_error("lint.toml", toml="ignore = [\n")  # invalid TOML

    def test_unknown_rule_in_a_comment_is_reported_at_the_comment(self) -> None:
        self.assert_error("s.awk:2: unknown rule 'nope'", script="BEGIN {}\n# lint: ignore[nope]\n")

    def test_checks_are_rules_of_lint_toml(self) -> None:
        config = self.read(toml='[global-name]\nallow = ["badName"]\n', script="")
        self.assertEqual(config.allow, {"global-name": ["badName"]})

    def test_expects(self) -> None:
        config = self.read()
        script = config.script

        def warning(file: str, line: int, message: str) -> "run.LintWarning":
            return parse(f"gawk: {file}:{line}: warning: {message}")

        self.assertEqual(
            config.expects(parse("gawk: warning: no explicit close of file `x' provided")),
            "ignore no-close",
        )
        self.assertEqual(
            config.expects(warning(script, 9, "reference to uninitialized variable `COLOR_X'")),
            "[uninit-variable] allow COLOR_*",
        )
        self.assertIsNone(
            config.expects(warning(script, 9, "reference to uninitialized variable `X'"))
        )
        self.assertEqual(
            config.expects(warning(script, 4, 'reference to uninitialized element `a["k"]\'')),
            f"{script}:4: ignore[uninit-element]",
        )
        # an inline comment is only for its file and line
        self.assertIsNone(
            config.expects(warning(script, 3, 'reference to uninitialized element `a["k"]\''))
        )
        self.assertIsNone(
            config.expects(warning("other.awk", 4, 'reference to uninitialized element `a["k"]\''))
        )

    def test_entries(self) -> None:
        config = self.read()
        self.assertEqual(
            config.entries(),
            [
                "ignore no-close",
                "[uninit-variable] allow COLOR_*",
                "[uninit-variable] allow VARS",
                f"{config.script}:2: ignore[substr-start]",
                f"{config.script}:2: ignore[substr-empty]",
                f"{config.script}:4: ignore[uninit-element]",
            ],
        )


# ------------------------------------------------------------------------------------------
# lint: report
# ------------------------------------------------------------------------------------------
class TestReportLint(TempDir):
    def setUp(self) -> None:
        super().setUp()
        toml = '[uninit-variable]\nallow = ["OPTION"]\n'
        script = self.write("s.awk", "BEGIN {}\nx = substr(s, 0) # lint: ignore[substr-start]\n")
        self.config = run.LintConfig.read(self.write("lint.toml", toml), str(script))
        self.script = self.config.script
        # warnings that use all the entries (so that nothing is stale)
        self.expected = (
            f"gawk: {self.script}:1: warning: reference to uninitialized variable `OPTION'\n"
            f"gawk: {self.script}:2: warning: substr: start index 0 is invalid, using 1\n"
        )

    def report(self, results: list, names: list[str] | None = None) -> tuple[int, str]:
        args = argparse.Namespace(awk="/usr/bin/gawk", names=names or [], verbose=False)
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            status = run.report_lint(results, self.config, args)
        return status, out.getvalue()

    def case(self, details: str) -> "run.Result":
        return run.Result("case", True, "", details=details)

    def unit(self, details: str) -> "run.Result":
        return run.Result("test_x", True, "", details=details, label=run.UNIT_LABEL)

    def test_only_expected_warnings(self) -> None:
        status, out = self.report([self.case(self.expected)])
        self.assertEqual(status, 0)
        self.assertIn("0 unexpected lint warnings in 1 case and 0 unit test files (2 expected", out)

    def test_unexpected_warning_in_the_script(self) -> None:
        warning = f"gawk: {self.script}:1: warning: reference to uninitialized variable `TYPO'\n"
        status, out = self.report([self.case(self.expected + warning), self.case(warning)])
        self.assertEqual(status, 1)
        self.assertIn(f"[gawk] {self.script}:1: uninit-variable TYPO (2x, 1 run)", out)

    def test_warning_in_test_code_is_for_information(self) -> None:
        warning = "gawk: test/unit/harness.awk:5: warning: statement has no effect\n"
        status, out = self.report([self.case(self.expected), self.unit(warning)])
        self.assertEqual(status, 0)
        self.assertIn("in test code (for information only):", out)
        self.assertIn("unknown: test/unit/harness.awk:5: statement has no effect", out)

    def test_warning_without_file(self) -> None:
        warning = "gawk: warning: function `f' defined but never called directly\n"
        # from a unit test file: test code (information); from a case: the script (checked)
        self.assertEqual(self.report([self.case(self.expected), self.unit(warning)])[0], 0)
        self.assertEqual(self.report([self.case(self.expected + warning)])[0], 1)

    def test_check_in_test_code_is_checked(self) -> None:
        check = "check: test/unit/test_x.awk: test-global leaked\n"
        globals_result = run.Result(
            "global variables", True, "", details=check, label=run.GLOBALS_LABEL
        )
        status, out = self.report([self.case(self.expected), globals_result])
        self.assertEqual(status, 1)
        self.assertIn("test/unit/test_x.awk: test-global leaked (1x, 1 run)", out)

    def test_stale_entries_after_a_full_run(self) -> None:
        status, out = self.report([self.case("")])
        self.assertEqual(status, 1)
        self.assertIn("lint.toml: `[uninit-variable] allow OPTION` expects no warning", out)
        self.assertIn(f"`{self.script}:2: ignore[substr-start]` expects no warning", out)

    def test_no_stale_entries_after_a_run_of_some_tests(self) -> None:
        status, out = self.report([self.case("")], names=["case"])
        self.assertEqual(status, 0)
        self.assertNotIn("expects no warning", out)

    def test_failed_run(self) -> None:
        status, out = self.report([self.case(self.expected), run.timed_out("slow", 30)])
        self.assertEqual(status, 1)
        self.assertIn("FAILED slow (timed out after 30 s)", out)


# ------------------------------------------------------------------------------------------
# selection of tests by name
# ------------------------------------------------------------------------------------------
class TestSelect(unittest.TestCase):
    ITEMS = ["misc", "recipeprefix-misc-plus", "options-no-color", "options-invalid"]

    def select(self, *names: str) -> list[str]:
        args = argparse.Namespace(names=list(names), suite="integration")
        return run.select(args, self.ITEMS, lambda item: [item])

    def test_no_names_selects_everything(self) -> None:
        self.assertEqual(self.select(), self.ITEMS)

    def test_exact_name(self) -> None:
        self.assertEqual(self.select("misc"), ["misc"])
        self.assertEqual(self.select("misc.test"), ["misc"])

    def test_patterns(self) -> None:
        self.assertEqual(self.select("options-*"), ["options-no-color", "options-invalid"])
        self.assertEqual(
            self.select("*misc*", "options-inv?lid"), self.ITEMS[:2] + ["options-invalid"]
        )

    def test_unknown_name_is_an_error(self) -> None:
        with self.assertRaises(SystemExit) as cm:
            self.select("misc", "nope")
        self.assertEqual(cm.exception.code, "no integration test matches: nope")

    def test_unit_test_names(self) -> None:
        self.assertEqual(
            run.unit_names(Path("test/unit/test_parsing.awk")), ["test_parsing", "parsing"]
        )


# ------------------------------------------------------------------------------------------
# integration cases and unit tests (TAP)
# ------------------------------------------------------------------------------------------
class TestCase(TempDir):
    def test_read(self) -> None:
        path = self.write(
            "x.test",
            "#: desc: a case\n#: bug: 12\n#: env: NO_COLOR=1\n-v COLOR=0 Makefile.x\n"
            "#: stdout\nout\n#: exit: 1\n",
        )
        case = run.Case.read(path)
        self.assertEqual(case.name, "x")
        self.assertEqual(case.args, "-v COLOR=0 Makefile.x")
        self.assertEqual(case.bug, "12")
        self.assertEqual(case.env, {"NO_COLOR": "1"})
        self.assertEqual(case.expected, b"#: stdout\nout\n#: exit: 1\n")

    def test_render_output(self) -> None:
        self.assertEqual(run.render_output(b"", b"out\n", 0), b"#: stdout\nout\n")
        self.assertEqual(run.render_output(b"err\n", b"", 1), b"#: stderr\nerr\n#: exit: 1\n")
        self.assertEqual(run.render_output(b"", b"", 0), b"")


class TestCheckTap(unittest.TestCase):
    def test_passed(self) -> None:
        self.assertEqual(run.check_tap("ok 1 - a\nok 2 - b\n1..2\n", 0), (True, "2 checks", 2))

    def test_failed_check(self) -> None:
        passed, summary, _ = run.check_tap("ok 1\nnot ok 2\n1..2\n", 1)
        self.assertFalse(passed)
        self.assertIn("1 of 2 checks failed", summary)

    def test_known_bug(self) -> None:
        tap = "ok 1\nnot ok 2 - x # TODO issue 7\n1..2\n"
        self.assertEqual(run.check_tap(tap, 0), (True, "2 checks, known bugs: 1", 2))

    def test_fixed_bug(self) -> None:
        passed, summary, _ = run.check_tap("ok 1 - x # TODO issue 7\n1..1\n", 0)
        self.assertFalse(passed)
        self.assertIn("FIXED: check 1 (issue 7)", summary)

    def test_missing_plan(self) -> None:
        passed, summary, _ = run.check_tap("ok 1\n", 0)
        self.assertFalse(passed)
        self.assertIn("no TAP plan", summary)

    def test_plan_mismatch(self) -> None:
        passed, summary, _ = run.check_tap("ok 1\n1..2\n", 0)
        self.assertFalse(passed)
        self.assertIn("does not match", summary)

    def test_bail_out(self) -> None:
        self.assertEqual(run.check_tap("Bail out! no file\n", 2), (False, "Bail out! no file", 0))


# ------------------------------------------------------------------------------------------
# end to end: the lint suite on a copy of makefile-doc.awk with an injected problem
# ------------------------------------------------------------------------------------------
@unittest.skipIf(GAWK is None, "gawk is not installed")
class TestLintSuite(TempDir):
    def lint(
        self, inject: str = "", append: str = "", names: tuple[str, ...] = ("misc",)
    ) -> tuple[int, str]:
        """Run `run.py lint` on a copy of the script: `inject` is added at the start of
        init_globals (run by every case), `append` at the end of the script."""
        text = (ROOT / SCRIPT).read_text()
        start = "function init_globals() {\n"
        self.assertIn(start, text)
        copy = self.write(SCRIPT, text.replace(start, start + inject, 1) + append)
        proc = subprocess.run(
            [
                sys.executable,
                str(TOOLS / "run.py"),
                "lint",
                "--awk",
                GAWK,
                "--script",
                str(copy),
                *names,
            ],
            cwd=ROOT,
            capture_output=True,
            text=True,
        )
        return proc.returncode, proc.stdout + proc.stderr

    def test_clean_script(self) -> None:
        status, out = self.lint(names=())
        self.assertEqual(status, 0, out)
        self.assertIn("0 unexpected lint warnings", out)

    def test_uninitialized_variable(self) -> None:
        status, out = self.lint(inject="  PROBE = NEVER_SET_PROBE + 1\n")
        self.assertEqual(status, 1, out)
        self.assertIn("uninit-variable NEVER_SET_PROBE", out)

    def test_parse_time_warning(self) -> None:
        status, out = self.lint(append="\nfunction probe_unused() { PROBE == 1 }\n")
        self.assertEqual(status, 1, out)
        self.assertIn("statement has no effect", out)
        self.assertIn("unused-function probe_unused", out)

    def test_global_name(self) -> None:
        status, out = self.lint(inject="  badName = 1\n")
        self.assertEqual(status, 1, out)
        self.assertIn("global-name badName", out)

    def test_stale_inline_comment(self) -> None:
        status, out = self.lint(inject="  # lint: ignore[uninit-argument]\n", names=())
        self.assertEqual(status, 1, out)
        self.assertIn("ignore[uninit-argument]` expects no warning", out)


if __name__ == "__main__":
    unittest.main()
