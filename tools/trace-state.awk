# Print the state of the parser of makefile-doc.awk after each input line, instead of the
# help. Load it before the script, so that its rule sees each line before the script parses
# it, i.e., with the state that the previous line left (its END runs first, and its exit
# skips the END of the script):
#   awk -f tools/trace-state.awk -f makefile-doc.awk Makefile
# This assumes that the script reads its input only through the main loop of awk (no
# getline): a line read otherwise would not be seen here.
#
# The fields are the state of the model of the parser (misc/docs/parser-model.tex), in terms
# of Make, not of the variables of the script, so that another parser can produce the same
# trace. Each file starts with a header line
#   == FILE
# (stdin is -; an empty file has no line, so it has no header), then one line per physical
# input line:
#   LINE J R D S C | TEXT
# with the state from the line on (the effect of the line included):
#   J     1 if the line is joined with the next one (a backslash continuation, recipe lines
#         included: the joined line takes effect at its last physical line), 0 otherwise
#   R     1 if a rule is open (a line that starts with the recipe prefix is a recipe line),
#         0 otherwise
#   D     the number of pending doc lines (waiting for their anchor)
#   S     the number of pending section lines
#   C     the recipe prefix (a tab is shown as \t)
#   TEXT  the input line (a tab is shown as \t, a final \r is dropped); for an empty line,
#         nothing follows the | (no trailing space)
# Each anchor that the line documents follows it on a line of its own:
#   LINE ============ => KIND:NAME
# where KIND is target or variable, with " +section" when the pending section is placed
# before the anchor. `grep -e '^==' -e '=>'` lists the documented anchors of each file.

BEGIN {
  TRACE_PENDING = 0 # a line is waiting to be printed (at the next line, or at the end)
  TRACE_LINE = 0
  TRACE_TEXT = ""
  TRACE_ANCHOR_INDEX = 0 # the first entry of ANCHOR_ORDER not printed yet
}

# print the waiting line, with the state that the script left after parsing it, then the
# anchors that it documented
function trace_print(    k, kind_name, join_flag, rule_flag, prefix) {
  # the script does not join a continued recipe line: it reads it as a recipe line followed by
  # lines that continue it (IN_MULTILINE_BACKSLASH_RECIPE), shown here as a joined line
  join_flag = IN_CONTINUED_LINE || IN_MULTILINE_BACKSLASH_RECIPE ? 1 : 0
  rule_flag = IN_RULE != "" ? 1 : 0
  prefix = RECIPEPREFIX == "\t" ? "\\t" : RECIPEPREFIX
  printf("%4d %d %d %2d %2d %-2s |%s\n", TRACE_LINE, join_flag, rule_flag,
         DESCRIPTION_DATA_INDEX - 1, SECTION_DATA_INDEX - 1, prefix,
         TRACE_TEXT == "" ? "" : " " TRACE_TEXT)

  for (k = TRACE_ANCHOR_INDEX; k < ANCHOR_ORDER_INDEX; k++) {
    split(ANCHOR_ORDER[k], kind_name, SUBSEP)
    printf("%4d ============ => %s:%s%s\n", TRACE_LINE, kind_name[1], kind_name[2],
           (k in SECTION_BEFORE) ? " +section" : "")
  }
  TRACE_ANCHOR_INDEX = ANCHOR_ORDER_INDEX
}

{
  if (TRACE_PENDING) {
    trace_print()
  } else {
    TRACE_ANCHOR_INDEX = ANCHOR_ORDER_INDEX # the first line: nothing documented yet
  }
  if (FNR == 1) {
    print "== " (FILENAME == "" ? "-" : FILENAME)
  }
  TRACE_LINE = FNR
  TRACE_TEXT = $0
  sub(/\r$/, "", TRACE_TEXT)
  TRACE_TEXT = string_replace("\t", "\\t", TRACE_TEXT)
  TRACE_PENDING = 1
}

END {
  if (TRACE_PENDING) {
    trace_print()
  }
  exit
}
