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
  form_substitutions(SUB, SUB_PARAMS, SUB_LABELS, SUB_VALUES)
  check_true("test_utils_substitutions_form_substitutions_1",
             length(SUB_PARAMS) == 2 &&
             length(SUB_LABELS) == 2 &&
             length(SUB_VALUES) == 2 &&
             SUB_PARAMS["NAME"] == "L:1,M:0" &&
             SUB_LABELS["NAME"] == "LABEL" &&
             SUB_VALUES["NAME"] == "v1 v2" &&
             SUB_PARAMS["target"] == "" &&
             SUB_LABELS["target"] == "target_renamed" &&
             SUB_VALUES["target"] == "three items here")
}

function test_utils_substitutions_form_substitutions_2() {
  delete SUB_PARAMS
  delete SUB_LABELS
  delete SUB_VALUES
  SUB = "T1:;T2::;T3:V31 V32"
  form_substitutions(SUB, SUB_PARAMS, SUB_LABELS, SUB_VALUES)
  check_true("test_utils_substitutions_form_substitutions_2",
             length(SUB_PARAMS) == 3 &&
             length(SUB_LABELS) == 1 &&  # T1 has only values
             length(SUB_VALUES) == 3 &&
             SUB_PARAMS["T1"] == "" &&
             SUB_VALUES["T1"] == "" &&
             SUB_PARAMS["T2"] == "" &&
             SUB_LABELS["T2"] == "" &&
             SUB_VALUES["T2"] == "" &&
             SUB_PARAMS["T3"] == "" &&
             SUB_VALUES["T3"] == "V31 V32")
}

function test_utils_substitutions_form_substitutions_3(    stderr_content, stderr_content_lines) {
  delete SUB_PARAMS
  delete SUB_LABELS
  delete SUB_VALUES
  SUB = "T1"

  form_substitutions(SUB, SUB_PARAMS, SUB_LABELS, SUB_VALUES) # sends a warning to stderr

  stderr_content = stderr_text()
  split(stderr_content, stderr_content_lines, "\n")
  check_true("test_utils_substitutions_form_substitutions_3",
             length(SUB_PARAMS) == 1 &&
             length(SUB_LABELS) == 0 &&
             length(SUB_VALUES) == 0 &&
             SUB_PARAMS["T1"] == "" &&
             stderr_content_lines[1] == "WARNING: a minimal substitution is -v SUB='NAME:'")
}

function test_utils_substitutions_extract_substitution_params() {
  extract_substitution_params("L:0,M:0,N:3,S:\\,,P:--,I:{,T:}")
  check_true("1: test_utils_substitutions_extract_substitution_params",
             SUB_PARAMS_CURRENT["L"] == 0 &&
             SUB_PARAMS_CURRENT["M"] == 0 &&
             SUB_PARAMS_CURRENT["N"] == 3 &&
             SUB_PARAMS_CURRENT["S"] == "," &&
             SUB_PARAMS_CURRENT["P"] == "--" &&
             SUB_PARAMS_CURRENT["I"] == "{" &&
             SUB_PARAMS_CURRENT["T"] == "}")

  extract_substitution_params("")
  check_true("2: test_utils_substitutions_extract_substitution_params",
             SUB_PARAMS_CURRENT["L"] == 1 &&
             SUB_PARAMS_CURRENT["M"] == 1 &&
             SUB_PARAMS_CURRENT["N"] == -1 &&
             SUB_PARAMS_CURRENT["S"] == "" &&
             SUB_PARAMS_CURRENT["P"] == "" &&
             SUB_PARAMS_CURRENT["I"] == "" &&
             SUB_PARAMS_CURRENT["T"] == "")
}

BEGIN {
  test_utils_substitutions_main()
  done()
}
