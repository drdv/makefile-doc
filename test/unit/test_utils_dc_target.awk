function test_form_dc_target_name() {
  init_globals()
  check("form_dc_target_name: first rule", form_dc_target_name("t"), "t~1")

  TARGETS_DC_COUNTER["t"]++
  check("form_dc_target_name: second rule", form_dc_target_name("t"), "t~2")
}

BEGIN {
  test_form_dc_target_name()
  done()
}
