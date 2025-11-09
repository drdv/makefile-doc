function test_utils_general_main(    arr, sorted_keys) {
  assert_equal(max(1, 2), 2, "max(1, 2) == 2")
  assert_equal(max(1, -3), 1, "max(1, -3) == 1")
  assert_equal(min(1, 2), 1, "min(1, 2) == 1")
  assert_equal(min(1, -3), -3, "min(1, -3) == -3")
  assert_equal(repeated_string("", 5), "     ", "repeated_string("", 5)")
  assert_equal(repeated_string("a", 4), "aaaa", "repeated_string(\"a\", 4)")
  assert_equal(abs(-1), 1, "abs(-1) == 1")
  assert_equal(abs(1), 1, "abs(1) == 1")
  assert_equal(abs(0), 0, "abs(0) == 0")

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

  delete arr
  arr["kb"] = 1
  arr["a3"] = 1
  arr["b2"] = 1
  arr["a4"] = 1
  arr["z0"] = 1
  sort_keys(arr, sorted_keys)
  assert(sorted_keys[1] == "a3" &&
         sorted_keys[2] == "a4" &&
         sorted_keys[3] == "b2" &&
         sorted_keys[4] == "kb" &&
         sorted_keys[5] == "z0",
         "sort_keys")
}

BEGIN {
  UNITTEST_CURRENT_FILE = "test_utils_general"

  UNIT_TEST = UNIT_TEST == "" ? 1 : UNIT_TEST
  if (UNIT_TEST) {
    test_utils_general_main()
  }
}
