function test_utils_dc_target_msg(initial, expected, f) {
  return sprintf("\n  initial: %s\n  %s == %s",
                 initial,
                 f,
                 expected)
}

function test_utils_dc_target_main(    expected) {
  TARGETS_DC_COUNTER[1] = 5
  expected = 5
  normalize_dc_target_status(1)
  assert_equal(TARGETS_DC_COUNTER[1], expected,
               test_utils_dc_target_msg(TARGETS_DC_COUNTER[1],
                                        expected,
                                        "normalize_dc_target_status(1)"))

  TARGETS_DC_COUNTER[1] = 5
  expected = -6
  maybe_increment_dc_target_index(1, 1)
  assert_equal(TARGETS_DC_COUNTER[1], expected,
               test_utils_dc_target_msg(TARGETS_DC_COUNTER[1],
                                        expected,
                                        "normalize_dc_target_status(1)"))

  TARGETS_DC_COUNTER[1] = -6
  expected = -6
  maybe_increment_dc_target_index(1, 1)
  assert_equal(TARGETS_DC_COUNTER[1], expected,
               test_utils_dc_target_msg(TARGETS_DC_COUNTER[1],
                                        expected,
                                        "maybe_increment_dc_target_index(1, 1)"))

  TARGETS_DC_COUNTER[1] = -6
  expected = 6
  normalize_dc_target_status(1)
  assert_equal(TARGETS_DC_COUNTER[1], expected,
               test_utils_dc_target_msg(TARGETS_DC_COUNTER[1],
                                        expected,
                                        "normalize_dc_target_status(1)"))

  TARGETS_DC_COUNTER[1] = 6
  expected = 6
  maybe_increment_dc_target_index(1, 0)
  assert_equal(TARGETS_DC_COUNTER[1], expected,
               test_utils_dc_target_msg(TARGETS_DC_COUNTER[1],
                                        expected,
                                        "maybe_increment_dc_target_index(1, 0)"))
}

BEGIN {
  UNITTEST_CURRENT_FILE = "test_utils_dc_target"

  UNIT_TEST = UNIT_TEST == "" ? 1 : UNIT_TEST
  if (UNIT_TEST) {
    test_utils_dc_target_main()
  }
}
