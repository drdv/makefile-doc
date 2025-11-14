function test_utils_dc_target_main(    target_name_nominal, expected) {
  target_name_nominal = "some-target"

  expected = target_name_nominal DOUBLE_COLON_SEPARATOR "1"
  assert_equal(form_dc_target_name(target_name_nominal), expected,
               "form_dc_target_name(\"" target_name_nominal "\")")

  TARGETS_DC_COUNTER[target_name_nominal]++

  expected = target_name_nominal DOUBLE_COLON_SEPARATOR "2"
  assert_equal(form_dc_target_name(target_name_nominal), expected,
               "form_dc_target_name(\"" target_name_nominal "\")")

}

BEGIN {

  UNITTEST_CURRENT_FILE = "test_utils_dc_target"

  DOUBLE_COLON_SEPARATOR = "~"
  split("", TARGETS_DC_COUNTER)

  UNIT_TEST = UNIT_TEST == "" ? 1 : UNIT_TEST
  if (UNIT_TEST) {
    test_utils_dc_target_main()
  }
}
