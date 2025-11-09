# ------------------------------------------
# Unit test module
# ------------------------------------------
#
# How to use:
#
# Test files should put their tests in the BEGIN block, where the variable UNITTEST_CURRENT_FILE
# should be set. Then run
#
# awk -v UNIT_TEST=1 -f unittest.awk -f test1.awk [-f test2.awk ...] [-f your_library.awk ...] /dev/null
#
# It is recommended to pass your_library.awk last and to add if (UNIT_TEST) {exit 0} at
# the top of its BEGIN and END stanza

function assert_equal(result, expected, string)
{
  if (!(result == expected)) {
    printf("[%s] Assertion failed: %s\n  result: %s\n  expected: %s\n",
           UNITTEST_CURRENT_FILE,
           string,
           result,
           expected) > "/dev/stderr"
    UNITTEST_NUMB_TESTS_FAILED[UNITTEST_CURRENT_FILE]++
  }

  if (UNITTEST_VERBOSE) {
    printf("[%s] %s\n", UNITTEST_CURRENT_FILE, string)
  }

  unittest_register_results()
}

function assert(condition, string)
{
  if (!condition) {
    printf("[%s] Assertion failed: %s\n",
           UNITTEST_CURRENT_FILE,
           string) > "/dev/stderr"
    UNITTEST_NUMB_TESTS_FAILED[UNITTEST_CURRENT_FILE]++
  }

  if (UNITTEST_VERBOSE) {
    printf("[%s] %s\n", UNITTEST_CURRENT_FILE, string)
  }

  unittest_register_results()
}

function unittest_register_results() {
  if (!(UNITTEST_CURRENT_FILE in UNITTEST_NUMB_TESTS_RUN)) {
    _TEST_FILES[++UNITTEST_TEST_FILES_INDEX] = UNITTEST_CURRENT_FILE
    UNITTEST_NUMB_TESTS_RUN[UNITTEST_CURRENT_FILE] = 0 # to make the linter happy
  }
  UNITTEST_NUMB_TESTS_RUN[UNITTEST_CURRENT_FILE]++
}

function unittest_report_results(    max_filename_length, k, filename, n, m,
                                     total_numb_tests, total_numb_failed) {
  printf("===========================================\n")
  printf("Test results\n")
  printf("===========================================\n")
  max_filename_length = 0
  for (filename in UNITTEST_NUMB_TESTS_RUN) {
    n = length(filename)
    if (max_filename_length < n) {
      max_filename_length = n
    }
  }
  total_numb_tests = 0
  total_numb_failed = 0
  for (k=1; k<=UNITTEST_TEST_FILES_INDEX; k++) {
    filename = _TEST_FILES[k]
    n = UNITTEST_NUMB_TESTS_RUN[filename]
    m = (filename in UNITTEST_NUMB_TESTS_FAILED) ? UNITTEST_NUMB_TESTS_FAILED[filename] : 0
    printf("[%-" max_filename_length "s] passed %s tests out of %s\n",
           filename,
           n - m,
           n)
    total_numb_tests += n
    total_numb_failed += m
  }

  if (total_numb_failed == 0) {
    printf("All %s tests passed\n", total_numb_tests)
  } else {
    printf("Failed %s tests out of %s\n", total_numb_failed, total_numb_tests)
    exit 1
  }
}

function unittest_consume_file(file) {
  close(file)  # close file if open for writing
  file_content = ""
  while ((getline line < file) > 0) {
    file_content = file_content line "\n"
  }
  close(STDERR)  # close reared stream
  printf("") > STDERR
  close(file)  # close writer stream
  return file_content
}

BEGIN {
  split("", UNITTEST_NUMB_TESTS_RUN)
  split("", UNITTEST_NUMB_TESTS_FAILED)
  split("", _TEST_FILES)
  UNITTEST_TEST_FILES_INDEX = 0
}

END {
  UNIT_TEST = UNIT_TEST == "" ? 1 : UNIT_TEST
  if (UNIT_TEST) {
    unittest_report_results()
  }
}
