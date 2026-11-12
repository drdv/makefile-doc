# Unit test harness for makefile-doc.awk
#
# A test file calls check()/check_true() for each check and done() at the end of its BEGIN
# block. The results are printed in TAP format (https://testanything.org):
#
#   ok 1 - name of a passing check
#   not ok 2 - name of a failing check
#   #   got:  "..."
#   #   want: "..."
#   1..2
#
# Test files are run by test/run.py, one awk process per file:
#
#   awk -v UNIT_TEST=1 -v STDERR=<tmpfile> \
#       -f test/unit/harness.awk -f makefile-doc.awk -f test/unit/test_x.awk /dev/null
#
# makefile-doc.awk calls init_globals() in its BEGIN block (before the tests run). Tests that
# modify the global state can call init_globals() again to reset it.

# make control characters visible in the diagnostics (no gsub: the meaning of backslashes
# in the replacement string differs between awk implementations)
function harness_escape(string,    k, c, out) {
  out = ""
  for (k = 1; k <= length(string); k++) {
    c = substr(string, k, 1)
    if (c == "\\") { c = "\\\\" }
    else if (c == "\n") { c = "\\n" }
    else if (c == "\t") { c = "\\t" }
    else if (c == "\033") { c = "\\033" }
    out = out c
  }
  return out
}

function harness_result(name, passed) {
  HARNESS_N++
  if (passed) {
    printf("ok %d - %s\n", HARNESS_N, name)
  } else {
    HARNESS_FAILED++
    printf("not ok %d - %s\n", HARNESS_N, name)
  }
}

# check that got == want
function check(name, got, want) {
  harness_result(name, got == want)
  if (!(got == want)) {
    printf("#   got:  \"%s\"\n", harness_escape(got))
    printf("#   want: \"%s\"\n", harness_escape(want))
  }
}

# check that a condition is true
function check_true(name, condition) {
  harness_result(name, condition)
}

# Return what the code under test has written to STDERR since the last call, and empty the
# file. STDERR must be a regular file (test/run.py passes one with -v STDERR=...).
function stderr_text(    line, text) {
  if (STDERR == "/dev/stderr") {
    printf("Bail out! STDERR is not a file (run the tests with test/run.py)\n")
    exit 2
  }
  close(STDERR) # flush the stream used for writing
  text = ""
  while ((getline line < STDERR) > 0) {
    text = text line "\n"
  }
  close(STDERR) # close the stream used for reading
  printf("") > STDERR # truncate
  close(STDERR)
  return text
}

# print the TAP plan and set the exit status
function done() {
  printf("1..%d\n", HARNESS_N)
  exit (HARNESS_FAILED > 0 ? 1 : 0)
}

BEGIN {
  HARNESS_N = 0
  HARNESS_FAILED = 0
}
