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
#  - the observations of the line, when -v TRACE_OBS=N is given (N > 0): its non-empty fields,
#    N per row (a flag is shown only when it is on)
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
# With -v TRACE_OBS=N (N>0), the observations of a logical line follow its last physical line, on a
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

  # ------------------------------------------------------------------------------------------------
  # the observations defined in parser_structure
  # in addition parser_observe defines: "first_char" "inline" "inline_doc" "text" "tag" "prefix"
  # ------------------------------------------------------------------------------------------------
  TRACE_STRUCTURE_COUNT = split("line_kind anchor_kind anchor_name comment override " \
                                "operator value double grouped", TRACE_STRUCTURE_FIELDS, " ")
  # ------------------------------------------------------------------------------------------------
}

function trace_print(k, joined, prefix) { #locals
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

  if (TRACE_OBS > 0 && !joined) {
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

function trace_print_obs(obs, k,
                         line, j, key, n, numb_obs_per_line) { #locals
  if (k == "neutral" || k == "recipe") {
    return
  }

  # show the observations in batches of TRACE_OBS
  line = ""
  n = 0
  for (j = 1; j <= TRACE_STRUCTURE_COUNT; j++) {
    key = TRACE_STRUCTURE_FIELDS[j]
    if (array_get(obs, key) == "" ||
        (key ~ /^(inline|double|grouped|override)$/ && obs[key] == 0)) {
      continue # empty, or a flag that is off
    }

    line = trace_obj_field(line, key, obs[key])
    if (++n % TRACE_OBS == 0) {
      printf("%4d ============ ->%s\n", TRACE_LINE, line)
      line = ""
    }
  }

  # print the last row when it has fewer than TRACE_OBS fields
  if (line != "") {
    printf("%4d ============ ->%s\n", TRACE_LINE, line)
  }
}

function trace_obj_field(line, key, value) {
  return line " " key ":[" string_replace("\t", "\\t", value) "]"
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
