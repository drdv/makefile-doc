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

# add a record to the interface, as the parser does (section "": none)
function add_anchor(kind, name, tag, doc, section) {
  ANCHOR_COUNT++
  ANCHORS[ANCHOR_COUNT, "kind"] = kind
  ANCHORS[ANCHOR_COUNT, "name"] = name
  ANCHORS[ANCHOR_COUNT, "tag"] = tag
  ANCHORS[ANCHOR_COUNT, "doc"] = doc
  if (section != "") {
    ANCHORS[ANCHOR_COUNT, "section"] = section
  }
}

# the displayed names, in order, separated by spaces
function displayed_names(    k, names) {
  for (k = 1; k <= DISPLAY_COUNT; k++) {
    names = k == 1 ? DISPLAY[k, "name"] : names " " DISPLAY[k, "name"]
  }
  return names
}

# a variable, a target documented twice, and a deprecated target in between
function add_anchors() {
  add_anchor("variable", "V", "##", " v", " S1")
  add_anchor("target", "t", "##", " first", "")
  add_anchor("target", "old", "##%", " deprecated", " S2")
  add_anchor("target", "t", "##!", " second", "")
}

function test_prepare_rendering() {
  init_globals()
  VARS = 1
  DEPRECATED = 1
  add_anchors()
  prepare_rendering()
  check("prepare_rendering: the targets, then the variables, each once, in file order",
        displayed_names(), "t old V")
  check("prepare_rendering: the last definition gives the doc and tag",
        DISPLAY[1, "doc"] " " DISPLAY[1, "tag"], " second ##!")
  check("prepare_rendering: a section goes to the next displayed anchor",
        DISPLAY[3, "section"] DISPLAY[2, "section"], " S1 S2")
  check("prepare_rendering: the documented anchors", DOCUMENTED_COUNT, 3)

  init_globals()
  VARS = 0
  DEPRECATED = 0
  add_anchors()
  prepare_rendering()
  check("prepare_rendering: hidden anchors are left out", displayed_names(), "t")
  check("prepare_rendering: the sections of hidden anchors go to the next displayed one",
        DISPLAY[1, "section"], " S2")
  check("prepare_rendering: hidden anchors are still documented", DOCUMENTED_COUNT, 3)

  init_globals()
  VARS = 1
  DEPRECATED = 1
  SUB_LABELS["t"] = "T"
  SUB_VALUES["t"] = "a b"
  add_anchor("target", "t", "##", " doc", "")
  prepare_rendering()
  check("prepare_rendering: the displayed name and the SUB values",
        DISPLAY[1, "name"] " " DISPLAY[1, "values"], "T a b")
  check("prepare_rendering: the label is the displayed name", DISPLAY[1, "label"], "T")

  init_globals()
  add_anchor("variable", "V", "##", " doc", "")
  ANCHORS[ANCHOR_COUNT, "override"] = 1
  prepare_rendering()
  check("prepare_rendering: the label of a variable set with override",
        DISPLAY[1, "name"] "|" DISPLAY[1, "label"], "V|V (fixed)")
  init_globals()
  VARS = ""
  DEPRECATED = ""
}

function test_format_documentation() {
  init_globals()
  VARS = 1
  DEPRECATED = 1
  OFFSET = 2
  PADDING = "."
  add_anchor("variable", "VAR", "##", " v", " S")
  add_anchor("target", "t", "##", " doc", "")
  prepare_rendering()
  check("format_documentation: the targets, then the variables (no colors)",
        format_documentation(),
        "------------------\n" \
        "Available targets:\n" \
        "------------------\n" \
        "t..   doc\n" \
        "\n" \
        "------------------\n" \
        "Variables:\n" \
        "------------------\n" \
        " S\n" \
        "VAR   v\n" \
        "------------------\n")

  init_globals()
  check("format_documentation: nothing displayed", format_documentation(), "")
  VARS = DEPRECATED = OFFSET = PADDING = ""
}

# initialize the colors as init_globals() and process_options() do (with the default color
# options)
function setup_colors(output_format, export_theme) {
  define_ansi_to_html_colors() # the default colors, without the theme of a previous call
  OUTPUT_FORMAT = output_format
  EXPORT_THEME = export_theme
  COLOR_DEFAULT = COLOR_ATTENTION = COLOR_DEPRECATED = ""
  COLOR_SECTION = COLOR_BACKTICKS = ""
  COLOR = 1
  initialize_colors()
}

function test_default_color_option() {
  if ("NO_COLOR" in ENVIRON) {
    delete ENVIRON["NO_COLOR"] # the tests run without it in their environment
  }
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
        "\\textcolor{makefile-doc-default}{")
  check("define_color (LATEX): background", define_color(44, "BACKTICKS"),
        "\\bgcolor{makefile-doc-backticks}{")
  check("define_color (LATEX): attribute", define_color(1, "BACKTICKS"), "\\textbf{")
  check("define_color (LATEX): reset", define_color(-1), "}")

  setup_colors("", "")
}

function test_export_theme() {
  init_globals()
  setup_colors("HTML", "")
  check("export theme: no FG by default", EXPORT_FG_BG["FG"], "")
  check("export theme: no BG by default", EXPORT_FG_BG["BG"], "")
  check("export theme: default (solarized) blue", EXPORT_PALETTE[34], "268bd2")

  setup_colors("HTML", "32:d33682,,FG:000000,BG:AAAAAA")
  check("export theme: color", EXPORT_PALETTE[32], "d33682")
  check("export theme: FG", EXPORT_FG_BG["FG"], "000000")
  check("export theme: BG", EXPORT_FG_BG["BG"], "AAAAAA")
  check("export theme: the background of a color is set separately",
        EXPORT_PALETTE[42], "859900")
  check("export theme: valid and empty entries are not errors", OPTION_ERRORS, 0)

  setup_colors("HTML", "3:ffffff,5:123456,34:fff")
  check("export theme: invalid entries are errors",
        stderr_text(),
        "ERROR: EXPORT_THEME: '3:ffffff' should start with FG, BG or one of " \
        "30-37, 40-47, 90-97, 100-107\n" \
        "ERROR: EXPORT_THEME: '5:123456' should start with FG, BG or one of " \
        "30-37, 40-47, 90-97, 100-107\n" \
        "ERROR: EXPORT_THEME: '34:fff' should end with a color of 6 hex digits\n")
  check("export theme: attributes (0-9) cannot be changed", ANSI_TO_HTML_VALUE[3], "italic")
  check_true("export theme: unsupported parameters are not added", !(5 in EXPORT_PALETTE))
  check("export theme: an invalid entry keeps the default", EXPORT_PALETTE[34], "268bd2")

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
  check("html_box_style: without FG and BG",
        html_box_style(), "  .makefile-doc { display: inline-block; }\n")

  setup_colors("HTML", "BG:000000")
  check("html_box_style: BG",
        html_box_style(), "  .makefile-doc { display: inline-block; background-color: #000000; }\n")

  setup_colors("HTML", "FG:ffffff,BG:000000")
  check("html_box_style: FG and BG",
        html_box_style(),
        "  .makefile-doc { display: inline-block; color: #ffffff; background-color: #000000; }\n")

  setup_colors("", "")
}

BEGIN {
  test_substitute_backticks_patterns()
  test_escape_for_latex_output()
  test_escape_for_html_output()
  test_prepare_rendering()
  test_format_documentation()
  test_default_color_option()
  test_validate_ansi_param()
  test_is_bool_is_hex_color()
  test_define_color()
  test_export_theme()
  test_ansi_color_param_to_html_style()
  done()
}
