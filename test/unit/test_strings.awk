function test_max_min() {
  check("max: second is larger", max(1, 2), 2)
  check("max: first is larger", max(1, -3), 1)
  check("min: first is smaller", min(1, 2), 1)
  check("min: second is smaller", min(1, -3), -3)
}

function test_repeated_string() {
  check("repeated_string: empty string means a space", repeated_string("", 5), "     ")
  check("repeated_string: a character", repeated_string("a", 4), "aaaa")
}

function test_length_array_posix(    arr) {
  check("length_array_posix: empty array", length_array_posix(arr), 0)

  arr["k1"] = "this"
  arr["k2"] = "is"
  arr["k3"] = "a"
  arr["k4"] = "test"
  check("length_array_posix: 4 elements", length_array_posix(arr), 4)
}

function test_join(    arr) {
  split("this is another test", arr, " ")
  check("join: colon delimiter", join(arr, ":"), "this:is:another:test")
}

function test_string_replace(    text, parts) {
  text = "this is my text and this also is text not end"
  check("string_replace: two matches in the middle",
        string_replace("text", "X", text),
        "this is my X and this also is X not end")
  check("string_replace: matches at the start",
        string_replace("this", "X", text),
        "X is my text and X also is text not end")
  check("string_replace: match at the end",
        string_replace("end", "X", text),
        "this is my text and this also is text not X")
  # a "0" from split() looks like a number: it is false in a condition, but not empty
  split("0", parts, ";")
  check("string_replace: a search string of 0 (from split) is replaced",
        string_replace(parts[1], "X", "a0b0"),
        "aXbX")
  # many occurrences (a recursive implementation exhausts the stack of mawk at about 200)
  check("string_replace: 1000 occurrences",
        string_replace(" ", ".", repeated_string("", 1000)),
        repeated_string(".", 1000))
  check("string_replace: the replacement is not searched again",
        string_replace("a", "aa", "a-a"), "aa-aa")
  check("string_replace: overlapping occurrences are replaced from the left",
        string_replace("aa", "b", "aaa"), "ba")
  check("string_replace: empty search string changes nothing",
        string_replace("", "X", text),
        text)
  check("string_replace: empty replacement",
        string_replace("this", "", text),
        " is my text and  also is text not end")

  check("string_replace: no regex interpretation of $(VAR)",
        string_replace("$(VAR)", "VALUE", "this is my $(VAR) and this also is $(VAR) not end"),
        "this is my VALUE and this also is VALUE not end")
  check("string_replace: inner reference of a nested one",
        string_replace("$(NESTED)", "VAR", "nested vars $($(NESTED)) end"),
        "nested vars $(VAR) end")
  check("string_replace: reference left by the previous replacement",
        string_replace("$(VAR)", "VAL", "nested vars $(VAR) end"),
        "nested vars VAL end")
}

function test_strip_trailing_blanks() {
  check("strip_trailing_blanks: nothing to strip", strip_trailing_blanks("a b\n c\n"), "a b\n c\n")
  check("strip_trailing_blanks: empty text", strip_trailing_blanks(""), "")
  check("strip_trailing_blanks: spaces before a newline",
        strip_trailing_blanks("a  \nb\n"), "a\nb\n")
  check("strip_trailing_blanks: tabs before a newline",
        strip_trailing_blanks("a\t\t\nb\n"), "a\nb\n")
  check("strip_trailing_blanks: spaces and tabs mixed", strip_trailing_blanks("a \t \n"), "a\n")
  check("strip_trailing_blanks: blanks at the end of the text (no final newline)",
        strip_trailing_blanks("a\nb  "), "a\nb")
  check("strip_trailing_blanks: every line", strip_trailing_blanks("a \nb \nc \n"), "a\nb\nc\n")
  check("strip_trailing_blanks: a line with only blanks becomes empty",
        strip_trailing_blanks("a\n   \nb\n"), "a\n\nb\n")
  check("strip_trailing_blanks: leading and inner blanks are kept",
        strip_trailing_blanks("  a  b  \n"), "  a  b\n")
  check("strip_trailing_blanks: empty lines are kept",
        strip_trailing_blanks("a \n\n\nb\n"), "a\n\n\nb\n")
}

function test_strip_start_end_spaces_tabs() {
  check("strip_start_end_spaces_tabs: spaces",
        strip_start_end_spaces_tabs("   a test string   "), "a test string")
  check("strip_start_end_spaces_tabs: spaces and tabs",
        strip_start_end_spaces_tabs(" \t   a test string \t   "), "a test string")
}

BEGIN {
  test_max_min()
  test_repeated_string()
  test_length_array_posix()
  test_join()
  test_string_replace()
  test_strip_start_end_spaces_tabs()
  test_strip_trailing_blanks()
  done()
}
