function test_utils_dc_target_main(    target_name_nominal, expected) {
  target_name_nominal = "some-target"

  expected = target_name_nominal DOUBLE_COLON_SEPARATOR "1"
  check("form_dc_target_name(\"" target_name_nominal "\")",
        form_dc_target_name(target_name_nominal), expected)

  TARGETS_DC_COUNTER[target_name_nominal]++

  expected = target_name_nominal DOUBLE_COLON_SEPARATOR "2"
  check("form_dc_target_name(\"" target_name_nominal "\")",
        form_dc_target_name(target_name_nominal), expected)
}

BEGIN {
  test_utils_dc_target_main()
  done()
}
