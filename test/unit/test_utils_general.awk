function test_utils_general_main(    text, expected) {
  test_utils_general_min_max()
  test_utils_general_repeated_string()
  test_utils_general_length_array_posix()
  test_utils_general_join_splitted()

  text = "this is my text and this also is text not end"

  test_utils_general_string_replace(text, "text", "SOMETHING ELSE", "")
  test_utils_general_string_replace(text, "this", "SOMETHING ELSE", "")
  test_utils_general_string_replace(text, "end", "SOMETHING ELSE", "")
  test_utils_general_string_replace(text, "", "SOMETHING ELSE", text)
  test_utils_general_string_replace(text, "this", "", "")

  text = "this is my $(VAR) and this also is $(VAR) not end"
  expected = "this is my VALUE and this also is VALUE not end"
  test_utils_general_string_replace(text, "$(VAR)", "VALUE", expected)

  text = "nested vars $($(NESTED)) end"
  expected = "nested vars $(VAR) end"
  test_utils_general_string_replace(text, "$(NESTED)", "VAR", expected)
  test_utils_general_string_replace(expected, "$(VAR)", "VAL", "nested vars VAL end")
}

function test_utils_general_string_replace(text, string, replacement, expected) {
  if (!expected) {
    expected = text
    gsub(string, replacement, expected)
  }
  assert_equal(expected,
               string_replace(string, replacement, text))
}

function test_utils_general_join_splitted(    arr) {
  delete arr
  split("this is another test", arr, " ")
  assert_equal(join_splitted(arr, ":"), "this:is:another:test", "join(arr, \":\")")
}

function test_utils_general_length_array_posix(    arr) {
  delete arr
  assert_equal(length_array_posix(arr), 0, "1: length_array_posix(arr)")

  arr["k1"] = "this"
  arr["k2"] = "it"
  arr["k3"] = "a"
  arr["k4"] = "test"
  assert_equal(length_array_posix(arr), 4, "2: length_array_posix(arr)")
}

function test_utils_general_repeated_string() {
  assert_equal(repeated_string("", 5), "     ", "repeated_string("", 5)")
  assert_equal(repeated_string("a", 4), "aaaa", "repeated_string(\"a\", 4)")
}

function test_utils_general_min_max() {
  assert_equal(max(1, 2), 2, "max(1, 2) == 2")
  assert_equal(max(1, -3), 1, "max(1, -3) == 1")
  assert_equal(min(1, 2), 1, "min(1, 2) == 1")
  assert_equal(min(1, -3), -3, "min(1, -3) == -3")
}

BEGIN {
  UNITTEST_CURRENT_FILE = "test_utils_general"

  UNIT_TEST = UNIT_TEST == "" ? 1 : UNIT_TEST
  if (UNIT_TEST) {
    test_utils_general_main()
  }
}
