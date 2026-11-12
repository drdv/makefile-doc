function test_substitute_backticks_patterns() {
  COLOR_BACKTICKS_CODE = ">>>"
  COLOR_RESET_CODE = "<<<"

  check("substitute_backticks_patterns: two regions",
        substitute_backticks_patterns("this `is` a test `x` and"),
        "this >>>is<<< a test >>>x<<< and")
  check("substitute_backticks_patterns: regions are paired from the left",
        substitute_backticks_patterns("`this `is` a test `x` and`"),
        ">>>this <<<is>>> a test <<<x>>> and<<<")
  check("substitute_backticks_patterns: inside braces",
        substitute_backticks_patterns("{`1`, `2`, `3`}"),
        "{>>>1<<<, >>>2<<<, >>>3<<<}")
  check("substitute_backticks_patterns: region with a space",
        substitute_backticks_patterns("empty ` ` region"),
        "empty >>> <<< region")
  check("substitute_backticks_patterns: empty region is left as is",
        substitute_backticks_patterns("empty `` region"),
        "empty `` region")
}

function test_escape_braces_for_latex_output() {
  OUTPUT_FORMAT = "HTML"
  check("escape_braces_for_latex_output: HTML is unchanged",
        escape_braces_for_latex_output("this is {a test} string"),
        "this is {a test} string")

  OUTPUT_FORMAT = "LATEX"
  check("escape_braces_for_latex_output: LATEX",
        escape_braces_for_latex_output("this is {a test} string"),
        "this is \\{a test\\} string")

  OUTPUT_FORMAT = ""
}

BEGIN {
  test_substitute_backticks_patterns()
  test_escape_braces_for_latex_output()
  done()
}
