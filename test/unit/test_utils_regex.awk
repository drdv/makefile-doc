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

function test_substitute_backticks_patterns() {
  COLOR_BACKTICKS_CODE = ">>>"
  COLOR_RESET_CODE = "<<<"

  check("substitute_backticks_patterns: two regions",
        substitute_backticks_patterns("this `is` a test `x` and"),
        "this >>>is<<< a test >>>x<<< and")
  check("substitute_backticks_patterns: regions are paired from the left",
        substitute_backticks_patterns("`this `is` a test `x` and`"),
        ">>>this <<<is>>> a test <<<x>>> and<<<")
  check("substitute_backticks_patterns: inside braces",
        substitute_backticks_patterns("{`1`, `2`, `3`}"),
        "{>>>1<<<, >>>2<<<, >>>3<<<}")
  check("substitute_backticks_patterns: region with a space",
        substitute_backticks_patterns("empty ` ` region"),
        "empty >>> <<< region")
  check("substitute_backticks_patterns: empty region is left as is",
        substitute_backticks_patterns("empty `` region"),
        "empty `` region")
}

function test_strip_start_end_spaces_tabs() {
  check("strip_start_end_spaces_tabs: spaces",
        strip_start_end_spaces_tabs("   a test string   "), "a test string")
  check("strip_start_end_spaces_tabs: spaces and tabs",
        strip_start_end_spaces_tabs(" \t   a test string \t   "), "a test string")
}

function test_escape_braces_for_latex_output() {
  OUTPUT_FORMAT = "HTML"
  check("escape_braces_for_latex_output: HTML is unchanged",
        escape_braces_for_latex_output("this is {a test} string"),
        "this is {a test} string")

  OUTPUT_FORMAT = "LATEX"
  check("escape_braces_for_latex_output: LATEX",
        escape_braces_for_latex_output("this is {a test} string"),
        "this is \\{a test\\} string")

  OUTPUT_FORMAT = ""
}

# the description saved by parse_inline_descriptions(line), or "<none>"
function inline_description(line) {
  forget_descriptions_data()
  parse_inline_descriptions(line)
  return length_array_posix(DESCRIPTION_DATA) ? DESCRIPTION_DATA[1] : "<none>"
}

function test_parse_inline_descriptions() {
  check("parse_inline_descriptions: ## (a ; in the doc is kept)",
        inline_description("target: ## some ;description"), "## some ;description")
  check("parse_inline_descriptions: ##! (a ; in the doc is kept)",
        inline_description("target: ##! some description;"), "##! some description;")
  check("parse_inline_descriptions: ##%",
        inline_description("target: ##% some description"), "##% some description")
  check("parse_inline_descriptions: after deps without a space",
        inline_description("target: deps1 deps2 | deps3## some description"),
        "## some description")

  check("parse_inline_descriptions: none after an empty inline recipe",
        inline_description("target:; ## some description"), "<none>")
  check("parse_inline_descriptions: none after an inline recipe",
        inline_description("target:; @echo 1 ##! some description"), "<none>")
  check("parse_inline_descriptions: none after an inline recipe with two commands",
        inline_description("target: ; @echo 1 ; echo 2 ##% some description"), "<none>")
  check("parse_inline_descriptions: none after deps and an inline recipe",
        inline_description("target: deps1 deps2 | deps3 ; echo 1 ## some description"),
        "<none>")
  check("parse_inline_descriptions: none without a doc",
        inline_description("target: "), "<none>")
  check("parse_inline_descriptions: none after deps without a doc",
        inline_description("target: deps1 deps2 | deps3"), "<none>")

  inline_description("target: ## doc")
  check("parse_inline_descriptions: the index advances", DESCRIPTION_DATA_INDEX, 2)
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

BEGIN {
  test_get_tag_from_description()
  test_parse_variable_name()
  test_substitute_backticks_patterns()
  test_strip_start_end_spaces_tabs()
  test_escape_braces_for_latex_output()
  test_parse_inline_descriptions()
  test_update_display_parameters()
  done()
}
