# Check the section Rendering of the script: what is displayed (render_prepare), and
# its layout (render_documentation).

# ---------------------------------------------------------------------------------------
# interface -> DISPLAY: what is displayed (render_prepare)
# ---------------------------------------------------------------------------------------

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
function displayed_names(k, names) { #locals
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

function test_render_prepare() {
  init_globals()
  VARS = 1
  DEPRECATED = 1
  add_anchors()
  render_prepare()
  check("render_prepare: the targets, then the variables, each once, in file order",
        displayed_names(), "t old V")
  check("render_prepare: the last definition gives the doc and tag",
        DISPLAY[1, "doc"] " " DISPLAY[1, "tag"], " second ##!")
  check("render_prepare: a section goes to the next displayed anchor",
        DISPLAY[3, "section"] DISPLAY[2, "section"], " S1 S2")

  init_globals()
  VARS = 0
  DEPRECATED = 0
  add_anchors()
  render_prepare()
  check("render_prepare: hidden anchors are left out", displayed_names(), "t")
  check("render_prepare: a section skips hidden anchors of its kind, not other kinds",
        DISPLAY[1, "section"], " S2")

  init_globals()
  VARS = 0
  DEPRECATED = 1
  add_anchor("variable", "V", "##", " v", " S")
  add_anchor("target", "t", "##", " doc", "")
  render_prepare()
  check("render_prepare: the section of a hidden variable does not go to a target",
        ("1", "section") in DISPLAY, 0)

  init_globals()
  VARS = 1
  DEPRECATED = 0
  add_anchor("target", "old", "##%", " deprecated", " S1")
  add_anchor("target", "t1", "##", " one", " S2")
  add_anchor("target", "t2", "##", " two", "")
  render_prepare()
  check("render_prepare: a section with no displayed anchor before the next one is dropped",
        DISPLAY[1, "section"] "|" (("2", "section") in DISPLAY), " S2|0")

  init_globals()
  VARS = 1
  DEPRECATED = 1
  SUB_LABELS["t"] = "T"
  SUB_VALUES["t"] = "a b"
  add_anchor("target", "t", "##", " doc", "")
  render_prepare()
  check("render_prepare: the displayed name and the SUB values",
        DISPLAY[1, "name"] " " DISPLAY[1, "values"], "T a b")
  check("render_prepare: the label is the displayed name", DISPLAY[1, "label"], "T")

  init_globals()
  add_anchor("variable", "V", "##", " doc", "")
  ANCHORS[ANCHOR_COUNT, "override"] = 1
  render_prepare()
  check("render_prepare: the label of a variable set with override",
        DISPLAY[1, "name"] "|" DISPLAY[1, "label"], "V|V (fixed)")
  init_globals()
  VARS = ""
  DEPRECATED = ""
}

function test_render_display_name(labels) { #locals
  opt_form_substitutions("<A:1>$(D):out;<A:1>out/:o/;/a:/X", 1, DSUB_PARAM, labels, DSUB_VALUES,
                         DSUB_NAMES)
  DSUB_COUNT = array_length(DSUB_NAMES)
  check("render_display_name: replaced in the order given", render_display_name("$(D)/a"), "o/a")
  check("render_display_name: every occurrence", render_display_name("$(D)/a $(D)/b"), "o/a o/b")
  check("render_display_name: a name without the text", render_display_name("plain"), "plain")
  SUB_LABELS["$(D)/a"] = "label"
  check("render_display_name: a SUB label wins", render_display_name("$(D)/a"), "label")
  init_globals()
}

# ---------------------------------------------------------------------------------------
# DISPLAY -> text: the layout (render_documentation)
# ---------------------------------------------------------------------------------------

function test_render_substitute_backticks() {
  COLOR_BACKTICKS_CODE = ">>>"
  COLOR_RESET_CODE = "<<<"

  check("render_substitute_backticks: two regions",
        render_substitute_backticks("this `is` a test `x` and"),
        "this >>>is<<< a test >>>x<<< and")
  check("render_substitute_backticks: regions are paired from the left",
        render_substitute_backticks("`this `is` a test `x` and`"),
        ">>>this <<<is>>> a test <<<x>>> and<<<")
  check("render_substitute_backticks: inside braces",
        render_substitute_backticks("{`1`, `2`, `3`}"),
        "{>>>1<<<, >>>2<<<, >>>3<<<}")
  check("render_substitute_backticks: region with a space",
        render_substitute_backticks("empty ` ` region"),
        "empty >>> <<< region")
  check("render_substitute_backticks: empty region is left as is",
        render_substitute_backticks("empty `` region"),
        "empty `` region")
}

# render_sub_values: the values of a SUB, with the parameters of its row of SUB_PARAM
function test_render_sub_values(labels, values, names) { #locals
  init_globals()
  OFFSET = 3
  check("render_sub_values: no values", render_sub_values("", "", 1), "\n")
  check("render_sub_values: the defaults (one value per line, on the next lines)",
        render_sub_values("a b", "", 1), "\n    a\n    b\n")
  opt_form_substitutions("<L:0,M:0,I:{,T:},S:\\,>t:a b c;<N:2>u:a b c", 0, SUB_PARAM, labels,
                         values, names)
  check("render_sub_values: L:0, M:0, I, T and S", render_sub_values("a b c", "t", 1),
        " {a, b, c}\n")
  check("render_sub_values: N", render_sub_values("a b c", "u", 1), "\n    a\n    b\n")
  OFFSET = ""
  init_globals()
}

# render_doc: the doc after the name, its lines aligned
function test_render_doc() {
  init_globals()
  OFFSET = 3
  check("render_doc: the lines aligned with the first one (width 1)",
        render_doc("a\nb", 1), "   a\n    b")
  OUTPUT_FORMAT = "HTML"
  COLOR_BACKTICKS = 1
  COLOR_BACKTICKS_CODE = "<b>"
  COLOR_RESET_CODE = "</b>"
  check("render_doc: a span in backticks across lines does not color the indentation",
        render_doc("see `foo\nbar` here", 1), "   see <b>foo</b>\n    <b>bar</b> here")
  OFFSET = OUTPUT_FORMAT = COLOR_BACKTICKS = ""
  init_globals()
}

# one DISPLAY record (no section, no SUB values)
function display_record(label, tag, doc) {
  DISPLAY_COUNT = 1
  DISPLAY[1, "label"] = label
  DISPLAY[1, "tag"] = tag
  DISPLAY[1, "doc"] = doc
  DISPLAY[1, "values"] = ""
  DISPLAY[1, "sub_row"] = ""
}

# render_anchor: one DISPLAY record in, its text out (no colors)
function test_render_anchor() {
  init_globals()
  OFFSET = 3
  PADDING = "."
  display_record("t", "##", "doc")
  check("render_anchor: the label padded to the width, then the doc", render_anchor(1, 3),
        "t..   doc\n")
  DISPLAY[1, "doc"] = "line 1\nline 2"
  check("render_anchor: the next lines of the doc are aligned with the first one",
        render_anchor(1, 3), "t..   line 1\n      line 2\n")
  DISPLAY[1, "section"] = "S"
  DISPLAY[1, "doc"] = "doc"
  check("render_anchor: the section above", render_anchor(1, 3), "S\nt..   doc\n")
  DISPLAY[1, "section"] = ""
  check("render_anchor: an empty section is a blank line", render_anchor(1, 3),
        "\nt..   doc\n")
  DISPLAY[1, "values"] = "a b"
  delete DISPLAY[1, "section"]
  check("render_anchor: the SUB values after the doc", render_anchor(1, 3),
        "t..   doc\n      a\n      b\n")
  OFFSET = PADDING = ""
  init_globals()
}

function test_render_documentation() {
  init_globals()
  VARS = 1
  DEPRECATED = 1
  OFFSET = 3
  PADDING = "."
  add_anchor("variable", "VAR", "##", "v", "S")
  add_anchor("target", "t", "##", "doc", "")
  render_prepare()
  check("render_documentation: the targets, then the variables (no colors)",
        render_documentation(),
        "------------------\n" \
        "Available targets:\n" \
        "------------------\n" \
        "t..   doc\n" \
        "\n" \
        "------------------\n" \
        "Variables:\n" \
        "------------------\n" \
        "S\n" \
        "VAR   v\n" \
        "------------------\n")

  init_globals()
  check("render_documentation: nothing displayed", render_documentation(), "")
  VARS = DEPRECATED = OFFSET = PADDING = ""
}

BEGIN {
  # interface -> DISPLAY: what is displayed (render_prepare)
  test_render_prepare()
  test_render_display_name()

  # DISPLAY -> text: the layout (render_documentation)
  test_render_substitute_backticks()
  test_render_doc()
  test_render_sub_values()
  test_render_anchor()
  test_render_documentation()
  done()
}
