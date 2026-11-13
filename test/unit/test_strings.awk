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

function test_string_replace(    text) {
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
  done()
}
