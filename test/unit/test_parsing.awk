function test_get_tag_from_description() {
  check("get_tag_from_description: ##", get_tag_from_description("   ##   doc"), "##")
  check("get_tag_from_description: ##!", get_tag_from_description("   ##!   doc"), "##!")
  check("get_tag_from_description: ##%", get_tag_from_description("   ##%   doc"), "##%")
  check("get_tag_from_description: ##Z is ##", get_tag_from_description("   ##Z   doc"), "##")
  check("get_tag_from_description: no tag", get_tag_from_description("   !#   doc"), 0)
}

function test_parse_variable_name() {
  check("parse_variable_name: := without spaces",
        parse_variable_name("VAR2_1:=1##comment"), "VAR2_1")
  check("parse_variable_name: ?= with spaces",
        parse_variable_name("var2_1   ?=  1##comment"), "var2_1")
  check("parse_variable_name: :::=",
        parse_variable_name("x   :::=fsws"), "x")
  check("parse_variable_name: += without value",
        parse_variable_name("__a__   +="), "__a__")
  check("parse_variable_name: = with inline doc",
        parse_variable_name("X = ## doc"), "X")
  check("parse_variable_name: ::= with value and inline doc",
        parse_variable_name("this_is_A_VARIABLE ::= this is a value ## doc"),
        "this_is_A_VARIABLE")
  check("parse_variable_name: ?= with inline doc and no value",
        parse_variable_name("x4?=## doc"), "x4")
  check("parse_variable_name: repeated qualifiers",
        parse_variable_name("override unexport private  override     private  export _w::="),
        "_w")
  check("parse_variable_name: name starting with a qualifier",
        parse_variable_name("private  override  export unexport override1     ::=     1"),
        "override1")
  check("parse_variable_name: name made of qualifiers",
        parse_variable_name("private  override  export unexport export_override::=1"),
        "export_override")
}

# the description saved by parse_inline_descriptions(line), or "<none>"
function saved_inline_description(line) {
  forget_descriptions_data()
  parse_inline_descriptions(line)
  return length_array_posix(DESCRIPTION_DATA) ? DESCRIPTION_DATA[1] : "<none>"
}

function test_parse_inline_descriptions() {
  check("parse_inline_descriptions: ## (a ; in the doc is kept)",
        saved_inline_description("target: ## some ;description"), "## some ;description")
  check("parse_inline_descriptions: ##! (a ; in the doc is kept)",
        saved_inline_description("target: ##! some description;"), "##! some description;")
  check("parse_inline_descriptions: ##%",
        saved_inline_description("target: ##% some description"), "##% some description")
  check("parse_inline_descriptions: after deps without a space",
        saved_inline_description("target: deps1 deps2 | deps3## some description"),
        "## some description")

  check("parse_inline_descriptions: none after an empty inline recipe",
        saved_inline_description("target:; ## some description"), "<none>")
  check("parse_inline_descriptions: none after an inline recipe",
        saved_inline_description("target:; @echo 1 ##! some description"), "<none>")
  check("parse_inline_descriptions: none after an inline recipe with two commands",
        saved_inline_description("target: ; @echo 1 ; echo 2 ##% some description"), "<none>")
  check("parse_inline_descriptions: none after deps and an inline recipe",
        saved_inline_description("target: deps1 deps2 | deps3 ; echo 1 ## some description"),
        "<none>")
  check("parse_inline_descriptions: none without a doc",
        saved_inline_description("target: "), "<none>")
  check("parse_inline_descriptions: none after deps without a doc",
        saved_inline_description("target: deps1 deps2 | deps3"), "<none>")

  saved_inline_description("target: ## doc")
  check("parse_inline_descriptions: the index advances", DESCRIPTION_DATA_INDEX, 2)
}

function test_form_dc_target_name() {
  init_globals()
  check("form_dc_target_name: first rule", form_dc_target_name("t"), "t~1")

  TARGETS_DC_COUNTER["t"]++
  check("form_dc_target_name: second rule", form_dc_target_name("t"), "t~2")
}

function test_assemble_description_section_data(    arr) {
  arr[1] = "first line"
  check("assemble_description_section_data: one line",
        assemble_description_section_data(arr),
        "first line")

  arr[2] = "   second line"
  arr[3] = "\t last line  "
  check("assemble_description_section_data: lines are joined with newlines (spaces kept)",
        assemble_description_section_data(arr),
        "first line\n   second line\n\t last line  ")

  delete arr
  check("assemble_description_section_data: empty array",
        assemble_description_section_data(arr),
        "")
}

function test_update_display_parameters(    description) {
  description = "Z## Wrong tag"
  update_display_parameters(description)
  check("update_display_parameters: wrong tag is reported on stderr",
        stderr_text(),
        "ERROR (we shouldn't be here): Z## Wrong tag\n")
  check("update_display_parameters: wrong tag calls fatal()",
        FATAL_MSG,
        "ERROR (we shouldn't be here): Z## Wrong tag")
}

function test_has_odd_terminal_backslashes() {
  check("has_odd_terminal_backslashes: none", has_odd_terminal_backslashes("abc"), 0)
  check("has_odd_terminal_backslashes: empty string", has_odd_terminal_backslashes(""), 0)
  check("has_odd_terminal_backslashes: only a backslash", has_odd_terminal_backslashes("\\"), 1)
  check("has_odd_terminal_backslashes: one", has_odd_terminal_backslashes("abc\\"), 1)
  check("has_odd_terminal_backslashes: two", has_odd_terminal_backslashes("abc\\\\"), 0)
  check("has_odd_terminal_backslashes: three", has_odd_terminal_backslashes("abc\\\\\\"), 1)
  check("has_odd_terminal_backslashes: only the trailing run counts",
        has_odd_terminal_backslashes("a\\ \\"), 1)
  check("has_odd_terminal_backslashes: not at the end",
        has_odd_terminal_backslashes("a\\ b"), 0)
}

function test_is_double_colon_rule() {
  check("is_double_colon_rule: ::", is_double_colon_rule("t::"), 1)
  check("is_double_colon_rule: :", is_double_colon_rule("t:"), 0)
  check("is_double_colon_rule: :: with a target variable", is_double_colon_rule("t:: A:=1"), 1)
  check("is_double_colon_rule: grouped", is_double_colon_rule("a b &::"), 1)
  check("is_double_colon_rule: :: in the recipe of a : rule",
        is_double_colon_rule("t: ; @echo \"a::b\""), 0)
  check("is_double_colon_rule: no colon", is_double_colon_rule("t"), 0)
}

function test_detect_ignored_targets() {
  init_globals()
  check("detect_ignored_targets: .PHONY", detect_ignored_targets(".PHONY: t"), 1)
  check("detect_ignored_targets: .SILENT", detect_ignored_targets(".SILENT: t"), 1)
  check("detect_ignored_targets: .IGNORE", detect_ignored_targets(".IGNORE: t"), 1)
  check("detect_ignored_targets: .SECONDARY", detect_ignored_targets(".SECONDARY: t"), 1)
  check("detect_ignored_targets: .INTERMEDIATE", detect_ignored_targets(".INTERMEDIATE: t"), 1)
  check("detect_ignored_targets: .PRECIOUS", detect_ignored_targets(".PRECIOUS: t"), 1)
  check("detect_ignored_targets: leading whitespace and spaces before :",
        detect_ignored_targets(" \t.PHONY  : t"), 1)
  check("detect_ignored_targets: tab before :",
        detect_ignored_targets(".PHONY\t: t"), 1)
  check("detect_ignored_targets: .SECONDEXPANSION is not ignored",
        detect_ignored_targets(".SECONDEXPANSION:"), 0)
  check("detect_ignored_targets: a longer name", detect_ignored_targets(".PHONYX: t"), 0)
  check("detect_ignored_targets: .PHONY as a prerequisite", detect_ignored_targets("t: .PHONY"), 0)
}

BEGIN {
  test_get_tag_from_description()
  test_parse_variable_name()
  test_parse_inline_descriptions()
  test_form_dc_target_name()
  test_assemble_description_section_data()
  test_update_display_parameters()
  test_has_odd_terminal_backslashes()
  test_is_double_colon_rule()
  test_detect_ignored_targets()
  done()
}
