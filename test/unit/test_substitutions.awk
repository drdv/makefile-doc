function test_form_substitutions_with_labels(    params, labels, values, names) {
  form_substitutions("<L:1,M:0>NAME:LABEL:v1 v2;target:target_renamed:three items here",
                     params, labels, values, names)
  check("form_substitutions: number of params", length_array_posix(params), 2)
  check("form_substitutions: number of labels", length_array_posix(labels), 2)
  check("form_substitutions: number of values", length_array_posix(values), 2)
  check("form_substitutions: params", params["NAME"], "L:1,M:0")
  check("form_substitutions: label", labels["NAME"], "LABEL")
  check("form_substitutions: values", values["NAME"], "v1 v2")
  check("form_substitutions: no params", params["target"], "")
  check("form_substitutions: label (2nd substitution)", labels["target"], "target_renamed")
  check("form_substitutions: values (2nd substitution)", values["target"], "three items here")
  check("form_substitutions: names in order", names[1] " " names[2], "NAME target")
}

function test_form_substitutions_empty_parts(    params, labels, values, names) {
  form_substitutions("T1:;T2::;T3:V31 V32", params, labels, values, names)
  check("form_substitutions: number of params", length_array_posix(params), 3)
  check("form_substitutions: number of labels", length_array_posix(labels), 1)
  check("form_substitutions: number of values", length_array_posix(values), 3)
  check_true("form_substitutions: NAME: has no label", !("T1" in labels))
  check("form_substitutions: NAME: has empty values", values["T1"], "")
  check("form_substitutions: NAME:: has an empty label", labels["T2"], "")
  check("form_substitutions: NAME:: has empty values", values["T2"], "")
  check("form_substitutions: NAME:VALUES", values["T3"], "V31 V32")
}

function test_form_substitutions_name_only(    params, labels, values, names) {
  form_substitutions("T1", params, labels, values, names)
  check("form_substitutions: name only gives a warning",
        stderr_text(),
        "WARNING: a minimal substitution is -v SUB='NAME:'\n")
  check("form_substitutions: name only has params", length_array_posix(params), 1)
  check("form_substitutions: name only has no labels", length_array_posix(labels), 0)
  check("form_substitutions: name only has no values", length_array_posix(values), 0)
}

function test_extract_substitution_params() {
  extract_substitution_params("L:0,M:0,N:3,S:\\,,P:--,I:{,T:}")
  check("extract_substitution_params: L", SUB_PARAMS_CURRENT["L"], 0)
  check("extract_substitution_params: M", SUB_PARAMS_CURRENT["M"], 0)
  check("extract_substitution_params: N", SUB_PARAMS_CURRENT["N"], 3)
  check("extract_substitution_params: S is an escaped comma", SUB_PARAMS_CURRENT["S"], ",")
  check("extract_substitution_params: P", SUB_PARAMS_CURRENT["P"], "--")
  check("extract_substitution_params: I", SUB_PARAMS_CURRENT["I"], "{")
  check("extract_substitution_params: T", SUB_PARAMS_CURRENT["T"], "}")

  extract_substitution_params("")
  check("extract_substitution_params: default L", SUB_PARAMS_CURRENT["L"], 1)
  check("extract_substitution_params: default M", SUB_PARAMS_CURRENT["M"], 1)
  check("extract_substitution_params: default N", SUB_PARAMS_CURRENT["N"], -1)
  check("extract_substitution_params: default S", SUB_PARAMS_CURRENT["S"], "")
  check("extract_substitution_params: default P", SUB_PARAMS_CURRENT["P"], "")
  check("extract_substitution_params: default I", SUB_PARAMS_CURRENT["I"], "")
  check("extract_substitution_params: default T", SUB_PARAMS_CURRENT["T"], "")
}

function test_form_substitutions_colons(    params, labels, values, names) {
  form_substitutions("t:t:/a:b;u:/a:b", params, labels, values, names)
  check("form_substitutions: value with colons after a label", values["t"], "/a:b")
  check("form_substitutions: without a label, the 2nd colon ends the label", labels["u"], "/a")
  check("form_substitutions: without a label, the rest is the value", values["u"], "b")
}

function test_form_substitutions_spaces_in_name(    params, labels, values, names) {
  form_substitutions(" \tt :v", params, labels, values, names)
  check("form_substitutions: spaces around the name are removed", names[1], "t")
  check("form_substitutions: value of a name with spaces", values["t"], "v")
}

function test_form_substitutions_dsub(    params, labels, values, names) {
  form_substitutions("$(X):a:b;$(Y):;$(X):c", params, labels, values, names, 1)
  check("form_substitutions (DSUB): no labels", length_array_posix(labels), 0)
  check("form_substitutions (DSUB): the value is everything after the 1st colon",
        values["$(Y)"], "")
  check("form_substitutions (DSUB): the last value of a repeated name is used",
        values["$(X)"], "c")
  check("form_substitutions (DSUB): names in the order given (repeats kept)",
        names[1] " " names[2] " " names[3], "$(X) $(Y) $(X)")

  form_substitutions("$(X):a:b", params, labels, values, names, 1)
  check("form_substitutions (DSUB): value with colons", values["$(X)"], "a:b")
}

BEGIN {
  test_form_substitutions_with_labels()
  test_form_substitutions_empty_parts()
  test_form_substitutions_name_only()
  test_extract_substitution_params()
  test_form_substitutions_colons()
  test_form_substitutions_spaces_in_name()
  test_form_substitutions_dsub()
  done()
}
