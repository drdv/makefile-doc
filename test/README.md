# Tests

- `make test@<variant>`: integration tests (`test/integration/`)
- `make utest@<variant>`: unit tests (`test/unit/`)
- `make bugs@<variant>`: reproducers for known, unfixed bugs (recipes with `#: bug: N` in
  `test/integration/`)

For example, `make test@mawk` runs the integration tests with mawk, and `make test@all`
with every variant. `make test`, `utest` and `bugs` use `AWK` (default `awk`) and
`AWK_FLAGS`, e.g., `make test AWK=gawk AWK_FLAGS=--posix`.

The awk variants are downloaded and built into `test/bin/` when a test needs them. `make
deps@<variant>` (or `deps@all`) does this in advance, and `make clean@<variant>` (or
`clean@all`) removes them. `awk` and `gawk` are the ones installed on the system; the other
versions are pinned in `test/deps.toml`, where each download is checked against its SHA256.

The test tools in `test/` are written in Python (>= 3.11, standard library only). `make
lint-py` lints them and checks their formatting with [ruff](https://docs.astral.sh/ruff)
(settings in `ruff.toml`; `uvx ruff format test` reformats them). The unit
and integration tests are run by `test/run.py`. Options can be passed with `RUNNER_FLAGS`,
e.g., `make utest@mawk RUNNER_FLAGS='-v -k parsing'` (`-v` shows the output of passing
tests, `-k` selects tests whose name contains a string). A test fails if its awk process
runs for more than 30 seconds (`--timeout`).

`make bench@all` times `makefile-doc.awk` with each awk variant on large real Makefiles
(downloaded once into `test/bin/`, with docs inserted automatically) and prints a Markdown
table; `make bench@<variant>` times one variant. Options of `test/bench.py` can be passed
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
  makefile-doc.awk and the harness (`check-test-variables`).

The results are printed in [TAP](https://testanything.org) format. A test file fails if a
check fails, if it stops before `done()` (e.g., because of an `exit` or a syntax error), or if
awk exits with a non-zero status.

## Integration tests

Each `test/integration/test-*` file (a recipe) runs `makefile-doc.awk` on a fixture
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
RUNNER_FLAGS='--update -k test-docs-precedence'` (check the diff by hand).

Conventions:

- A fixture covers one topic and stays small, so that a change affects few recipes. Add a
  new fixture rather than growing an unrelated one.
- A recipe is named after its fixture: `test-<topic>` or `test-<topic>-<case>` for
  `Makefile.<topic>` (e.g., `test-sub-L` uses `Makefile.sub`). Fixtures about targets start
  with `targets-`, about variables with `vars-`, and about docs with `docs-`.
- Every recipe has a `#: desc:` line, and an `#: issue:` line if it comes from an issue.
- Colors are turned off (`-v COLOR=0`) unless the recipe is about colors or output formats.
  The runner removes `NO_COLOR` from the environment of the tests.
- A `#: env: NAME=value` line sets an environment variable for the recipe (e.g.,
  `#: env: NO_COLOR=1`).

## Reporting and fixing bugs

1. **Open an issue.** Every bug should have one.
2. **Reproducer (optional, can be a separate PR):** written by hand with the *correct*
   expected result. It is merged even if no fix exists yet.
   - Integration test: a recipe `test/integration/test-<name>` with a `#: bug: N` line.
     `make test` skips it and `make bugs` runs it.
   - Unit test: a `check_bug(name, got, want, issue)` call next to the other checks of the
     same function. `make utest` reports it as a known bug.
3. **Fix:** the fix PR changes the code and turns the reproducer into a regular test:
   `#: bug: N` becomes `#: issue: N`, and `check_bug` becomes `check`. `make bugs` and
   `make utest` fail once a reproducer passes, so a forgotten change is caught.

Every reproducer needs an issue number, so known bugs never become an undocumented backlog.
`make bugs` lists the known bugs of the integration tests (`-v` shows their diffs).
