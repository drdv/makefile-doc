# Tests

- `make test`: integration tests (`test/integration/`)
- `make utest`: unit tests (`test/unit/`)
- `make bugs`: reproducers for known, unfixed bugs (recipes with `#: bug: N` in
  `test/integration/`)

Add `AWK=<variant>` to run with a specific awk (or use `test@<variant>`, e.g., `make
test@mawk`), or use `test@all` / `utest@all` / `bugs@all` for all of them.

The awk variants are downloaded and built into `test/bin/` when a test needs them. `make
deps@<variant>` (or `deps@all`) does this in advance, and `make clean@<variant>` (or
`clean@all`) removes them. `awk` and `gawk` are the ones installed on the system; the other
versions are pinned in `test/awk-variants.mk`, where each download is checked against its
SHA256.

The unit and integration tests are run by `test/run.py` (Python >= 3.8, standard library
only). Options can be passed with `RUNNER_FLAGS`, e.g., `make utest RUNNER_FLAGS='-v -k
parsing'` (`-v` shows the output of passing tests, `-k` selects tests by name). A single
integration test can also be run with its own target, e.g., `make test-docs-tags`.

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
- Declare the local variables of test functions in their signature (as in makefile-doc.awk):
  `make lint` fails if a test file defines other global variables than those of
  makefile-doc.awk and the harness (`check-test-variables`).

The results are printed in [TAP](https://testanything.org) format. A test file fails if a
check fails, if it stops before `done()` (e.g., because of an `exit` or a syntax error), or if
awk exits with a non-zero status.

## Integration tests

Each `test/integration/test-*` file (a recipe) runs `makefile-doc.awk` on a fixture
(`test/fixtures/Makefile.*`) and holds the expected output. The first line holds the awk
arguments (in shell syntax) and the remaining lines hold the expected output: stderr first,
then stdout, then `exit: N` if the exit status is not 0. Metadata lines starting with `#:`
come first and are ignored when running:

```
#: desc: what this test checks (the expected behavior)
#: issue: 123
-v COLOR_DEFAULT=0 -v SUB='...' test/fixtures/Makefile.sub
<expected output>
```

The output must match the expected output exactly, including blanks at the end of lines and
the final newline. Use `RUNNER_FLAGS=--update` to regenerate the expected output, e.g., `make
test-docs-tags RUNNER_FLAGS=--update` (check the diff by hand).

Conventions:

- A fixture covers one topic and stays small, so that a change affects few recipes. Add a
  new fixture rather than growing an unrelated one.
- A recipe is named after its fixture: `test-<topic>` or `test-<topic>-<case>` for
  `Makefile.<topic>` (e.g., `test-sub-L` uses `Makefile.sub`). Fixtures about targets start
  with `targets-`, about variables with `vars-`, and about docs with `docs-`.
- Every recipe has a `#: desc:` line, and an `#: issue:` line if it comes from an issue.
- Colors are turned off (`-v COLOR=0`) unless the recipe is about colors or output formats.
  The runner removes `NO_COLOR` from the environment of the tests.

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
