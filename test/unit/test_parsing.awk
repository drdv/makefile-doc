function test_get_tag_from_description() {
  check("get_tag_from_description: ##", get_tag_from_description("##   doc"), "##")
  check("get_tag_from_description: ##!", get_tag_from_description("##!   doc"), "##!")
  check("get_tag_from_description: ##%", get_tag_from_description("##%   doc"), "##%")
  check("get_tag_from_description: ##Z is ##", get_tag_from_description("##Z   doc"), "##")
  check("get_tag_from_description: no tag", get_tag_from_description("!#   doc"), "")
}

function test_form_dc_target_name() {
  init_globals()
  check("form_dc_target_name: first rule", form_dc_target_name("t"), "t~1")

  TARGETS_DC_COUNTER["t"]++
  check("form_dc_target_name: second rule", form_dc_target_name("t"), "t~2")
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

BEGIN {
  test_get_tag_from_description()
  test_form_dc_target_name()
  test_has_odd_terminal_backslashes()
  done()
}
