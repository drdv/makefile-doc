# Tests

- `make test@<variant>`: integration tests (`test/integration/`)
- `make utest@<variant>`: unit tests (`test/unit/`)
- `make lint`: lint the awk code (`lint-tests`) and the Python code (`lint-py`)
- `make test-tools`: tests of the Python tools in `test/tools/`
- `make check`: all of the above, with the awk variant `AWK`

For example, `make test@mawk` runs the integration tests with mawk, and `make test@all`
with every variant. `make test` and `utest` use `AWK` (default `awk`) and `AWK_FLAGS`,
e.g., `make test AWK=gawk AWK_FLAGS=--posix`.

The awk variants are downloaded and built into `test/bin/` when a test needs them. `make
deps@<variant>` (or `deps@all`) does this in advance, and `make clean@<variant>` (or
`clean@all`) removes them. `awk` and `gawk` are the ones installed on the system; the other
versions are pinned in `test/tools/deps.toml`, where each download is checked against its SHA256.
`make versions` shows the version that each installed variant reports and flags the ones
that differ from `deps.toml`: a variant already in `test/bin/` is not rebuilt when its
version changes (rebuild it with `make clean@<variant> deps@<variant>`).

## Python, uv and pytest

The tests are run by [pytest](https://docs.pytest.org) (`tests_new/`), and the tools in
`test/tools/` are written in Python. [uv](https://docs.astral.sh/uv) is the only thing to
install: `uv run` creates `.venv/` with the Python version and the packages of
`pyproject.toml`, at the versions pinned in `uv.lock`. The Makefile calls everything
through `uv run`.

| File                            | Tests                                                |
|---------------------------------|------------------------------------------------------|
| `tests_new/conftest.py`         | the `--awk` and `--update` options, how awk is run   |
| `tests_new/test_integration.py` | one test per `test/integration/*.test` case          |
| `tests_new/test_unit.py`        | one test per `test/unit/test_*.awk` file             |
| `tests_new/test_lint.py`        | `gawk --lint` and the checks of the global variables |

pytest can be called directly; `--awk` is an awk command with its flags and can be
repeated (the default is `$AWK`, or `awk`):

```
uv run pytest --awk gawk                              # everything, with gawk
uv run pytest --awk gawk --awk 'gawk --posix' --awk mawk
uv run pytest --awk 'busybox awk' tests_new/test_unit.py
uv run pytest --awk gawk -k options-no-color           # the tests with this text in their name
uv run pytest --awk gawk --collect-only -q             # list the tests
```

The awk commands of a run are shown after the number of collected tests (`awk: gawk,
mawk`). A test is named after its awk and its case or file, e.g.,
`test_case[gawk-options-no-color]` and `test_unit[mawk-parsing]`. `-k` selects by a part of
the name (`-k options-`, `-k 'parsing and mawk'`); it does not take patterns such as
`options-*`. Other useful options: `-x` (stop at the first failure), `-vv` (full diffs) and
`--pdb` (open the debugger at a failure). With `make`, options are passed with
`PYTEST_FLAGS`, e.g., `make utest@mawk PYTEST_FLAGS='-k parsing'`.

awk runs in a fixed environment (`PATH` and `LC_ALL=C` only), so the variables of your
shell (`NO_COLOR`, `AWKPATH`, the locale) do not change the results. An awk process that
runs for more than 30 seconds fails its test.

`make lint-py` lints the Python code and checks its formatting with
[ruff](https://docs.astral.sh/ruff) (settings in `ruff.toml`; `uv run ruff format`
reformats it), and `make test-tools` runs the tests of the tools (`test/tools/test_*.py`).

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
  makefile-doc.awk and the harness.

The results are printed in [TAP](https://testanything.org) format, which
`tests_new/test_unit.py` reads: each check is reported as a subtest of the test of its
file, and a failed check is shown with its `got` and `want` values. A test file fails if a
check fails, if it stops before `done()` (e.g., because of an `exit` or a syntax error), or
if awk exits with a non-zero status.

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
the final newline. `--update` writes the actual output into the cases that differ, e.g.,
`make test@awk PYTEST_FLAGS='--update -k docs-precedence'` (check the diff by hand); it
takes one `--awk` only, and does not touch the cases of known bugs. The version of the
script (the line `Version: v1.8` of `--help`) is written `Version: @VERSION@` in expected
outputs, so a new version does not change the `.test` files.

Conventions:

- A fixture covers one topic and stays small, so that a change affects few cases. Add a
  new fixture rather than growing an unrelated one.
- A case is named after its fixture: `<topic>.test` or `<topic>-<variation>.test` for
  `Makefile.<topic>` (e.g., `sub-L.test` uses `Makefile.sub`). Fixtures about targets start
  with `targets-`, about variables with `vars-`, and about docs with `docs-`.
- Every case has a `#: desc:` line, and an `#: issue:` line if it comes from an issue.
- Colors are turned off (`-v COLOR=0`) unless the case is about colors or output formats.
- A `#: env: NAME=value` line sets an environment variable for the case (e.g.,
  `#: env: NO_COLOR=1`).

## Lint

`make lint-tests` (`tests_new/test_lint.py`) runs every integration case and unit test file
with `gawk --lint` and collects the distinct warnings; the output of the tests is not
compared. Unlike `gawk --lint` without input, this lints the code that runs only on input
(the parsing and the output). It uses the `gawk` in `PATH` and is skipped without one.

A warning in `makefile-doc.awk` fails `test_no_unexpected_warnings` unless it is expected:

- by a regular expression of `ignore` in `[tool.makefile-doc.lint]` of `pyproject.toml`.
  It is searched in the warning written as `<file>: <message>`, e.g.,
  ``makefile-doc.awk: reference to uninitialized variable `COLOR_DEFAULT'``;
- or by a `# lint: ignore[TEXT]` comment, for an idiom at one place, where `TEXT` is a
  part of the message of the warning:

  ```awk
  last = substr(text, length(text), 1) # lint: ignore[substr: start index] ("" for an empty text)
  ```

  The comment is at the end of the line of the warning, or alone on the line before it.
  For several warnings at one line, write one comment per line above it. What follows
  the `]` is a note for the reader.

An `ignore` entry or a comment that expects no warning fails `test_no_stale_ignore`.
Warnings in test code (the harness and the unit test files) are not checked.

Two more tests check the global variables, in the dumps of `gawk -d`: `test_global_names`
fails for a global variable of `makefile-doc.awk` that is neither `UPPER_CASE` nor
`g_lower_case`, and `test_unit_file_defines_no_globals` for a global variable that a unit
test file defines and that neither `makefile-doc.awk` nor the harness (`HARNESS_*`) defines
(e.g., a local variable missing from a function signature).

## Benchmark

`make bench@all` times `makefile-doc.awk` with each awk variant on large real Makefiles
(downloaded once into `test/bin/`, with docs inserted automatically) and prints a Markdown
table; `make bench@<variant>` times one variant. Options of `test/tools/bench.py` can be passed
with `BENCH_FLAGS`, e.g., `make bench@mawk BENCH_FLAGS='--rev HEAD --keep -n 10'`: also
show the change from the last commit (useful after changes to the parsing), keep the
annotated Makefiles in `test/bin/`, and take the best of 10 runs.

## Releasing

The version is defined in `makefile-doc.awk` (`VERSION = "v1.9"`); the install snippet of
the README (`help: VER := v1.9`) is a copy of it. The release notes are the message of the
annotated tag, so they are kept in git (`git show v1.10`). A release:

1. `make release-notes` writes a draft of the notes to `release-message.md` (the commits
   since the last tag); edit it;
2. `make bump V=v1.10` sets the version in the script and the README, commits them, creates
   the annotated tag with `release-message.md` as its message, and deletes the file
   (`test/tools/release.py`; without `release-message.md`, `bump` only sets the version);
3. push the commit and the tag: `git push && git push origin v1.10`;
4. the tag runs `.github/workflows/release.yml`: the tests (the CI workflow), a check that
   the tag, the script and the README have the same version, then a draft release with
   `makefile-doc.awk` and its checksum, and the message of the tag as notes;
5. review the draft on GitHub and publish it.

## Reporting and fixing bugs

1. **Open an issue.** Every bug should have one.
2. **Reproducer (optional, can be a separate PR):** written by hand with the *correct*
   expected result. It is merged even if no fix exists yet.
   - Integration test: a case `test/integration/<name>.test` with a `#: bug: N` line.
   - Unit test: a `check_bug(name, got, want, issue)` call next to the other checks of the
     same function.

   Both are run with the other tests and are expected to fail: pytest reports them as
   `xfailed`.
3. **Fix:** the fix PR changes the code and turns the reproducer into a regular test:
   `#: bug: N` becomes `#: issue: N`, and `check_bug` becomes `check`. The tests fail once
   a reproducer passes (`XPASS(strict)` for a case, `FIXED` for a check), so a forgotten
   change is caught.

Every reproducer needs an issue number, so known bugs never become an undocumented backlog.

`make test@bawk` also runs `misc/busybox_awk_bug_20251107.awk`, a bug of busybox awk that
`makefile-doc.awk` works around: it fails once busybox has fixed it, and the workaround can
then be removed.
