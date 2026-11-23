# Print the state of the parser of makefile-doc.awk after each input line, instead of the
# help. Load it before the script, so that its rule sees each line before the script parses
# it, i.e., with the state that the previous line left (its END runs first, and its exit
# skips the END of the script):
#   awk -f tools/trace-state.awk -f makefile-doc.awk Makefile
#
# The fields describe the parse in terms of Make, not of the variables of the script, so
# that another parser can produce the same trace. One line per physical input line:
#   FILE:LINE JOIN RECIPE DOCS SECTION ATTACHED | TEXT
# with the state after the line:
#   JOIN      \ if the line is joined with the next one (a backslash continuation outside a
#             recipe: the joined line is parsed at its last physical line), . otherwise
#   RECIPE    - outside a rule, R in a rule (a line that starts with the recipe prefix is a
#             recipe line), R\ in a recipe line that continues on the next line
#   DOCS      the number of pending doc lines (waiting for their anchor)
#   SECTION   the number of pending section lines
#   ATTACHED  the anchors that the line documented, each as [KIND:NAME] (KIND is target or
#             variable), with " +section" when the pending section is placed before it;
#             - if none
#   TEXT      the input line (a tab is shown as \t, a final \r is dropped)

BEGIN {
  trace_pending = 0 # a line is waiting to be printed (at the next line, or at the end)
  trace_file = ""
  trace_line = 0
  trace_text = ""
  trace_anchor_index = 0 # the first entry of ANCHOR_ORDER not printed yet
}

# print the waiting line, with the state that the script left after parsing it
function trace_print(    k, kind_name, attached, join_mark, recipe_mark) {
  attached = ""
  for (k = trace_anchor_index; k < ANCHOR_ORDER_INDEX; k++) {
    split(ANCHOR_ORDER[k], kind_name, SUBSEP)
    attached = attached (attached == "" ? "" : " ") "[" kind_name[1] ":" kind_name[2] \
               ((k in SECTION_BEFORE) ? " +section" : "") "]"
  }
  trace_anchor_index = ANCHOR_ORDER_INDEX

  join_mark = IN_CONTINUED_LINE ? "\\" : "."
  recipe_mark = IN_MULTILINE_BACKSLASH_RECIPE ? "R\\" : (IN_RULE != "" ? "R" : "-")
  printf("%s:%d %s %s %d %d %s | %s\n", trace_file, trace_line, join_mark, recipe_mark,
         DESCRIPTION_DATA_INDEX - 1, SECTION_DATA_INDEX - 1,
         attached == "" ? "-" : attached, trace_text)
}

{
  if (trace_pending) {
    trace_print()
  } else {
    trace_anchor_index = ANCHOR_ORDER_INDEX # the first line: nothing documented yet
  }
  trace_file = FILENAME == "" ? "-" : FILENAME
  trace_line = FNR
  trace_text = $0
  sub(/\r$/, "", trace_text)
  trace_text = string_replace("\t", "\\t", trace_text)
  trace_pending = 1
}

END {
  if (trace_pending) {
    trace_print()
  }
  exit
}
