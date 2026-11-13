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

function test_escape_for_html_output() {
  OUTPUT_FORMAT = "HTML"
  check("escape_for_html_output: <, > and &",
        escape_for_html_output("AWK=<variant> & co"), "AWK=&lt;variant&gt; &amp; co")
  check("escape_for_html_output: & is escaped only once",
        escape_for_html_output("&lt;"), "&amp;lt;")

  OUTPUT_FORMAT = "LATEX"
  check("escape_for_html_output: LATEX is unchanged",
        escape_for_html_output("<a> & b"), "<a> & b")

  OUTPUT_FORMAT = ""
}

function test_escape_for_latex_output() {
  OUTPUT_FORMAT = "HTML"
  check("escape_for_latex_output: HTML is unchanged",
        escape_for_latex_output("this is {a test} string"),
        "this is {a test} string")

  OUTPUT_FORMAT = "LATEX"
  check("escape_for_latex_output: LATEX",
        escape_for_latex_output("this is {a test} string"),
        "this is \\{a test\\} string")
  check("escape_for_latex_output: backslash",
        escape_for_latex_output("a \\n b"), "a \\textbackslash{}n b")
  check("escape_for_latex_output: backslash next to braces",
        escape_for_latex_output("\\{x}"), "\\textbackslash{}\\{x\\}")

  OUTPUT_FORMAT = ""
}

function test_get_max_anchor_length(    anchors, docs) {
  init_globals()
  anchors[1] = "t"; docs["t"] = "## doc"
  anchors[2] = "long-deprecated"; docs["long-deprecated"] = "##% doc"
  anchors[3] = "attention"; docs["attention"] = "##! doc"

  DEPRECATED = 1
  check("get_max_anchor_length: all anchors displayed",
        get_max_anchor_length(anchors, docs), 15)
  DEPRECATED = 0
  check("get_max_anchor_length: hidden deprecated anchors are skipped",
        get_max_anchor_length(anchors, docs), 9)
  SUB_LABELS["t"] = "a-longer-label"
  check("get_max_anchor_length: SUB labels are used", get_max_anchor_length(anchors, docs), 14)

  delete anchors[1]
  delete anchors[3]
  check("get_max_anchor_length: 0 when no anchor is displayed",
        get_max_anchor_length(anchors, docs), 0)
  delete SUB_LABELS["t"]
  DEPRECATED = ""
}

# initialize the colors as process_options() does (with the default color options)
function setup_colors(output_format, export_theme) {
  OUTPUT_FORMAT = output_format
  EXPORT_THEME = export_theme
  COLOR_DEFAULT = COLOR_ATTENTION = COLOR_DEPRECATED = ""
  COLOR_SECTION = COLOR_BACKTICKS = ""
  COLOR = 1
  initialize_colors()
}

function test_default_color_option() {
  delete ENVIRON["NO_COLOR"]
  check("default_color_option: colors without NO_COLOR", default_color_option(), 1)
  ENVIRON["NO_COLOR"] = ""
  check("default_color_option: colors with an empty NO_COLOR", default_color_option(), 1)
  ENVIRON["NO_COLOR"] = "1"
  check("default_color_option: no colors with NO_COLOR=1", default_color_option(), 0)
  delete ENVIRON["NO_COLOR"]
}

function test_validate_ansi_param(    message) {
  init_globals()
  setup_colors("ANSI", "")
  check("validate_ansi_param: color", validate_ansi_param("COLOR_X", 34), 34)
  check("validate_ansi_param: attribute", validate_ansi_param("COLOR_X", 9), 9)
  check("validate_ansi_param: bright background", validate_ansi_param("COLOR_X", 107), 107)
  check("validate_ansi_param: 0 (no color)", validate_ansi_param("COLOR_X", 0), 0)
  check("validate_ansi_param: valid parameters are not errors", OPTION_ERRORS, 0)

  message = "ERROR: COLOR_X should be one of 0, 1, 3, 4, 9, 30-37, 40-47, 90-97, 100-107\n"
  check("validate_ansi_param: unsupported attribute", validate_ansi_param("COLOR_X", 2), 0)
  check("validate_ansi_param: unsupported attribute is an error", stderr_text(), message)
  check("validate_ansi_param: out of range", validate_ansi_param("COLOR_X", 108), 0)
  check("validate_ansi_param: not a number", validate_ansi_param("COLOR_X", "abc"), 0)
  check("validate_ansi_param: compound parameter", validate_ansi_param("COLOR_X", "1;34"), 0)
  check("validate_ansi_param: FG is not a color parameter",
        validate_ansi_param("COLOR_X", "FG"), 0)
  check("validate_ansi_param: the other errors", stderr_text(), message message message message)
  check("validate_ansi_param: every error is counted", OPTION_ERRORS, 5)
}

function test_is_bool_is_hex_color() {
  check_true("is_bool: 0", is_bool(0))
  check_true("is_bool: 1", is_bool("1"))
  check_true("is_bool: 2", !is_bool(2))
  check_true("is_bool: empty", !is_bool(""))
  check_true("is_bool: text", !is_bool("yes"))
  check_true("is_hex_color: lower case", is_hex_color("7c3f00"))
  check_true("is_hex_color: upper case", is_hex_color("AABBCC"))
  check_true("is_hex_color: 3 digits", !is_hex_color("fff"))
  check_true("is_hex_color: leading #", !is_hex_color("#7c3f00"))
  check_true("is_hex_color: not hex", !is_hex_color("00000g"))
  check_true("is_hex_color: empty", !is_hex_color(""))
}

function test_export_theme_validation() {
  init_globals()
  setup_colors("HTML", "34:7c3f00,,FG:000000")
  check("EXPORT_THEME: color of a parameter", ANSI_TO_HTML_COLOR[34], "7c3f00")
  check("EXPORT_THEME: FG", ANSI_TO_HTML_COLOR["FG"], "000000")
  check("EXPORT_THEME: valid and empty entries are not errors", OPTION_ERRORS, 0)

  setup_colors("HTML", "1:ffffff,34:fff")
  check("EXPORT_THEME: invalid entries are errors",
        stderr_text(),
        "ERROR: EXPORT_THEME: '1:ffffff' should start with FG, BG or one of " \
        "30-37, 40-47, 90-97, 100-107\n" \
        "ERROR: EXPORT_THEME: '34:fff' should end with a color of 6 hex digits\n")
  check("EXPORT_THEME: an invalid entry keeps the default", ANSI_TO_HTML_COLOR[34], "268bd2")
}


function test_define_color() {
  setup_colors("ANSI", "")
  check("define_color (ANSI): color", define_color(34, "DEFAULT"), "\033[34m")
  check("define_color (ANSI): reset", define_color(-1), "\033[0m")
  check("define_color (ANSI): no color", define_color(0, "DEFAULT"), "")

  setup_colors("HTML", "")
  check("define_color (HTML): color", define_color(34, "DEFAULT"),
        "<span class=\"makefile-doc-default\">")
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
        "  .makefile-doc-default { color: #268bd2; }\n")
  check("ansi_color_param_to_html_style: attribute",
        ansi_color_param_to_html_style(1, "BACKTICKS"),
        "  .makefile-doc-backticks { font-weight: bold; }\n")
  check("ansi_color_param_to_html_style: no rule without a color",
        ansi_color_param_to_html_style(0, "SECTION"), "")
  check("ansi_color_param_to_html_style: FG not set",
        ansi_color_param_to_html_style("FG", "FG"), "")

  setup_colors("HTML", "BG:000000")
  check("ansi_color_param_to_html_style: BG",
        ansi_color_param_to_html_style("BG", "BG"),
        "  .makefile-doc { background-color: #000000; }\n")

  setup_colors("", "")
}

BEGIN {
  test_substitute_backticks_patterns()
  test_escape_for_latex_output()
  test_escape_for_html_output()
  test_get_max_anchor_length()
  test_default_color_option()
  test_validate_ansi_param()
  test_is_bool_is_hex_color()
  test_export_theme_validation()
  test_define_color()
  test_export_theme()
  test_ansi_color_param_to_html_style()
  done()
}
