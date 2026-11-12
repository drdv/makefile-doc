function test_utils_docs_data_assemble_description_section_data(    arr, expected) {
  arr[1] = "This is the first line"
  check("1: assemble_description_section_data(array)",
        assemble_description_section_data(arr), arr[1])

  arr[2] = "   second line"
  arr[3] = "\t last line  "
  expected = arr[1] "\n" arr[2] "\n" arr[3]
  check("2: assemble_description_section_data(array)",
        assemble_description_section_data(arr), expected)

  # test an empty array (even though this cannot happen in the actual code)
  delete arr
  check("3: assemble_description_section_data(array)",
        assemble_description_section_data(arr), "")
}

BEGIN {
  test_utils_docs_data_assemble_description_section_data()
  done()
}
