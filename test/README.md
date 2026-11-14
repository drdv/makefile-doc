# Tests

- `make test@<variant>`: integration tests (`test/integration/`)
- `make utest@<variant>`: unit tests (`test/unit/`)
- `make bugs@<variant>`: reproducers for known, unfixed bugs (cases with `#: bug: N` in
  `test/integration/`)

For example, `make test@mawk` runs the integration tests with mawk, and `make test@all`
with every variant. `make test`, `utest` and `bugs` use `AWK` (default `awk`) and
`AWK_FLAGS`, e.g., `make test AWK=gawk AWK_FLAGS=--posix`.

The awk variants are downloaded and built into `test/bin/` when a test needs them. `make
deps@<variant>` (or `deps@all`) does this in advance, and `make clean@<variant>` (or
`clean@all`) removes them. `awk` and `gawk` are the ones installed on the system; the other
versions are pinned in `test/tools/deps.toml`, where each download is checked against its SHA256.
`make versions` shows the version that each installed variant reports and flags the ones
that differ from `deps.toml`: a variant already in `test/bin/` is not rebuilt when its
version changes (rebuild it with `make clean@<variant> deps@<variant>`).

The test tools in `test/` are written in Python (>= 3.11, standard library only). `make
lint-py` lints them and checks their formatting with [ruff](https://docs.astral.sh/ruff)
(settings in `ruff.toml`; `uvx ruff format test` reformats them), and `make test-tools` runs
their tests (`test/tools/test_*.py`, written with `unittest` and run with
[pytest](https://docs.pytest.org) through `uvx`; the tests of the lint suite run gawk on
a copy of `makefile-doc.awk` with an injected problem). The unit
and integration tests are run by `test/tools/run.py`. Options can be passed with `RUNNER_FLAGS`,
e.g., `make utest@mawk RUNNER_FLAGS='-v parsing'` (`-v` shows the output of passing
tests). Names select tests: a name is exact (`misc` is `test/integration/misc.test`,
`parsing` is `test/unit/test_parsing.awk`) or a shell-style pattern (`'options-*'`,
`'*no-color*'`); a name that matches no test is an error. A test fails if its awk process
runs for more than 30 seconds (`--timeout`).

`make bench@all` times `makefile-doc.awk` with each awk variant on large real Makefiles
(downloaded once into `test/bin/`, with docs inserted automatically) and prints a Markdown
table; `make bench@<variant>` times one variant. Options of `test/tools/bench.py` can be passed
with `BENCH_FLAGS`, e.g., `make bench@mawk BENCH_FLAGS='--rev HEAD --keep -n 10'`: also
show the change from the last commit (useful after changes to the parsing), keep the
annotated Makefiles in `test/bin/`, and take the best of 10 runs.

## Unit tests

Each `test/unit/test_*.awk` file is run in its own awk process, together with
`test/unit/harness.awk` and `makefile-doc.awk`. A test file calls the functions of
`makefile-doc.awk` directly and ends its `BEGIN` block with `done()`:

```awk
function test_string_replace() {
  check("string_replace: plain", string_replace("a", "X", "banana"), "bXnXnX")
  check_true("max: larger first", max(2, 1) == 2)
}

BEGIN {
  test_string_replace()
  done()
}
```

- `check(name, got, want)` and `check_true(name, condition)` record one check each.
- `check_bug(name, got, want, issue)` records a check of a known, unfixed bug (see below).
- `stderr_text()` returns what the code under test wrote to `STDERR` since the last call.
- `init_globals()` (from `makefile-doc.awk`) resets the global state; it has already been
  called when the tests start.
- `fatal()` does not exit in unit tests: it records its message in `FATAL_MSG`.
- `option_error()` reports an invalid option on `STDERR` (check it with `stderr_text()`)
  and counts it in `OPTION_ERRORS`; `init_globals()` resets the count.
- Declare the local variables of test functions in their signature (as in makefile-doc.awk):
  `make lint` fails if a test file defines other global variables than those of
  makefile-doc.awk and the harness (the rule `test-global` of `make lint-tests`).

The results are printed in [TAP](https://testanything.org) format. A test file fails if a
check fails, if it stops before `done()` (e.g., because of an `exit` or a syntax error), or if
awk exits with a non-zero status.

## Integration tests

Each `test/integration/*.test` file (a case) runs `makefile-doc.awk` on a fixture
(`test/fixtures/Makefile.*`) and holds the expected output. Metadata lines starting with
`#:` come first and are ignored when running. The next line holds the awk arguments (in
shell syntax). The remaining lines hold the expected output: stderr after a `#: stderr`
line, then stdout after a `#: stdout` line (a stream without output has no such line), then
`#: exit: N` if the exit status is not 0:

```
#: desc: what this test checks (the expected behavior)
#: issue: 123
-v COLOR_DEFAULT=0 -v SUB='...' test/fixtures/Makefile.sub
#: stderr
<expected stderr>
#: stdout
<expected stdout>
#: exit: 1
```

The output must match the expected output exactly, including blanks at the end of lines and
the final newline. Use `--update` to regenerate the expected output, e.g., `make test@awk
RUNNER_FLAGS='--update docs-precedence'` (check the diff by hand).

Conventions:

- A fixture covers one topic and stays small, so that a change affects few cases. Add a
  new fixture rather than growing an unrelated one.
- A case is named after its fixture: `<topic>.test` or `<topic>-<variation>.test` for
  `Makefile.<topic>` (e.g., `sub-L.test` uses `Makefile.sub`). Fixtures about targets start
  with `targets-`, about variables with `vars-`, and about docs with `docs-`.
- Every case has a `#: desc:` line, and an `#: issue:` line if it comes from an issue.
- Colors are turned off (`-v COLOR=0`) unless the case is about colors or output formats.
  The runner removes `NO_COLOR` from the environment of the tests.
- A `#: env: NAME=value` line sets an environment variable for the case (e.g.,
  `#: env: NO_COLOR=1`).

## Lint

`make lint-tests` runs every integration case and unit test file with `gawk --lint` (the
`lint` suite of `test/tools/run.py`) and prints each distinct warning once, e.g.,
`makefile-doc.awk:1012: uninit-argument is_variable (123x, 41 runs)`: the line, the rule and
the name. The output of the tests is not compared. Unlike `gawk --lint` without input, this
lints the code that runs only on input (the parsing and the output). Names select cases and
unit test files, e.g., `make lint-tests RUNNER_FLAGS='-v misc parsing'` (`-v` lists the runs
of each warning).

A warning is classified by a rule (`LINT_RULES` in `run.py`), e.g., `uninit-variable`,
`uninit-argument`, `uninit-element`, `substr-start`; a warning that matches no rule is
`unknown`. The suite fails if a warning in `makefile-doc.awk` is not expected:

- in `test/tools/lint.toml`: `ignore = [...]` (rules that are never reported) and, per rule,
  `allow = [...]` (expected names, e.g., the options passed with `-v`, or `COLOR_*`);
- or by a `# lint: ignore[RULE, ...]` comment at the end of its line (or alone on the line
  before it), for an idiom at one place, e.g., the last character of an empty line.

An entry or comment that expects no warning is reported after a run of everything (it is
stale), and an invalid one is an error. Warnings in test code (the harness and the unit
test files) that `lint.toml` does not expect are listed for information only.

The suite also checks the global variables, in the dumps of `gawk -d` (`LINT_CHECKS` in
`run.py`), and reports them as warnings of two rules: `global-name`, a global variable of
`makefile-doc.awk` that is neither `UPPER_CASE` nor `g_lower_case`, and `test-global`, a
global variable that a unit test file defines and that neither `makefile-doc.awk` nor the
harness (`HARNESS_*`) defines (e.g., a local variable missing from a function signature).
These are checked in test code too.

## Reporting and fixing bugs

1. **Open an issue.** Every bug should have one.
2. **Reproducer (optional, can be a separate PR):** written by hand with the *correct*
   expected result. It is merged even if no fix exists yet.
   - Integration test: a case `test/integration/<name>.test` with a `#: bug: N` line.
     `make test` skips it and `make bugs` runs it.
   - Unit test: a `check_bug(name, got, want, issue)` call next to the other checks of the
     same function. `make utest` reports it as a known bug.
3. **Fix:** the fix PR changes the code and turns the reproducer into a regular test:
   `#: bug: N` becomes `#: issue: N`, and `check_bug` becomes `check`. `make bugs` and
   `make utest` fail once a reproducer passes, so a forgotten change is caught.

Every reproducer needs an issue number, so known bugs never become an undocumented backlog.

`make bugs@bawk` also runs `misc/busybox_awk_bug_20251107.awk`, a bug of busybox awk that
`makefile-doc.awk` works around: it fails once busybox has fixed it, and the workaround can
then be removed.
`make bugs` lists the known bugs of the integration tests (`-v` shows their diffs).
