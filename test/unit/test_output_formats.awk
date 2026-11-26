# Check the section Output formats of the script: colors, themes, escapes, and the
# functions fmt_* that rendering calls.

function test_html_escape() {
  check("html_escape: <, > and &", html_escape("AWK=<variant> & co"),
        "AWK=&lt;variant&gt; &amp; co")
  check("html_escape: & is escaped only once", html_escape("&lt;"), "&amp;lt;")
}

function test_latex_escape() {
  check("latex_escape: braces", latex_escape("this is {a test} string"),
        "this is \\{a test\\} string")
  check("latex_escape: backslash", latex_escape("a \\n b"), "a \\textbackslash{}n b")
  check("latex_escape: backslash next to braces", latex_escape("\\{x}"),
        "\\textbackslash{}\\{x\\}")
}

function test_fmt_escape() {
  OUTPUT_FORMAT = "ANSI"
  check("fmt_escape (ANSI): unchanged", fmt_escape("<a> & {b} \\"), "<a> & {b} \\")
  OUTPUT_FORMAT = "HTML"
  check("fmt_escape (HTML): the HTML escapes only", fmt_escape("<a> & {b} \\"),
        "&lt;a&gt; &amp; {b} \\")
  OUTPUT_FORMAT = "LATEX"
  check("fmt_escape (LATEX): the LaTeX escapes only", fmt_escape("<a> & {b} \\"),
        "<a> & \\{b\\} \\textbackslash{}")
  OUTPUT_FORMAT = ""
}

function test_fmt_color() {
  OUTPUT_FORMAT = "HTML"
  COLOR_RESET_CODE = "</>"
  check("fmt_color: each line on its own, not the empty ones", fmt_color("a\n\nb", "<c>"),
        "<c>a</>\n\n<c>b</>")
  check("fmt_color: no color code, no change", fmt_color("a\nb", ""), "a\nb")
  check("fmt_color (HTML): a reset inside is kept as is", fmt_color("x<y>z</>w", "<c>"),
        "<c>x<y>z</>w</>")
  OUTPUT_FORMAT = "ANSI"
  COLOR_RESET_CODE = "\033[0m"
  check("fmt_color (ANSI): the color is restored after a reset inside",
        fmt_color("x\033[33mz\033[0mw", "\033[32m"),
        "\033[32mx\033[33mz\033[0m\033[32mw\033[0m")
  OUTPUT_FORMAT = ""
  COLOR_RESET_CODE = ""
}

function test_fmt_document() {
  init_globals()
  OUTPUT_HEADER = "<h>\n"
  OUTPUT_FOOTER = "</h>\n"
  OUTPUT_FORMAT = "HTML"
  check("fmt_document: the body between the header and the footer", fmt_document("a\n"),
        "<h>\na\n</h>\n")
  OUTPUT_FORMAT = "LATEX"
  COLOR_RESET_CODE = "}"
  EXPORT_FG_BG["FG"] = "111111"
  check("fmt_document (LATEX): FG on each line", fmt_document("a\n"),
        "<h>\n\\textcolor{makefile-doc-fg}{a}\n</h>\n")
  OUTPUT_FORMAT = ""
  init_globals()
}

# initialize the colors as init_globals() and opt_process() do (with the default color
# options)
function setup_colors(output_format, export_theme) {
  define_ansi_to_html_colors() # the default colors, without the theme of a previous call
  OUTPUT_FORMAT = output_format
  EXPORT_THEME = export_theme
  COLOR_DEFAULT = COLOR_ATTENTION = COLOR_DEPRECATED = ""
  COLOR_SECTION = COLOR_BACKTICKS = ""
  COLOR = 1
  opt_colors()
  initialize_color_codes()
}

function test_opt_default_color() {
  if ("NO_COLOR" in ENVIRON) {
    delete ENVIRON["NO_COLOR"] # the tests run without it in their environment
  }
  check("opt_default_color: colors without NO_COLOR", opt_default_color(), 1)
  ENVIRON["NO_COLOR"] = ""
  check("opt_default_color: colors with an empty NO_COLOR", opt_default_color(), 1)
  ENVIRON["NO_COLOR"] = "1"
  check("opt_default_color: no colors with NO_COLOR=1", opt_default_color(), 0)
  delete ENVIRON["NO_COLOR"]
}

function test_opt_ansi_param(message) { #locals
  init_globals()
  setup_colors("ANSI", "")
  check("opt_ansi_param: color", opt_ansi_param("COLOR_X", 34), 34)
  check("opt_ansi_param: attribute", opt_ansi_param("COLOR_X", 9), 9)
  check("opt_ansi_param: bright background", opt_ansi_param("COLOR_X", 107), 107)
  check("opt_ansi_param: 0 (no color)", opt_ansi_param("COLOR_X", 0), 0)
  check("opt_ansi_param: valid parameters are not errors", OPTION_ERRORS, 0)

  message = "ERROR: COLOR_X should be one of 0, 1, 3, 4, 9, 30-37, 40-47, 90-97, 100-107\n"
  check("opt_ansi_param: unsupported attribute", opt_ansi_param("COLOR_X", 2), 0)
  check("opt_ansi_param: unsupported attribute is an error", stderr_text(), message)
  check("opt_ansi_param: out of range", opt_ansi_param("COLOR_X", 108), 0)
  check("opt_ansi_param: not a number", opt_ansi_param("COLOR_X", "abc"), 0)
  check("opt_ansi_param: compound parameter", opt_ansi_param("COLOR_X", "1;34"), 0)
  check("opt_ansi_param: FG is not a color parameter",
        opt_ansi_param("COLOR_X", "FG"), 0)
  check("opt_ansi_param: the other errors", stderr_text(), message message message message)
  check("opt_ansi_param: every error is counted", OPTION_ERRORS, 5)
}

function test_fmt_color_code() {
  setup_colors("ANSI", "")
  check("fmt_color_code (ANSI): color", fmt_color_code(34, "DEFAULT"), "\033[34m")
  check("fmt_color_code (ANSI): reset", fmt_color_code(-1), "\033[0m")
  check("fmt_color_code (ANSI): no color", fmt_color_code(0, "DEFAULT"), "")

  setup_colors("HTML", "")
  check("fmt_color_code (HTML): color", fmt_color_code(34, "DEFAULT"),
        "<span class=\"makefile-doc-default\">")
  check("fmt_color_code (HTML): reset", fmt_color_code(-1), "</span>")

  setup_colors("LATEX", "")
  check("fmt_color_code (LATEX): color", fmt_color_code(34, "DEFAULT"),
        "\\textcolor{makefile-doc-default}{")
  check("fmt_color_code (LATEX): background", fmt_color_code(44, "BACKTICKS"),
        "\\bgcolor{makefile-doc-backticks}{")
  check("fmt_color_code (LATEX): attribute", fmt_color_code(1, "BACKTICKS"), "\\textbf{")
  check("fmt_color_code (LATEX): reset", fmt_color_code(-1), "}")

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
  test_html_escape()
  test_latex_escape()
  test_fmt_escape()
  test_fmt_color()
  test_fmt_document()
  test_opt_default_color()
  test_opt_ansi_param()
  test_fmt_color_code()
  test_export_theme()
  test_ansi_color_param_to_html_style()
  done()
}
