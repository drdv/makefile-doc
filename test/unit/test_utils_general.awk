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
  check("string_replace(\"" string "\", \"" replacement "\", ...)",
        string_replace(string, replacement, text), expected)
}

function test_utils_general_join_splitted(    arr) {
  delete arr
  split("this is another test", arr, " ")
  check("join(arr, \":\")", join_splitted(arr, ":"), "this:is:another:test")
}

function test_utils_general_length_array_posix(    arr) {
  delete arr
  check("1: length_array_posix(arr)", length_array_posix(arr), 0)

  arr["k1"] = "this"
  arr["k2"] = "it"
  arr["k3"] = "a"
  arr["k4"] = "test"
  check("2: length_array_posix(arr)", length_array_posix(arr), 4)
}

function test_utils_general_repeated_string() {
  check("repeated_string(\"\", 5)", repeated_string("", 5), "     ")
  check("repeated_string(\"a\", 4)", repeated_string("a", 4), "aaaa")
}

function test_utils_general_min_max() {
  check("max(1, 2) == 2", max(1, 2), 2)
  check("max(1, -3) == 1", max(1, -3), 1)
  check("min(1, 2) == 1", min(1, 2), 1)
  check("min(1, -3) == -3", min(1, -3), -3)
}

BEGIN {
  test_utils_general_main()
  done()
}
