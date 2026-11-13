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
  form_substitutions("T1:;T2:L2:;T3:V31 V32", params, labels, values, names)
  check("form_substitutions: number of params", length_array_posix(params), 3)
  check("form_substitutions: number of labels", length_array_posix(labels), 1)
  check("form_substitutions: number of values", length_array_posix(values), 3)
  check_true("form_substitutions: NAME: has no label", !("T1" in labels))
  check("form_substitutions: NAME: has empty values", values["T1"], "")
  check("form_substitutions: NAME:LABEL: has a label", labels["T2"], "L2")
  check("form_substitutions: NAME:LABEL: has empty values", values["T2"], "")
  check("form_substitutions: NAME:VALUES", values["T3"], "V31 V32")
}

function test_form_substitutions_empty_items(    params, labels, values, names) {
  init_globals()
  form_substitutions(";T1:a; \t;T2:b;", params, labels, values, names)
  check("form_substitutions: empty items are skipped", length_array_posix(names), 2)
  check("form_substitutions: names stay in order", names[1] " " names[2], "T1 T2")
  check("form_substitutions: empty items are not errors", OPTION_ERRORS, 0)
}

function test_form_substitutions_invalid(    params, labels, values, names) {
  init_globals()
  form_substitutions("T1", params, labels, values, names)
  check("form_substitutions: name only is an error",
        stderr_text(),
        "ERROR: SUB: 'T1' should be NAME[:LABEL]:[VALUES]\n")
  check("form_substitutions: name only is not kept", length_array_posix(names), 0)

  form_substitutions("T1", params, labels, values, names, 1)
  check("form_substitutions (DSUB): name only is an error that names DSUB",
        stderr_text(),
        "ERROR: DSUB: 'T1' should be NAME:VALUES\n")

  form_substitutions(":v", params, labels, values, names)
  check("form_substitutions: empty name is an error",
        stderr_text(),
        "ERROR: SUB: ':v' has an empty NAME\n")

  form_substitutions("T2::v;T3:w", params, labels, values, names)
  check("form_substitutions: empty label is an error",
        stderr_text(),
        "ERROR: SUB: 'T2::v' has an empty LABEL\n")
  check("form_substitutions: the valid items are kept", names[1], "T3")
  check("form_substitutions: every invalid item is counted", OPTION_ERRORS, 4)
}

function test_parse_substitution_params(    params, keys, n) {
  n = parse_substitution_params(" L :0,S:\\,,P:x:y,,T:}", params, keys)
  check("parse_substitution_params: number of pairs (empty ones are skipped)", n, 4)
  check("parse_substitution_params: keys in order (blanks removed)",
        keys[1] keys[2] keys[3] keys[4], "LSPT")
  check("parse_substitution_params: value", params["L"], "0")
  check("parse_substitution_params: escaped comma", params["S"], ",")
  check("parse_substitution_params: only the first colon is a separator", params["P"], "x:y")
  check("parse_substitution_params: no parameters",
        parse_substitution_params("", params, keys), 0)
}

function test_validate_substitution_params() {
  init_globals()
  validate_substitution_params("t", "L:0,M:1,N:-1,S:x,P:y,I:{,T:}")
  validate_substitution_params("t", "N:12, L : 1 ")
  check("validate_substitution_params: valid parameters", stderr_text(), "")

  validate_substitution_params("t", "Z:1")
  check("validate_substitution_params: unknown parameter",
        stderr_text(),
        "ERROR: SUB: unknown parameter Z of t (use L, M, N, S, P, I or T)\n")
  validate_substitution_params("t", "L:2,M:")
  check("validate_substitution_params: L and M should be 0 or 1",
        stderr_text(),
        "ERROR: SUB: parameter L of t should be 0 or 1\n" \
        "ERROR: SUB: parameter M of t should be 0 or 1\n")
  validate_substitution_params("t", "N:-2")
  validate_substitution_params("t", "N:1.5")
  check("validate_substitution_params: N should be -1 or a non-negative integer",
        stderr_text(),
        "ERROR: SUB: parameter N of t should be -1 or a non-negative integer\n" \
        "ERROR: SUB: parameter N of t should be -1 or a non-negative integer\n")
  check("validate_substitution_params: every error is counted", OPTION_ERRORS, 5)
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
  test_form_substitutions_empty_items()
  test_form_substitutions_invalid()
  test_parse_substitution_params()
  test_validate_substitution_params()
  test_extract_substitution_params()
  test_form_substitutions_colons()
  test_form_substitutions_spaces_in_name()
  test_form_substitutions_dsub()
  done()
}
