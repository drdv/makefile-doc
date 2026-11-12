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

# initialize the colors as process_options() does (with the default color options)
function setup_colors(output_format, export_theme) {
  OUTPUT_FORMAT = output_format
  EXPORT_THEME = export_theme
  COLOR_DEFAULT = COLOR_ATTENTION = COLOR_DEPRECATED = ""
  COLOR_WARNING = COLOR_SECTION = COLOR_BACKTICKS = ""
  initialize_colors()
}

function test_validate_ansi_param() {
  setup_colors("ANSI", "")
  check("validate_ansi_param: color", validate_ansi_param(34), 34)
  check("validate_ansi_param: attribute", validate_ansi_param(9), 9)
  check("validate_ansi_param: bright background", validate_ansi_param(107), 107)
  check("validate_ansi_param: 0 (no color)", validate_ansi_param(0), 0)
  check("validate_ansi_param: unsupported attribute", validate_ansi_param(2), 0)
  check("validate_ansi_param: out of range", validate_ansi_param(108), 0)
  check("validate_ansi_param: not a number", validate_ansi_param("abc"), 0)
  check("validate_ansi_param: FG is not a color parameter", validate_ansi_param("FG"), 0)
}

function test_define_color() {
  setup_colors("ANSI", "")
  check("define_color (ANSI): color", define_color(34, "DEFAULT"), "\033[34m")
  check("define_color (ANSI): reset", define_color(-1), "\033[0m")
  check("define_color (ANSI): no color", define_color(0, "DEFAULT"), "")

  setup_colors("HTML", "")
  check("define_color (HTML): color", define_color(34, "DEFAULT"),
        "<span class=\"color-default\">")
  check("define_color (HTML): reset", define_color(-1), "</span>")

  setup_colors("LATEX", "")
  check("define_color (LATEX): color", define_color(34, "DEFAULT"),
        "\\textcolor{color-default}{")
  check("define_color (LATEX): background", define_color(44, "BACKTICKS"),
        "\\bgcolor{color-backticks}{")
  check("define_color (LATEX): attribute", define_color(1, "BACKTICKS"), "\\textbf{")
  check("define_color (LATEX): reset", define_color(-1), "}")

  setup_colors("", "")
}

function test_export_theme() {
  setup_colors("HTML", "")
  check("export theme: no FG by default", ANSI_TO_HTML_COLOR["FG"], -1)
  check("export theme: no BG by default", ANSI_TO_HTML_COLOR["BG"], -1)
  check("export theme: default (solarized) blue", ANSI_TO_HTML_COLOR[34], "268bd2")

  setup_colors("HTML", "32:d33682,FG:000000,BG:AAAAAA,3:ffffff,5:123456")
  check("export theme: color", ANSI_TO_HTML_COLOR[32], "d33682")
  check("export theme: FG", ANSI_TO_HTML_COLOR["FG"], "000000")
  check("export theme: BG", ANSI_TO_HTML_COLOR["BG"], "AAAAAA")
  check("export theme: attributes (0-9) cannot be changed", ANSI_TO_HTML_COLOR[3], "italic")
  check_true("export theme: unsupported parameters are not added",
             !(5 in ANSI_TO_HTML_COLOR))
  check("export theme: the background of a color is set separately",
        ANSI_TO_HTML_COLOR[42], "859900")

  setup_colors("", "")
}

function test_ansi_color_param_to_html_style() {
  setup_colors("HTML", "")
  check("ansi_color_param_to_html_style: color",
        ansi_color_param_to_html_style(34, "DEFAULT"),
        "    .color-default { color: #268bd2; }\n")
  check("ansi_color_param_to_html_style: attribute",
        ansi_color_param_to_html_style(1, "BACKTICKS"),
        "    .color-backticks { font-weight: bold; }\n")
  check("ansi_color_param_to_html_style: no color",
        ansi_color_param_to_html_style(0, "SECTION"),
        "    .color-section {}\n")
  check("ansi_color_param_to_html_style: FG not set",
        ansi_color_param_to_html_style("FG", "FG"), "")

  setup_colors("HTML", "BG:000000")
  check("ansi_color_param_to_html_style: BG",
        ansi_color_param_to_html_style("BG", "BG"),
        "    .makefile-doc-bg { background-color: #000000; }\n")

  setup_colors("", "")
}

BEGIN {
  test_substitute_backticks_patterns()
  test_escape_braces_for_latex_output()
  test_validate_ansi_param()
  test_define_color()
  test_export_theme()
  test_ansi_color_param_to_html_style()
  done()
}
