function test_form_substitutions_with_labels(    params, labels, values, names) {
  form_substitutions("<L:1,M:0>NAME:LABEL:v1 v2;target:target_renamed:three items here",
                     params, labels, values, names, 0)
  check("form_substitutions: number of labels", length_array_posix(labels), 2)
  check("form_substitutions: number of values", length_array_posix(values), 2)
  check("form_substitutions: params", params["NAME", "L"] " " params["NAME", "M"], "1 0")
  check("form_substitutions: label", labels["NAME"], "LABEL")
  check("form_substitutions: values", values["NAME"], "v1 v2")
  check("form_substitutions: no params (the defaults)",
        params["target", "L"] " " params["target", "M"] " " params["target", "N"], "1 1 -1")
  check("form_substitutions: label (2nd substitution)", labels["target"], "target_renamed")
  check("form_substitutions: values (2nd substitution)", values["target"], "three items here")
  check("form_substitutions: names in order", names[1] " " names[2], "NAME target")
}

function test_form_substitutions_semicolon(    params, labels, values, names) {
  form_substitutions("$(S):cd b\\; cmake ..;T:x", params, labels, values, names, 1)
  check("form_substitutions: an escaped ; is part of the value", values["$(S)"], "cd b; cmake ..")
  check("form_substitutions: an unescaped ; separates items", names[1] " " names[2], "$(S) T")
}

function test_form_substitutions_empty_parts(    params, labels, values, names) {
  form_substitutions("T1:;T2:L2:;T3:V31 V32", params, labels, values, names, 0)
  check_true("form_substitutions: a row of params for each substitution",
             ("T1", "L") in params && ("T2", "L") in params && ("T3", "L") in params)
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
  form_substitutions(";T1:a; \t;T2:b;", params, labels, values, names, 0)
  check("form_substitutions: empty items are skipped", length_array_posix(names), 2)
  check("form_substitutions: names stay in order", names[1] " " names[2], "T1 T2")
  check("form_substitutions: empty items are not errors", OPTION_ERRORS, 0)
}

function test_form_substitutions_invalid(    params, labels, values, names) {
  init_globals()
  form_substitutions("T1", params, labels, values, names, 0)
  check("form_substitutions: name only is an error",
        stderr_text(),
        "ERROR: SUB: 'T1' should be NAME:[[LABEL]:][VALUES]\n")
  check("form_substitutions: name only is not kept", length_array_posix(names), 0)

  form_substitutions("T1", params, labels, values, names, 1)
  check("form_substitutions (DSUB): name only is an error that names DSUB",
        stderr_text(),
        "ERROR: DSUB: 'T1' should be NAME:VALUE\n")

  form_substitutions(":v", params, labels, values, names, 0)
  check("form_substitutions: empty name is an error",
        stderr_text(),
        "ERROR: SUB: ':v' has an empty NAME\n")

  form_substitutions(":v;T3:w", params, labels, values, names, 0)
  stderr_text()
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

function test_store_sub_params(    params) {
  init_globals()
  set_sub_param_defaults(params)
  store_sub_params(params, "t", "L:0,M:1,N:-1,S:x,P:y,I:{,T:}")
  store_sub_params(params, "t", "N:12, L : 1 ")
  check("store_sub_params: valid parameters", stderr_text(), "")

  store_sub_params(params, "t", "Z:1")
  check("store_sub_params: unknown parameter",
        stderr_text(),
        "ERROR: SUB: unknown parameter Z of t (use L, M, N, S, P, I or T)\n")
  store_sub_params(params, "t", "L:2,M:")
  check("store_sub_params: L and M should be 0 or 1",
        stderr_text(),
        "ERROR: SUB: parameter L of t should be 0 or 1\n" \
        "ERROR: SUB: parameter M of t should be 0 or 1\n")
  check("store_sub_params: an invalid parameter keeps its default", params["t", "L"], 1)
  store_sub_params(params, "t", "N:-2")
  store_sub_params(params, "t", "N:1.5")
  check("store_sub_params: N should be -1 or a non-negative integer",
        stderr_text(),
        "ERROR: SUB: parameter N of t should be -1 or a non-negative integer\n" \
        "ERROR: SUB: parameter N of t should be -1 or a non-negative integer\n")
  store_sub_params(params, "t", "L:0,M:1,L:1")
  check("store_sub_params: a repeated parameter",
        stderr_text(),
        "ERROR: SUB: parameter L of t is given more than once\n")
  check("store_sub_params: every error is counted", OPTION_ERRORS, 6)
}

function test_store_sub_params_values(    params) {
  set_sub_param_defaults(params)
  store_sub_params(params, "t", "L:0,M:0,N:3,S:\\,,P:--,I:{,T:}")
  check("store_sub_params: L", params["t", "L"], 0)
  check("store_sub_params: M", params["t", "M"], 0)
  check("store_sub_params: N", params["t", "N"], 3)
  check("store_sub_params: S is an escaped comma", params["t", "S"], ",")
  check("store_sub_params: P", params["t", "P"], "--")
  check("store_sub_params: I", params["t", "I"], "{")
  check("store_sub_params: T", params["t", "T"], "}")
  check_true("store_sub_params: L, M and N are numbers (a string \"0\" would be true)",
             !params["t", "L"] && !params["t", "M"])

  store_sub_params(params, "u", "")
  check("store_sub_params: default L", params["u", "L"], 1)
  check("store_sub_params: default M", params["u", "M"], 1)
  check("store_sub_params: default N", params["u", "N"], -1)
  check("store_sub_params: default S", params["u", "S"], "")
  check("store_sub_params: default P", params["u", "P"], "")
  check("store_sub_params: default I", params["u", "I"], "")
  check("store_sub_params: default T", params["u", "T"], "")
  check("store_sub_params: the defaults are unchanged", params["", "L"] params["", "N"], "1-1")
}

function test_form_substitutions_colons(    params, labels, values, names) {
  init_globals()
  form_substitutions("t:t:/a:b;u:/a:b;v::/a:b;w::", params, labels, values, names, 0)
  check("form_substitutions: value with colons after a label", values["t"], "/a:b")
  check_true("form_substitutions: an empty label is no label", !("v" in labels))
  check("form_substitutions: value with colons after an empty label", values["v"], "/a:b")
  check_true("form_substitutions: NAME:: has no label", !("w" in labels))
  check("form_substitutions: NAME:: has empty values", values["w"], "")
  check("form_substitutions: an empty label is not an error", OPTION_ERRORS, 0)
  check("form_substitutions: without a label, the 2nd colon ends the label", labels["u"], "/a")
  check("form_substitutions: without a label, the rest is the value", values["u"], "b")
}

function test_form_substitutions_spaces_in_name(    params, labels, values, names) {
  form_substitutions(" \tt :v", params, labels, values, names, 0)
  check("form_substitutions: spaces around the name are removed", names[1], "t")
  check("form_substitutions: value of a name with spaces", values["t"], "v")

  form_substitutions("t: \tnew :v;u: :w", params, labels, values, names, 0)
  check("form_substitutions: spaces around the label are removed", labels["t"], "new")
  check_true("form_substitutions: a blank label is no label", !("u" in labels))
  check("form_substitutions: value after a blank label", values["u"], "w")
}

function test_form_substitutions_dsub(    params, labels, values, names) {
  form_substitutions("$(X):a:b;$(Y):;$(Z):c", params, labels, values, names, 1)
  check("form_substitutions (DSUB): no labels", length_array_posix(labels), 0)
  check("form_substitutions (DSUB): the value is everything after the 1st colon",
        values["$(Y)"], "")
  check("form_substitutions (DSUB): names in the order given",
        names[1] " " names[2] " " names[3], "$(X) $(Y) $(Z)")

  form_substitutions("<A:1>$(X):a:b", params, labels, values, names, 1)
  check("form_substitutions (DSUB): parameters", params["$(X)", "A"] " " params["$(X)", "D"],
        "1 1")
  check("form_substitutions (DSUB): value with colons", values["$(X)"], "a:b")
}

function test_form_substitutions_name_with_angle_brackets(    params, labels, values, names) {
  init_globals()
  form_substitutions("<><t>:new:v;<L:0><u>:w", params, labels, values, names, 0)
  check("form_substitutions: empty parameters before a NAME that starts with <...>",
        names[1] " " labels["<t>"] " " values["<t>"], "<t> new v")
  check("form_substitutions: parameters before a NAME that starts with <...>",
        names[2] " " params["<u>", "L"] " " values["<u>"], "<u> 0 w")

  form_substitutions("<><b>:B;<A:1, D:0><i>:I", params, labels, values, names, 1)
  check("form_substitutions (DSUB): empty parameters before a NAME that starts with <...>",
        names[1] " " values["<b>"], "<b> B")
  check("form_substitutions (DSUB): parameters before a NAME that starts with <...>",
        names[2] " " params["<i>", "A"] params["<i>", "D"] " " values["<i>"], "<i> 10 I")
  check("form_substitutions: a NAME that starts with <...> is not an error", OPTION_ERRORS, 0)
}

function test_form_substitutions_repeated(    params, labels, values, names) {
  init_globals()
  form_substitutions("t:a;u:b;t:c;t:a", params, labels, values, names, 0)
  check("form_substitutions: a repeated name is an error (also an identical repeat)",
        stderr_text(),
        "ERROR: SUB: 't' is given more than once\n" \
        "ERROR: SUB: 't' is given more than once\n")
  check("form_substitutions: every repeat is counted", OPTION_ERRORS, 2)

  form_substitutions("$(X):a;$(X):b", params, labels, values, names, 1)
  check("form_substitutions (DSUB): a repeated name is an error",
        stderr_text(),
        "ERROR: DSUB: '$(X)' is given more than once\n")

  init_globals()
  form_substitutions("t:a", params, labels, values, names, 0)
  form_substitutions("t:b", params, labels, values, names, 1)
  check("form_substitutions: the same name in SUB and DSUB is not an error", OPTION_ERRORS, 0)
}

function test_store_dsub_params(    params) {
  init_globals()
  set_dsub_param_defaults(params)
  store_dsub_params(params, "x", "")
  store_dsub_params(params, "x", "A:1")
  store_dsub_params(params, "x", " A : 1 , D:0,")
  check("store_dsub_params: valid parameters are not errors", OPTION_ERRORS, 0)

  store_dsub_params(params, "x", "L:0")
  check("store_dsub_params: unknown parameter",
        stderr_text(), "ERROR: DSUB: unknown parameter L of x (use A or D)\n")
  store_dsub_params(params, "x", "A:yes")
  check("store_dsub_params: A should be 0 or 1",
        stderr_text(), "ERROR: DSUB: parameter A of x should be 0 or 1\n")
  store_dsub_params(params, "x", "D:0")
  check("store_dsub_params: replaced nowhere",
        stderr_text(), "ERROR: DSUB: x is replaced nowhere (A and D are both 0)\n")
  store_dsub_params(params, "x", "A:1, A :1")
  check("store_dsub_params: a repeated parameter",
        stderr_text(), "ERROR: DSUB: parameter A of x is given more than once\n")
  check("store_dsub_params: every invalid parameter is counted", OPTION_ERRORS, 4)
  init_globals()
}

function test_form_substitutions_dsub_params(    labels) {
  form_substitutions("<A:1>b:2;<A:1,D:0>c:3;d:6",
                     DSUB_PARAM, labels, DSUB_VALUES, DSUB_NAMES, 1)
  check("form_substitutions (DSUB): default A and D",
        DSUB_PARAM["d", "A"] " " DSUB_PARAM["d", "D"], "0 1")
  check("form_substitutions (DSUB): A:1", DSUB_PARAM["b", "A"] " " DSUB_PARAM["b", "D"], "1 1")
  check("form_substitutions (DSUB): A:1,D:0",
        DSUB_PARAM["c", "A"] " " DSUB_PARAM["c", "D"], "1 0")
  init_globals()
}

function test_display_name(    labels) {
  form_substitutions("<A:1>$(D):out;<A:1>out/:o/;/a:/X", DSUB_PARAM, labels, DSUB_VALUES,
                     DSUB_NAMES, 1)
  DSUB_COUNT = length_array_posix(DSUB_NAMES)
  check("display_name: replaced in the order given", display_name("$(D)/a"), "o/a")
  check("display_name: every occurrence", display_name("$(D)/a $(D)/b"), "o/a o/b")
  check("display_name: a name without the text", display_name("plain"), "plain")
  SUB_LABELS["$(D)/a"] = "label"
  check("display_name: a SUB label wins", display_name("$(D)/a"), "label")
  init_globals()
}

BEGIN {
  test_form_substitutions_with_labels()
  test_form_substitutions_empty_parts()
  test_form_substitutions_semicolon()
  test_form_substitutions_empty_items()
  test_form_substitutions_invalid()
  test_parse_substitution_params()
  test_store_sub_params()
  test_store_sub_params_values()
  test_form_substitutions_colons()
  test_form_substitutions_spaces_in_name()
  test_form_substitutions_dsub()
  test_form_substitutions_name_with_angle_brackets()
  test_form_substitutions_repeated()
  test_store_dsub_params()
  test_form_substitutions_dsub_params()
  test_display_name()
  done()
}
