function test_get_doc_tag() {
  check("get_doc_tag: ##", get_doc_tag("##   doc"), "##")
  check("get_doc_tag: ##!", get_doc_tag("##!   doc"), "##!")
  check("get_doc_tag: ##%", get_doc_tag("##%   doc"), "##%")
  check("get_doc_tag: ##Z is ##", get_doc_tag("##Z   doc"), "##")
  check("get_doc_tag: no tag", get_doc_tag("!#   doc"), "")
}

function test_form_target_name(    state, obs) {
  init_globals()
  parser_init(state, "")
  obs["name"] = "a \t b"
  obs["grouped"] = 0
  obs["double"] = 0
  check("form_target_name: blanks collapsed", form_target_name(state, obs), "a b")
  obs["grouped"] = 1
  check("form_target_name: grouped", form_target_name(state, obs), "a b&")

  obs["name"] = "t"
  obs["grouped"] = 0
  obs["double"] = 1
  check("form_target_name: first double-colon rule", form_target_name(state, obs), "t~1")
  check("form_target_name: second double-colon rule", form_target_name(state, obs), "t~2")
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
  test_get_doc_tag()
  test_form_target_name()
  test_has_odd_terminal_backslashes()
  done()
}
