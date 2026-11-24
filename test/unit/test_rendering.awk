# Check the section Rendering of the script: what is displayed (prepare_rendering), and
# its layout (format_documentation).

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

function test_display_name(    labels) {
  form_substitutions("<A:1>$(D):out;<A:1>out/:o/;/a:/X", DSUB_PARAM, labels, DSUB_VALUES,
                     DSUB_NAMES, 1)
  DSUB_COUNT = length_array_posix(DSUB_NAMES)
  check("display_name: replaced in the order given", display_name("$(D)/a"), "o/a")
  check("display_name: every occurrence", display_name("$(D)/a $(D)/b"), "o/a o/b")
  check("display_name: a name without the text", display_name("plain"), "plain")
  SUB_LABELS["$(D)/a"] = "label"
  check("display_name: a SUB label wins", display_name("$(D)/a"), "label")
  init_globals()
}

BEGIN {
  test_substitute_backticks_patterns()
  test_prepare_rendering()
  test_format_documentation()
  test_display_name()
  done()
}
