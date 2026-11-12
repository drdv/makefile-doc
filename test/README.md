# Tests

- `make test`: integration tests (`test/integration/`)
- `make utest`: unit tests (`test/unit/`)
- `make bugs`: reproducers for known, unfixed bugs (`test/bugs/`)

Add `AWK=<variant>` to run with a specific awk, or use `test-all` / `utest-all` /
`bugs-all` for all of them.

The unit and integration tests are run by `test/run.py` (Python >= 3.8, standard library
only). Options can be passed with `RUNNER_FLAGS`, e.g., `make utest RUNNER_FLAGS='-v -k
parsing'` (`-v` shows the output of passing tests, `-k` selects tests by name). A single
integration test can also be run with its own target, e.g., `make test-default`.

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

The results are printed in [TAP](https://testanything.org) format. A test file fails if a
check fails, if it stops before `done()` (e.g., because of an `exit` or a syntax error), or if
awk exits with a non-zero status.

## Test file format

The first line holds the awk arguments (in shell syntax) and the remaining lines hold the
expected output: stderr first, then stdout, then `exit: N` if the exit status is not 0.
Optional metadata lines starting with `#:` may come first and are ignored when running:

```
#: desc: what this test checks
#: issue: 123
-v SUB='...' test/fixtures/Makefile.sub
<expected output>
```

The output must match the expected output exactly, including blanks at the end of lines and
the final newline. Fixtures are the `test/fixtures/Makefile.*` files. Use `UPDATE_RECIPE=1`
to regenerate the expected output of integration tests, e.g., `make test-default
UPDATE_RECIPE=1` (check the diff by hand).

## Reporting and fixing bugs

1. **Open an issue.** Every bug should have one.
2. **Reproducer (optional, can be a separate PR):** add `test/bugs/test-<name>` with `#:
   issue: N` and the *correct* expected output, written by hand. It is merged even if no
   fix exists yet.
3. **Fix:** the fix PR changes the code and moves the test from `test/bugs/` to
   `test/integration/`. `make bugs` fails when a bug test starts passing, so a forgotten
   move is caught.

For a unit test, the reproducer is a `check_bug(name, got, want, issue)` call next to the
other checks of the same function, with the *correct* `want`. It is reported as a known bug
while it fails, and `make utest` fails once it passes: the fix PR replaces `check_bug` with
`check`.

Every file in `test/bugs/` must have an `issue:` header, so the directory never becomes
an undocumented backlog. .
