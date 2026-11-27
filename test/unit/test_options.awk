# Check the section Options of the script: opt_process (the defaults of the options, and
# the report of the invalid ones, without exiting: BEGIN exits when opt_process returns a
# number other than 0), and SUB and DSUB (opt_form_substitutions and their parameters).

# as if no option was given with -v
function clear_options() {
  OUTPUT_FORMAT = VARS = PADDING = DEPRECATED = OFFSET = COLOR = RECIPEPREFIX = ""
  SUB = DSUB = EXPORT_THEME = ""
  COLOR_DEFAULT = COLOR_ATTENTION = COLOR_DEPRECATED = COLOR_SECTION = COLOR_BACKTICKS = ""
}

function test_process_options_defaults() {
  init_globals()
  clear_options()
  check("opt_process: no option, no invalid option", opt_process(), 0)
  check("opt_process: the defaults",
        OUTPUT_FORMAT " " VARS " " DEPRECATED " " OFFSET " [" PADDING "]", "ANSI 1 1 3 [ ]")
  check("opt_process: the default recipe prefix is a tab", RECIPEPREFIX, "\t")
  clear_options()
  init_globals()
}

function test_process_options_errors() {
  init_globals()
  clear_options()
  OUTPUT_FORMAT = "pdf"
  VARS = 2
  PADDING = "ab"
  OFFSET = -1
  check("opt_process: returns the number of invalid options", opt_process(), 4)
  check("opt_process: reports every invalid option",
        stderr_text(),
        "makefile-doc: error: OUTPUT_FORMAT should be ANSI, HTML or LATEX\n" \
        "makefile-doc: error: VARS should be 0 or 1\n" \
        "makefile-doc: error: PADDING should have length 1\n" \
        "makefile-doc: error: OFFSET should be a non-negative integer\n")
  check("opt_process: does not stop the script (BEGIN does)", ABORT, 0)
  clear_options()
  init_globals()
}

function test_form_substitutions_with_labels(params, labels, values, names) { #locals
  opt_form_substitutions("<L:1,M:0>NAME:LABEL:v1 v2;target:target_renamed:three items here", 0,
                         params, labels, values, names)
  check("opt_form_substitutions: number of labels", array_length(labels), 2)
  check("opt_form_substitutions: number of values", array_length(values), 2)
  check("opt_form_substitutions: params", params["NAME", "L"] " " params["NAME", "M"], "1 0")
  check("opt_form_substitutions: label", labels["NAME"], "LABEL")
  check("opt_form_substitutions: values", values["NAME"], "v1 v2")
  check("opt_form_substitutions: no params (the defaults)",
        params["target", "L"] " " params["target", "M"] " " params["target", "N"], "1 1 -1")
  check("opt_form_substitutions: label (2nd substitution)", labels["target"], "target_renamed")
  check("opt_form_substitutions: values (2nd substitution)", values["target"], "three items here")
  check("opt_form_substitutions: names in order", names[1] " " names[2], "NAME target")
}

function test_form_substitutions_semicolon(params, labels, values, names) { #locals
  opt_form_substitutions("$(S):cd b\\; cmake ..;T:x", 1, params, labels, values, names)
  check("opt_form_substitutions: an escaped ; is part of the value", values["$(S)"],
        "cd b; cmake ..")
  check("opt_form_substitutions: an unescaped ; separates items", names[1] " " names[2], "$(S) T")
}

function test_form_substitutions_empty_parts(params, labels, values, names) { #locals
  opt_form_substitutions("T1:;T2:L2:;T3:V31 V32", 0, params, labels, values, names)
  check_true("opt_form_substitutions: a row of params for each substitution",
             ("T1", "L") in params && ("T2", "L") in params && ("T3", "L") in params)
  check("opt_form_substitutions: number of labels", array_length(labels), 1)
  check("opt_form_substitutions: number of values", array_length(values), 3)
  check_true("opt_form_substitutions: NAME: has no label", !("T1" in labels))
  check("opt_form_substitutions: NAME: has empty values", values["T1"], "")
  check("opt_form_substitutions: NAME:LABEL: has a label", labels["T2"], "L2")
  check("opt_form_substitutions: NAME:LABEL: has empty values", values["T2"], "")
  check("opt_form_substitutions: NAME:VALUES", values["T3"], "V31 V32")
}

function test_form_substitutions_empty_items(params, labels, values, names) { #locals
  init_globals()
  opt_form_substitutions(";T1:a; \t;T2:b;", 0, params, labels, values, names)
  check("opt_form_substitutions: empty items are skipped", array_length(names), 2)
  check("opt_form_substitutions: names stay in order", names[1] " " names[2], "T1 T2")
  check("opt_form_substitutions: empty items are not errors", OPTION_ERRORS, 0)
}

function test_form_substitutions_invalid(params, labels, values, names) { #locals
  init_globals()
  opt_form_substitutions("T1", 0, params, labels, values, names)
  check("opt_form_substitutions: name only is an error",
        stderr_text(),
        "makefile-doc: error: SUB: 'T1' should be NAME:[[LABEL]:][VALUES]\n")
  check("opt_form_substitutions: name only is not kept", array_length(names), 0)

  opt_form_substitutions("T1", 1, params, labels, values, names)
  check("opt_form_substitutions (DSUB): name only is an error that names DSUB",
        stderr_text(),
        "makefile-doc: error: DSUB: 'T1' should be NAME:VALUE\n")

  opt_form_substitutions(":v", 0, params, labels, values, names)
  check("opt_form_substitutions: empty name is an error",
        stderr_text(),
        "makefile-doc: error: SUB: ':v' has an empty NAME\n")

  opt_form_substitutions(":v;T3:w", 0, params, labels, values, names)
  stderr_text()
  check("opt_form_substitutions: the valid items are kept", names[1], "T3")
  check("opt_form_substitutions: every invalid item is counted", OPTION_ERRORS, 4)
}

function test_opt_parse_substitution_params(params, keys, n) { #locals
  n = opt_parse_substitution_params(" L :0,S:\\,,P:x:y,,T:}", params, keys)
  check("opt_parse_substitution_params: number of pairs (empty ones are skipped)", n, 4)
  check("opt_parse_substitution_params: keys in order (blanks removed)",
        keys[1] keys[2] keys[3] keys[4], "LSPT")
  check("opt_parse_substitution_params: value", params["L"], "0")
  check("opt_parse_substitution_params: escaped comma", params["S"], ",")
  check("opt_parse_substitution_params: only the first colon is a separator", params["P"], "x:y")
  check("opt_parse_substitution_params: no parameters",
        opt_parse_substitution_params("", params, keys), 0)
}

function test_opt_checked_params(table, params, keys, n) { #locals
  init_globals()
  set_dsub_param_defaults(table)
  n = opt_checked_params("DSUB", "A D", "x", "D:0,Z:1,D:1,A:1", table, params, keys)
  check("opt_checked_params: the keys that are neither repeated nor unknown, in order",
        n " " keys[1] keys[2], "2 DA")
  check("opt_checked_params: their values", params["A"], "1")
  check("opt_checked_params: the row starts with the defaults", table["x", "A"] table["x", "D"],
        "01")
  check("opt_checked_params: unknown and repeated parameters are reported",
        stderr_text(),
        "makefile-doc: error: DSUB: unknown parameter Z of x (use A or D)\n" \
        "makefile-doc: error: DSUB: parameter D of x is given more than once\n")
  init_globals()
}

function test_opt_store_sub_params(params) { #locals
  init_globals()
  set_sub_param_defaults(params)
  opt_store_sub_params("t", "L:0,M:1,N:-1,S:x,P:y,I:{,T:}", params)
  opt_store_sub_params("t", "N:12, L : 1 ", params)
  check("opt_store_sub_params: valid parameters", stderr_text(), "")

  opt_store_sub_params("t", "Z:1", params)
  check("opt_store_sub_params: unknown parameter",
        stderr_text(),
        "makefile-doc: error: SUB: unknown parameter Z of t (use L, M, N, S, P, I or T)\n")
  opt_store_sub_params("t", "L:2,M:", params)
  check("opt_store_sub_params: L and M should be 0 or 1",
        stderr_text(),
        "makefile-doc: error: SUB: parameter L of t should be 0 or 1\n" \
        "makefile-doc: error: SUB: parameter M of t should be 0 or 1\n")
  check("opt_store_sub_params: an invalid parameter keeps its default", params["t", "L"], 1)
  opt_store_sub_params("t", "N:-2", params)
  opt_store_sub_params("t", "N:1.5", params)
  check("opt_store_sub_params: N should be -1 or a non-negative integer",
        stderr_text(),
        "makefile-doc: error: SUB: parameter N of t should be -1 or a non-negative integer\n" \
        "makefile-doc: error: SUB: parameter N of t should be -1 or a non-negative integer\n")
  opt_store_sub_params("t", "L:0,M:1,L:1", params)
  check("opt_store_sub_params: a repeated parameter",
        stderr_text(),
        "makefile-doc: error: SUB: parameter L of t is given more than once\n")
  check("opt_store_sub_params: every error is counted", OPTION_ERRORS, 6)
}

function test_store_sub_params_values(params) { #locals
  set_sub_param_defaults(params)
  opt_store_sub_params("t", "L:0,M:0,N:3,S:\\,,P:--,I:{,T:}", params)
  check("opt_store_sub_params: L", params["t", "L"], 0)
  check("opt_store_sub_params: M", params["t", "M"], 0)
  check("opt_store_sub_params: N", params["t", "N"], 3)
  check("opt_store_sub_params: S is an escaped comma", params["t", "S"], ",")
  check("opt_store_sub_params: P", params["t", "P"], "--")
  check("opt_store_sub_params: I", params["t", "I"], "{")
  check("opt_store_sub_params: T", params["t", "T"], "}")
  check_true("opt_store_sub_params: L, M and N are numbers (a string \"0\" would be true)",
             !params["t", "L"] && !params["t", "M"])

  opt_store_sub_params("u", "", params)
  check("opt_store_sub_params: default L", params["u", "L"], 1)
  check("opt_store_sub_params: default M", params["u", "M"], 1)
  check("opt_store_sub_params: default N", params["u", "N"], -1)
  check("opt_store_sub_params: default S", params["u", "S"], "")
  check("opt_store_sub_params: default P", params["u", "P"], "")
  check("opt_store_sub_params: default I", params["u", "I"], "")
  check("opt_store_sub_params: default T", params["u", "T"], "")
  check("opt_store_sub_params: the defaults are unchanged", params["", "L"] params["", "N"], "1-1")
}

function test_form_substitutions_colons(params, labels, values, names) { #locals
  init_globals()
  opt_form_substitutions("t:t:/a:b;u:/a:b;v::/a:b;w::", 0, params, labels, values, names)
  check("opt_form_substitutions: value with colons after a label", values["t"], "/a:b")
  check_true("opt_form_substitutions: an empty label is no label", !("v" in labels))
  check("opt_form_substitutions: value with colons after an empty label", values["v"], "/a:b")
  check_true("opt_form_substitutions: NAME:: has no label", !("w" in labels))
  check("opt_form_substitutions: NAME:: has empty values", values["w"], "")
  check("opt_form_substitutions: an empty label is not an error", OPTION_ERRORS, 0)
  check("opt_form_substitutions: without a label, the 2nd colon ends the label", labels["u"], "/a")
  check("opt_form_substitutions: without a label, the rest is the value", values["u"], "b")
}

function test_form_substitutions_spaces_in_name(params, labels, values, names) { #locals
  opt_form_substitutions(" \tt :v", 0, params, labels, values, names)
  check("opt_form_substitutions: spaces around the name are removed", names[1], "t")
  check("opt_form_substitutions: value of a name with spaces", values["t"], "v")

  opt_form_substitutions("t: \tnew :v;u: :w", 0, params, labels, values, names)
  check("opt_form_substitutions: spaces around the label are removed", labels["t"], "new")
  check_true("opt_form_substitutions: a blank label is no label", !("u" in labels))
  check("opt_form_substitutions: value after a blank label", values["u"], "w")
}

function test_form_substitutions_dsub(params, labels, values, names) { #locals
  opt_form_substitutions("$(X):a:b;$(Y):;$(Z):c", 1, params, labels, values, names)
  check("opt_form_substitutions (DSUB): no labels", array_length(labels), 0)
  check("opt_form_substitutions (DSUB): the value is everything after the 1st colon",
        values["$(Y)"], "")
  check("opt_form_substitutions (DSUB): names in the order given",
        names[1] " " names[2] " " names[3], "$(X) $(Y) $(Z)")

  opt_form_substitutions("<A:1>$(X):a:b", 1, params, labels, values, names)
  check("opt_form_substitutions (DSUB): parameters", params["$(X)", "A"] " " params["$(X)", "D"],
        "1 1")
  check("opt_form_substitutions (DSUB): value with colons", values["$(X)"], "a:b")
}

function test_form_substitutions_name_with_angle_brackets(params, labels, values, names) { #locals
  init_globals()
  opt_form_substitutions("<><t>:new:v;<L:0><u>:w", 0, params, labels, values, names)
  check("opt_form_substitutions: empty parameters before a NAME that starts with <...>",
        names[1] " " labels["<t>"] " " values["<t>"], "<t> new v")
  check("opt_form_substitutions: parameters before a NAME that starts with <...>",
        names[2] " " params["<u>", "L"] " " values["<u>"], "<u> 0 w")

  opt_form_substitutions("<><b>:B;<A:1, D:0><i>:I", 1, params, labels, values, names)
  check("opt_form_substitutions (DSUB): empty parameters before a NAME that starts with <...>",
        names[1] " " values["<b>"], "<b> B")
  check("opt_form_substitutions (DSUB): parameters before a NAME that starts with <...>",
        names[2] " " params["<i>", "A"] params["<i>", "D"] " " values["<i>"], "<i> 10 I")
  check("opt_form_substitutions: a NAME that starts with <...> is not an error", OPTION_ERRORS, 0)
}

function test_form_substitutions_repeated(params, labels, values, names) { #locals
  init_globals()
  opt_form_substitutions("t:a;u:b;t:c;t:a", 0, params, labels, values, names)
  check("opt_form_substitutions: a repeated name is an error (also an identical repeat)",
        stderr_text(),
        "makefile-doc: error: SUB: 't' is given more than once\n" \
        "makefile-doc: error: SUB: 't' is given more than once\n")
  check("opt_form_substitutions: every repeat is counted", OPTION_ERRORS, 2)

  opt_form_substitutions("$(X):a;$(X):b", 1, params, labels, values, names)
  check("opt_form_substitutions (DSUB): a repeated name is an error",
        stderr_text(),
        "makefile-doc: error: DSUB: '$(X)' is given more than once\n")

  init_globals()
  opt_form_substitutions("t:a", 0, params, labels, values, names)
  opt_form_substitutions("t:b", 1, params, labels, values, names)
  check("opt_form_substitutions: the same name in SUB and DSUB is not an error", OPTION_ERRORS, 0)
}

function test_opt_store_dsub_params(params) { #locals
  init_globals()
  set_dsub_param_defaults(params)
  opt_store_dsub_params("x", "", params)
  opt_store_dsub_params("x", "A:1", params)
  opt_store_dsub_params("x", " A : 1 , D:0,", params)
  check("opt_store_dsub_params: valid parameters are not errors", OPTION_ERRORS, 0)

  opt_store_dsub_params("x", "L:0", params)
  check("opt_store_dsub_params: unknown parameter",
        stderr_text(), "makefile-doc: error: DSUB: unknown parameter L of x (use A or D)\n")
  opt_store_dsub_params("x", "A:yes", params)
  check("opt_store_dsub_params: A should be 0 or 1",
        stderr_text(), "makefile-doc: error: DSUB: parameter A of x should be 0 or 1\n")
  opt_store_dsub_params("x", "D:0", params)
  check("opt_store_dsub_params: replaced nowhere",
        stderr_text(), "makefile-doc: error: DSUB: x is replaced nowhere (A and D are both 0)\n")
  opt_store_dsub_params("x", "A:1, A :1", params)
  check("opt_store_dsub_params: a repeated parameter",
        stderr_text(), "makefile-doc: error: DSUB: parameter A of x is given more than once\n")
  check("opt_store_dsub_params: every invalid parameter is counted", OPTION_ERRORS, 4)
  init_globals()
}

function test_form_substitutions_dsub_params(labels) { #locals
  opt_form_substitutions("<A:1>b:2;<A:1,D:0>c:3;d:6", 1, DSUB_PARAM, labels, DSUB_VALUES,
                         DSUB_NAMES)
  check("opt_form_substitutions (DSUB): default A and D",
        DSUB_PARAM["d", "A"] " " DSUB_PARAM["d", "D"], "0 1")
  check("opt_form_substitutions (DSUB): A:1", DSUB_PARAM["b", "A"] " " DSUB_PARAM["b", "D"], "1 1")
  check("opt_form_substitutions (DSUB): A:1,D:0",
        DSUB_PARAM["c", "A"] " " DSUB_PARAM["c", "D"], "1 0")
  init_globals()
}

BEGIN {
  test_process_options_defaults()
  test_process_options_errors()
  test_form_substitutions_with_labels()
  test_form_substitutions_empty_parts()
  test_form_substitutions_semicolon()
  test_form_substitutions_empty_items()
  test_form_substitutions_invalid()
  test_opt_parse_substitution_params()
  test_opt_checked_params()
  test_opt_store_sub_params()
  test_store_sub_params_values()
  test_form_substitutions_colons()
  test_form_substitutions_spaces_in_name()
  test_form_substitutions_dsub()
  test_form_substitutions_name_with_angle_brackets()
  test_form_substitutions_repeated()
  test_opt_store_dsub_params()
  test_form_substitutions_dsub_params()
  done()
}
