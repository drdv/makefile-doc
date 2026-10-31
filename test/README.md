# Tests

- `make test`: integration tests (`test/integration/`)
- `make utest`: unit tests (`test/unit/`)
- `make bugs`: reproducers for known, unfixed bugs (`test/bugs/`)

Add `AWK=<variant>` to run with a specific awk, or use `test-all` / `bugs-all`
for all of them.

## Test file format

The first line holds the awk arguments and the remaining lines hold the expected
output (stderr first, then stdout). Optional metadata lines starting with `#:`
may come first and are ignored when running:

```
#: desc: what this test checks
#: issue: 123
-v SUB='...' test/fixtures/Makefile.sub
<expected output>
```

Fixtures are the `test/fixtures/Makefile.*` files. Use `UPDATE_RECIPE=1` to regenerate the
expected output of an integration test (check the diff by hand).

## Reporting and fixing bugs

1. **Open an issue.** Every bug should have one.
2. **Reproducer (optional, can be a separate PR):** add `test/bugs/test-<name>` with `#:
   issue: N` and the *correct* expected output, written by hand. It is merged even if no
   fix exists yet.
3. **Fix:** the fix PR changes the code and moves the test from `test/bugs/` to
   `test/integration/`. `make bugs` fails when a bug test starts passing, so a forgotten
   move is caught.

Every file in `test/bugs/` must have an `issue:` header, so the directory never becomes
an undocumented backlog. .
