function test_utils_substitutions_main() {
  test_utils_substitutions_form_substitutions_1()
  test_utils_substitutions_form_substitutions_2()
  test_utils_substitutions_form_substitutions_3()
  test_utils_substitutions_extract_substitution_params()
}

function test_utils_substitutions_form_substitutions_1() {
  delete SUB_PARAMS
  delete SUB_LABELS
  delete SUB_VALUES
  SUB = "<L:1,M:0>NAME:LABEL:v1 v2;target:target_renamed:three items here"
  form_substitutions()
  assert(length(SUB_PARAMS) == 2 &&
         length(SUB_LABELS) == 2 &&
         length(SUB_VALUES) == 2 &&
         SUB_PARAMS["NAME"] == "L:1,M:0" &&
         SUB_LABELS["NAME"] == "LABEL" &&
         SUB_VALUES["NAME"] == "v1 v2" &&
         SUB_PARAMS["target"] == "" &&
         SUB_LABELS["target"] == "target_renamed" &&
         SUB_VALUES["target"] == "three items here",
         "test_utils_substitutions_form_substitutions_1")
}

function test_utils_substitutions_form_substitutions_2() {
  delete SUB_PARAMS
  delete SUB_LABELS
  delete SUB_VALUES
  SUB = "T1:;T2::;T3:V31 V32"
  form_substitutions()
  assert(length(SUB_PARAMS) == 3 &&
         length(SUB_LABELS) == 1 &&  # T1 has only values
         length(SUB_VALUES) == 3 &&
         SUB_PARAMS["T1"] == "" &&
         SUB_VALUES["T1"] == "" &&
         SUB_PARAMS["T2"] == "" &&
         SUB_LABELS["T2"] == "" &&
         SUB_VALUES["T2"] == "" &&
         SUB_PARAMS["T3"] == "" &&
         SUB_VALUES["T3"] == "V31 V32",
         "test_utils_substitutions_form_substitutions_2")
}

function test_utils_substitutions_form_substitutions_3(    stderr_content, stderr_content_lines) {
  delete SUB_PARAMS
  delete SUB_LABELS
  delete SUB_VALUES
  SUB = "T1"

  STDERR = "/tmp/.makefile-doc-stderr"
  form_substitutions() # this would send a warning to stderr

  stderr_content = unittest_consume_file(STDERR)
  split(stderr_content, stderr_content_lines, "\n")
  assert(length(SUB_PARAMS) == 1 &&
         length(SUB_LABELS) == 0 &&
         length(SUB_VALUES) == 0 &&
         SUB_PARAMS["T1"] == "" &&
         stderr_content_lines[1] == "WARNING: a minimal substitution is -v SUB='NAME:'",
         "test_utils_substitutions_form_substitutions_3")

  STDERR = "/dev/stderr"
}

function test_utils_substitutions_extract_substitution_params() {
  extract_substitution_params("L:0,M:0,N:3,S:\\,,P:--,I:{,T:}")
  assert(SUB_PARAMS_CURRENT["L"] == 0 &&
         SUB_PARAMS_CURRENT["M"] == 0 &&
         SUB_PARAMS_CURRENT["N"] == 3 &&
         SUB_PARAMS_CURRENT["S"] == "," &&
         SUB_PARAMS_CURRENT["P"] == "--" &&
         SUB_PARAMS_CURRENT["I"] == "{" &&
         SUB_PARAMS_CURRENT["T"] == "}",
         "1: test_utils_substitutions_extract_substitution_params")

  extract_substitution_params("")
  assert(SUB_PARAMS_CURRENT["L"] == 1 &&
         SUB_PARAMS_CURRENT["M"] == 1 &&
         SUB_PARAMS_CURRENT["N"] == -1 &&
         SUB_PARAMS_CURRENT["S"] == "" &&
         SUB_PARAMS_CURRENT["P"] == "" &&
         SUB_PARAMS_CURRENT["I"] == "" &&
         SUB_PARAMS_CURRENT["T"] == "",
         "2: test_utils_substitutions_extract_substitution_params")
}

BEGIN {
  UNITTEST_CURRENT_FILE = "test_utils_substitutions"

  SPACES_TABS_REGEX = "^[ \t]+|[ \t]+$"
  initialize_substitution_parameter_defaults()
  UNIT_TEST = UNIT_TEST == "" ? 1 : UNIT_TEST
  if (UNIT_TEST) {
    test_utils_substitutions_main()
  }
}
