function test_utils_general_main(    arr) {
  assert_equal(max(1, 2), 2, "max(1, 2) == 2")
  assert_equal(max(1, -3), 1, "max(1, -3) == 1")
  assert_equal(min(1, 2), 1, "min(1, 2) == 1")
  assert_equal(min(1, -3), -3, "min(1, -3) == -3")
  assert_equal(repeated_string("", 5), "     ", "repeated_string("", 5)")
  assert_equal(repeated_string("a", 4), "aaaa", "repeated_string(\"a\", 4)")

  delete arr
  assert_equal(length_array_posix(arr), 0, "1: length_array_posix(arr)")

  arr["k1"] = "this"
  arr["k2"] = "it"
  arr["k3"] = "a"
  arr["k4"] = "test"
  assert_equal(length_array_posix(arr), 4, "2: length_array_posix(arr)")

  delete arr
  split("this is another test", arr, " ")
  assert_equal(join_splitted(arr, ":"), "this:is:another:test", "join(arr, \":\")")
}

BEGIN {
  UNITTEST_CURRENT_FILE = "test_utils_general"

  UNIT_TEST = UNIT_TEST == "" ? 1 : UNIT_TEST
  if (UNIT_TEST) {
    test_utils_general_main()
  }
}
