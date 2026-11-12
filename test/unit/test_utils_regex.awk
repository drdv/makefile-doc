function test_utils_regex_main() {
  test_utils_regex_get_tag_from_description()
  test_utils_regex_parse_variable_name()
  test_utils_regex_substitute_backticks_patterns()
  test_utils_regex_strip_start_end_spaces_tabs()
  test_utils_regex_escape_braces_for_latex_output()
  test_utils_regex_parse_inline_descriptions()
  test_utils_regex_update_display_parameters()
}

function test_utils_regex_update_display_parameters(    description, stderr_content,
                                                        stderr_content_lines) {
  description = "Z## Wrong tag"
  update_display_parameters(description)
  stderr_content = stderr_text()
  split(stderr_content, stderr_content_lines, "\n")

  check("update_display_parameters(\"" description "\")",
        stderr_content_lines[1],
        sprintf("ERROR (we shouldn't be here): %s", description))
}

function test_utils_regex_parse_inline_descriptions(    text, expected) {
  split("", DESCRIPTION_DATA)
  DESCRIPTION_DATA_INDEX = 1

  expected = "## some ;description"
  text = "target: " expected
  parse_inline_descriptions(text)
  check("parse_inline_descriptions(\"" text "\")",
        DESCRIPTION_DATA[1],
        expected)

  expected = "##! some description;"
  text = "target: " expected
  parse_inline_descriptions(text)
  check("parse_inline_descriptions(\"" text "\")",
        DESCRIPTION_DATA[2],
        expected)

  expected = "##% some description"
  text = "target: " expected
  parse_inline_descriptions(text)
  check("parse_inline_descriptions(\"" text "\")",
        DESCRIPTION_DATA[3],
        expected)

  expected = "## some description"
  text = "target:; " expected
  parse_inline_descriptions(text)
  check("parse_inline_descriptions(\"" text "\")",
        length_array_posix(DESCRIPTION_DATA),
        3)

  expected = "##! some description"
  text = "target:; @echo 1 " expected
  parse_inline_descriptions(text)
  check("parse_inline_descriptions(\"" text "\")",
        length_array_posix(DESCRIPTION_DATA),
        3)

  expected = "##% some description"
  text = "target: ; @echo 1 ; echo 2 " expected
  parse_inline_descriptions(text)
  check("parse_inline_descriptions(\"" text "\")",
        length_array_posix(DESCRIPTION_DATA),
        3)

  text = "target: "
  parse_inline_descriptions(text)
  check("parse_inline_descriptions(\"" text "\")",
        length_array_posix(DESCRIPTION_DATA),
        3)

  text = "target: deps1 deps2 | deps3"
  parse_inline_descriptions(text)
  check("parse_inline_descriptions(\"" text "\")",
        length_array_posix(DESCRIPTION_DATA),
        3)

  expected = "## some description"
  text = "target: deps1 deps2 | deps3 ; echo 1 " expected
  parse_inline_descriptions(text)
  check("parse_inline_descriptions(\"" text "\")",
        length_array_posix(DESCRIPTION_DATA),
        3)

  expected = "## some description"
  text = "target: deps1 deps2 | deps3" expected
  parse_inline_descriptions(text)
  check("parse_inline_descriptions(\"" text "\")",
        DESCRIPTION_DATA[4],
        expected)

  check("DESCRIPTION_DATA_INDEX == 5",
        DESCRIPTION_DATA_INDEX,
        5)
}

function test_utils_regex_escape_braces_for_latex_output(    text, expected) {
  OUTPUT_FORMAT = "HTML"

  text = "this is {a test} string"
  expected = text
  check("escape_braces_for_latex_output(\"" text "\")",
        escape_braces_for_latex_output(text),
        expected)

  OUTPUT_FORMAT = "LATEX"

  text = "this is {a test} string"
  expected = "this is \\{a test\\} string"
  check("escape_braces_for_latex_output(\"" text "\")",
        escape_braces_for_latex_output(text),
        expected)
}

function test_utils_regex_strip_start_end_spaces_tabs(    text, expected) {
  expected = "this is a test string"
  text = "   " expected "   "
  check("strip_start_end_spaces_tabs(\"" text "\")",
        strip_start_end_spaces_tabs(text),
        expected)

  expected = "this is a test string"
  text = " \t   " expected " \t   "
  check("strip_start_end_spaces_tabs(\"" text "\")",
        strip_start_end_spaces_tabs(text),
        expected)
}

function test_utils_regex_substitute_backticks_patterns(    text, s, e) {
  s = COLOR_BACKTICKS_CODE
  e = COLOR_RESET_CODE

  text = "this `is` a test `x` and"
  check("substitute_backticks_patterns(\"" text "\")",
        substitute_backticks_patterns(text),
        "this "s"is"e" a test "s"x"e" and")

  text = "`this `is` a test `x` and`"
  check("substitute_backticks_patterns(\"" text "\")",
        substitute_backticks_patterns(text),
        s"this "e"is"s" a test "e"x"s" and"e)

  text = "{`1`, `2`, `3`}"
  check("substitute_backticks_patterns(\"" text "\")",
        substitute_backticks_patterns(text),
        "{"s"1"e", "s"2"e", "s"3"e"}")

  text = "empty ` ` region"
  check("substitute_backticks_patterns(\"" text "\")",
        substitute_backticks_patterns(text),
        "empty "s" "e" region")

  # here we simply leave the empty backtick region
  text = "empty `` region"
  check("substitute_backticks_patterns(\"" text "\")",
        substitute_backticks_patterns(text),
        text)
}

function test_utils_regex_parse_variable_name(    whole_line, var, op) {
  var = "VAR2_1"; op = ":="
  whole_line = var op "1##comment"
  check("parse_variable_name(\"" whole_line "\")",
        strip_start_end_spaces_tabs(parse_variable_name(whole_line)),
        var)

  var = "var2_1"; op = "   ?=  "
  whole_line = var op "1##comment"
  check("parse_variable_name(\"" whole_line "\")",
        strip_start_end_spaces_tabs(parse_variable_name(whole_line)),
        var)

  var = "x"; op = "   :::="
  whole_line = var op "fsws"
  check("parse_variable_name(\"" whole_line "\")",
        strip_start_end_spaces_tabs(parse_variable_name(whole_line)),
        var)

  var = "__a__"; op = "   +="
  whole_line = var op
  check("parse_variable_name(\"" whole_line "\")",
        strip_start_end_spaces_tabs(parse_variable_name(whole_line)),
        var)

  var = "X"; op = " = ## doc"
  whole_line = var op
  check("parse_variable_name(\"" whole_line "\")",
        strip_start_end_spaces_tabs(parse_variable_name(whole_line)),
        var)

  var = "this_is_A_VARIABLE"; op = " ::= this is a value ## doc"
  whole_line = var op
  check("parse_variable_name(\"" whole_line "\")",
        strip_start_end_spaces_tabs(parse_variable_name(whole_line)),
        var)

  var = "x4"; op = "?=## doc"
  whole_line = var op
  check("parse_variable_name(\"" whole_line "\")",
        strip_start_end_spaces_tabs(parse_variable_name(whole_line)),
        var)

  var = "_w"; op = "::="
  whole_line = "override unexport private  override     private  export " var op
  check("parse_variable_name(\"" whole_line "\")",
        strip_start_end_spaces_tabs(parse_variable_name(whole_line)),
        var)

  var = "override1"; op = "     ::=     1"
  whole_line = "private  override     private  override    export unexport " var op
  check("parse_variable_name(\"" whole_line "\")",
        strip_start_end_spaces_tabs(parse_variable_name(whole_line)),
        var)

  var = "export_override"; op = "::=1"
  whole_line = "private  override     private  override    export unexport " var op
  check("parse_variable_name(\"" whole_line "\")",
        strip_start_end_spaces_tabs(parse_variable_name(whole_line)),
        var)
}

function test_utils_regex_get_tag_from_description(    text, tag) {
  tag = "##"
  text = "   " tag "   a description"
  check("get_tag_from_description(\"" text "\")",
        get_tag_from_description(text),
        tag)

  tag = "##!"
  text = "   " tag "   a description"
  check("get_tag_from_description(\"" text "\")",
        get_tag_from_description(text),
        tag)

  tag = "##%"
  text = "   " tag "   a description"
  check("get_tag_from_description(\"" text "\")",
        get_tag_from_description(text),
        tag)

  tag = "##Z"
  text = "   " tag "   a description"
  check("get_tag_from_description(\"" text "\")",
        get_tag_from_description(text),
        "##")

  tag = "!#"
  text = "   " tag "   a description"
  check("get_tag_from_description(\"" text "\")",
        get_tag_from_description(text),
        0)
}

BEGIN {
  # assume arbitrary delimiters
  COLOR_BACKTICKS_CODE = ">>>"
  COLOR_RESET_CODE = "<<<"

  test_utils_regex_main()
  done()
}
