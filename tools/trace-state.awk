# Print, after each input line (see misc/docs/parser-model.tex):
#  1. its line number in the file
#  2. whether the line is joined with the next one
#  3. whether a rule is open, i.e.,
#     a line that starts with the recipe prefix is a recipe line (r_i)
#  4. the number of lines in the pending doc D_i
#  5. the number of lines in the pending section S_i
#  6. the recipe prefix (p_i)
#  7. the text of the line
# followed by:
#  - the observations of the line (when -v TRACE_OBS=1 is set)
#  - the anchor that the line documented, if any
#
# trace-state.awk should be loaded before the script, so that its rule sees each line before the
# script parses it, i.e., with the state and the memory that the previous line left (its END runs
# first, and its exit skips the END of makefile-doc.awk):
#
#   awk -f tools/trace-state.awk -f makefile-doc.awk Makefile
#
# This assumes that makefile-doc.awk reads its input only through the main loop of awk (no
# getline) -- which is the case.
#
# Fields 3 and 6 are part of the state of the parser, fields 4 and 5 are the sizes of its memory,
# and field 2 is outside the model (the joining of lines).
#
# The anchor that a line documents follows it on a line of its own:
#
#   ... ============ => KIND:[NAME]
#
# where KIND is target or variable, followed by +section when the pending section is placed before
# the anchor. Each file starts with a header line (stdin is -).
#
#  `grep -e '^==' -e '=>'`
#
# lists the documented anchors of each file.
#
# With -v TRACE_OBS=1, the observations of a logical line follow its last physical line, on a
# line of their own:
#
#   ... ============ -> <KIND> key:[value]... flags
#
# where KIND is the kind of the line (k_i). Only the observations of the structure are shown (not
# those added by parser_observe, e.g., the tag and the text of a doc line); none for a neutral line,
# and only <recipe> for a recipe line.

BEGIN {
  TRACE_PENDING = 0 # a line is waiting to be printed (at the next line, or at the end)
  TRACE_LINE = 0
  TRACE_TEXT = ""
  TRACE_ANCHOR_INDEX = 0 # the number of entries of ANCHORS printed
  if (TRACE_OBS == "") {
    TRACE_OBS = 0
  }
}

function trace_print(    k, joined, prefix) {
  joined = PARSER_JOINER["joining"] ? 1 : 0
  prefix = PARSER_STATE["p"] == "\t" ? "\\t" : PARSER_STATE["p"]
  printf("%4d %d %d %2d %2d %-2s |%s\n",
         TRACE_LINE,
         joined,
         PARSER_STATE["r"],
         PARSER_MEMORY["dn"],
         PARSER_MEMORY["sn"],
         prefix,
         TRACE_TEXT == "" ? "" : " " TRACE_TEXT)

  if (TRACE_OBS && !joined) {
    trace_print_obs(PARSER_OBS, PARSER_DERIVED["k"])
  }

  if (ANCHOR_COUNT > TRACE_ANCHOR_INDEX) {
    printf("%4d ============ => %s:[%s]%s\n",
           TRACE_LINE,
           ANCHORS[ANCHOR_COUNT, "kind"],
           ANCHORS[ANCHOR_COUNT, "name"],
           ((ANCHOR_COUNT, "section") in ANCHORS) ? " +section" : "")
  }
  TRACE_ANCHOR_INDEX = ANCHOR_COUNT
}

function trace_print_obs(obs, k, #locals
                         line) {
  if (k == "neutral") {
    return
  }
  line = sprintf("%4d ============ -> <%s>", TRACE_LINE, k)
  if (k == "recipe") {
    print line
    return
  }
  if (obs["anchor_kind"] != "") {
    line = line trace_field(obs["anchor_kind"], obs["anchor_name"])
  }
  if (obs["operator"] != "") {
    line = line trace_field("operator", obs["operator"]) trace_field("value", obs["value"])
  }
  if (obs["comment"] != "") {
    line = line trace_field("comment", obs["comment"])
  }
  if (obs["double"]) {
    line = line " double"
  }
  if (obs["grouped"]) {
    line = line " grouped"
  }
  if (obs["inline"]) {
    line = line " inline"
  }
  if (("override" in obs) && obs["override"]) {
    line = line " override"
  }
  print line
}

function trace_field(key, value) {
  return " " key ":[" string_replace("\t", "\\t", value) "]"
}

{
  if (TRACE_PENDING) {
    trace_print()
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
