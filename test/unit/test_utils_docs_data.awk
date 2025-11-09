function test_utils_docs_data_main() {
  test_utils_docs_data_assemble_description_section_data()
}

function test_utils_docs_data_assemble_description_section_data(    arr, expected) {

  arr[1] = "This is the first line"
  assert_equal(assemble_description_section_data(arr),
               arr[1],
               "1: assemble_description_section_data(array)")

  arr[2] = "   second line"
  arr[3] = "\t last line  "
  expected = arr[1] "\n" arr[2] "\n" arr[3]
  assert_equal(assemble_description_section_data(arr),
               expected,
               "2: assemble_description_section_data(array)")

  # test an empty array (even though this cannot happen in the actual code)
  delete arr
  assert_equal(assemble_description_section_data(arr),
               "",
               "3: assemble_description_section_data(array)")
}

BEGIN {
  UNITTEST_CURRENT_FILE = "test_utils_docs_data"

  UNIT_TEST = UNIT_TEST == "" ? 1 : UNIT_TEST
  if (UNIT_TEST) {
    test_utils_docs_data_main()
  }
}
