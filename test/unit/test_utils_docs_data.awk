function test_assemble_description_section_data(    arr) {
  arr[1] = "first line"
  check("assemble_description_section_data: one line",
        assemble_description_section_data(arr),
        "first line")

  arr[2] = "   second line"
  arr[3] = "\t last line  "
  check("assemble_description_section_data: lines are joined with newlines (spaces kept)",
        assemble_description_section_data(arr),
        "first line\n   second line\n\t last line  ")

  delete arr
  check("assemble_description_section_data: empty array",
        assemble_description_section_data(arr),
        "")
}

BEGIN {
  test_assemble_description_section_data()
  done()
}
