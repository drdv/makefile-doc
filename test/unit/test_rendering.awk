# Check the section Rendering of the script: what is displayed (prepare_rendering), and
# its layout (format_documentation).

# ---------------------------------------------------------------------------------------
# interface -> DISPLAY: what is displayed (prepare_rendering)
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

function test_display_name(    labels) {
  form_substitutions("<A:1>$(D):out;<A:1>out/:o/;/a:/X", 1, DSUB_PARAM, labels, DSUB_VALUES,
                     DSUB_NAMES)
  DSUB_COUNT = length_array_posix(DSUB_NAMES)
  check("display_name: replaced in the order given", display_name("$(D)/a"), "o/a")
  check("display_name: every occurrence", display_name("$(D)/a $(D)/b"), "o/a o/b")
  check("display_name: a name without the text", display_name("plain"), "plain")
  SUB_LABELS["$(D)/a"] = "label"
  check("display_name: a SUB label wins", display_name("$(D)/a"), "label")
  init_globals()
}

# ---------------------------------------------------------------------------------------
# DISPLAY -> text: the layout (format_documentation)
# ---------------------------------------------------------------------------------------

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

# display_substitutions: the values of a SUB, with the parameters of its row of SUB_PARAM
function test_display_substitutions(    labels, values, names) {
  init_globals()
  OFFSET = 2
  check("display_substitutions: no values", display_substitutions("", "", 1), "\n")
  check("display_substitutions: the defaults (one value per line, on the next lines)",
        display_substitutions("a b", "", 1), "\n    a\n    b\n")
  form_substitutions("<L:0,M:0,I:{,T:},S:\\,>t:a b c;<N:2>u:a b c", 0, SUB_PARAM, labels, values,
                     names)
  check("display_substitutions: L:0, M:0, I, T and S", display_substitutions("a b c", "t", 1),
        " {a, b, c}\n")
  check("display_substitutions: N", display_substitutions("a b c", "u", 1), "\n    a\n    b\n")
  OFFSET = ""
  init_globals()
}

# format_doc: the doc after the name, its lines aligned
function test_format_doc() {
  init_globals()
  OFFSET = 2
  check("format_doc: the lines aligned with the first one (width 1)",
        format_doc(" a\n b", 1), "   a\n    b")
  OUTPUT_FORMAT = "HTML"
  COLOR_BACKTICKS = 1
  COLOR_BACKTICKS_CODE = "<b>"
  COLOR_RESET_CODE = "</b>"
  check("format_doc: a span in backticks across lines does not color the indentation",
        format_doc(" see `foo\n bar` here", 1), "   see <b>foo</b>\n   <b> bar</b> here")
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

# format_anchor: one DISPLAY record in, its text out (no colors)
function test_format_anchor() {
  init_globals()
  OFFSET = 2
  PADDING = "."
  display_record("t", "##", " doc")
  check("format_anchor: the label padded to the width, then the doc", format_anchor(1, 3),
        "t..   doc\n")
  DISPLAY[1, "doc"] = " line 1\n line 2"
  check("format_anchor: the next lines of the doc are aligned with the first one",
        format_anchor(1, 3), "t..   line 1\n      line 2\n")
  DISPLAY[1, "section"] = " S"
  DISPLAY[1, "doc"] = " doc"
  check("format_anchor: the section above", format_anchor(1, 3), " S\nt..   doc\n")
  DISPLAY[1, "section"] = ""
  check("format_anchor: an empty section is a blank line", format_anchor(1, 3),
        "\nt..   doc\n")
  DISPLAY[1, "values"] = "a b"
  delete DISPLAY[1, "section"]
  check("format_anchor: the SUB values after the doc", format_anchor(1, 3),
        "t..   doc\n      a\n      b\n")
  OFFSET = PADDING = ""
  init_globals()
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

BEGIN {
  # interface -> DISPLAY: what is displayed (prepare_rendering)
  test_prepare_rendering()
  test_display_name()

  # DISPLAY -> text: the layout (format_documentation)
  test_substitute_backticks_patterns()
  test_format_doc()
  test_display_substitutions()
  test_format_anchor()
  test_format_documentation()
  done()
}
