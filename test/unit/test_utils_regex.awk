function test_utils_regex_main() {
  test_utils_regex_get_tag_from_description()
  test_utils_regex_parse_variable_name()
  test_utils_regex_substitute_backticks_patterns()
  test_utils_regex_strip_start_end_spaces_tabs()
  test_utils_regex_escape_braces_for_latex_output()
}

function test_utils_regex_escape_braces_for_latex_output(    text, expected) {
  OUTPUT_FORMAT = "HTML"

  text = "this is {a test} string"
  expected = text
  assert_equal(escape_braces_for_latex_output(text),
               expected,
               "escape_braces_for_latex_output(\"" text "\")")

  OUTPUT_FORMAT = "LATEX"

  text = "this is {a test} string"
  expected = "this is \\{a test\\} string"
  assert_equal(escape_braces_for_latex_output(text),
               expected,
               "escape_braces_for_latex_output(\"" text "\")")
}

function test_utils_regex_strip_start_end_spaces_tabs(    text, expected) {
  expected = "this is a test string"
  text = "   " expected "   "
  assert_equal(strip_start_end_spaces_tabs(text),
               expected,
               "strip_start_end_spaces_tabs(\"" text "\")")

  expected = "this is a test string"
  text = " \t   " expected " \t   "
  assert_equal(strip_start_end_spaces_tabs(text),
               expected,
               "strip_start_end_spaces_tabs(\"" text "\")")
}

function test_utils_regex_substitute_backticks_patterns(    text, s, e) {
  s = COLOR_BACKTICKS_CODE
  e = COLOR_RESET_CODE

  text = "this `is` a test `x` and"
  assert_equal(substitute_backticks_patterns(text),
               "this "s"is"e" a test "s"x"e" and",
               "substitute_backticks_patterns(\"" text "\")")

  text = "`this `is` a test `x` and`"
  assert_equal(substitute_backticks_patterns(text),
               s"this "e"is"s" a test "e"x"s" and"e,
               "substitute_backticks_patterns(\"" text "\")")

  text = "{`1`, `2`, `3`}"
  assert_equal(substitute_backticks_patterns(text),
               "{"s"1"e", "s"2"e", "s"3"e"}",
               "substitute_backticks_patterns(\"" text "\")")

  text = "empty ` ` region"
  assert_equal(substitute_backticks_patterns(text),
               "empty "s" "e" region",
               "substitute_backticks_patterns(\"" text "\")")

  # here we simply leave the empty backtick region
  text = "empty `` region"
  assert_equal(substitute_backticks_patterns(text),
               text,
               "substitute_backticks_patterns(\"" text "\")")
}

function test_utils_regex_parse_variable_name(    whole_line, var, op) {
  var = "VAR2_1"; op = ":="
  whole_line = var op "1##comment"
  assert_equal(strip_start_end_spaces_tabs(parse_variable_name(whole_line)),
               var,
               "parse_variable_name(\"" whole_line "\")")

  var = "var2_1"; op = "   ?=  "
  whole_line = var op "1##comment"
  assert_equal(strip_start_end_spaces_tabs(parse_variable_name(whole_line)),
               var,
               "parse_variable_name(\"" whole_line "\")")

  var = "x"; op = "   :::="
  whole_line = var op "fsws"
  assert_equal(strip_start_end_spaces_tabs(parse_variable_name(whole_line)),
               var,
               "parse_variable_name(\"" whole_line "\")")

  var = "__a__"; op = "   +="
  whole_line = var op
  assert_equal(strip_start_end_spaces_tabs(parse_variable_name(whole_line)),
               var,
               "parse_variable_name(\"" whole_line "\")")

  var = "X"; op = " = ## doc"
  whole_line = var op
  assert_equal(strip_start_end_spaces_tabs(parse_variable_name(whole_line)),
               var,
               "parse_variable_name(\"" whole_line "\")")

  var = "this_is_A_VARIABLE"; op = " ::= this is a value ## doc"
  whole_line = var op
  assert_equal(strip_start_end_spaces_tabs(parse_variable_name(whole_line)),
               var,
               "parse_variable_name(\"" whole_line "\")")

  var = "x4"; op = "?=## doc"
  whole_line = var op
  assert_equal(strip_start_end_spaces_tabs(parse_variable_name(whole_line)),
               var,
               "parse_variable_name(\"" whole_line "\")")

  var = "_w"; op = "::="
  whole_line = "override unexport private  override     private  export " var op
  assert_equal(strip_start_end_spaces_tabs(parse_variable_name(whole_line)),
               var,
               "parse_variable_name(\"" whole_line "\")")

  var = "override1"; op = "     ::=     1"
  whole_line = "private  override     private  override    export unexport " var op
  assert_equal(strip_start_end_spaces_tabs(parse_variable_name(whole_line)),
               var,
               "parse_variable_name(\"" whole_line "\")")

  var = "export_override"; op = "::=1"
  whole_line = "private  override     private  override    export unexport " var op
  assert_equal(strip_start_end_spaces_tabs(parse_variable_name(whole_line)),
               var,
               "parse_variable_name(\"" whole_line "\")")
}

function test_utils_regex_get_tag_from_description(    text, tag) {
  tag = "##"
  text = "   " tag "   a description"
  assert_equal(get_tag_from_description(text),
               tag,
               "get_tag_from_description(\"" text "\")")

  tag = "##!"
  text = "   " tag "   a description"
  assert_equal(get_tag_from_description(text),
               tag,
               "get_tag_from_description(\"" text "\")")

  tag = "##%"
  text = "   " tag "   a description"
  assert_equal(get_tag_from_description(text),
               tag,
               "get_tag_from_description(\"" text "\")")

  tag = "##Z"
  text = "   " tag "   a description"
  assert_equal(get_tag_from_description(text),
               "##",
               "get_tag_from_description(\"" text "\")")

  tag = "!#"
  text = "   " tag "   a description"
  assert_equal(get_tag_from_description(text),
               0,
               "get_tag_from_description(\"" text "\")")
}

BEGIN {
  UNITTEST_CURRENT_FILE = "test_utils_regex"

  initialize_variables_regex()

  # assume arbitrary delimiters
  COLOR_BACKTICKS_CODE = ">>>"
  COLOR_RESET_CODE = "<<<"

  UNIT_TEST = UNIT_TEST == "" ? 1 : UNIT_TEST
  if (UNIT_TEST) {
    test_utils_regex_main()
  }
}
