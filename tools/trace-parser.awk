# Print the state of the new parser (parser.awk) after each input line, in the format of
# tools/trace-state.awk, to compare it with the current parser. Load it before the script and
# the new parser, so that its rule sees each line first (its END runs first, and its exit skips
# the END of the script):
#   awk -f tools/trace-parser.awk -f makefile-doc.awk -f parser.awk Makefile
# The names of the anchors are shown as the current parser shows them: blanks collapsed, a &
# after grouped targets, ~N after the documented rules of a double-colon target.
# With -v TRACE_OBS=1, the observation of each logical line (but neutral ones) is printed
# after its state line, e.g.:
#      6 ============ -> <assignment> variable:[SRCS] operator:[:=] value:[s.c]
# Without it, the output can be diffed with that of tools/trace-state.awk.

BEGIN {
  TRACE_PARSER_STARTED = 0
  if (TRACE_OBS == "") {
    TRACE_OBS = 0
  }
}

{
  if (!TRACE_PARSER_STARTED) { # after the BEGIN of the script (RECIPEPREFIX is processed)
    lexical_init(TRACE_PARSER_STATE, RECIPEPREFIX)
    TRACE_PARSER_STARTED = 1
  }
  if (FNR == 1) {
    lexical_file_start(TRACE_PARSER_STATE)
    print "== " (FILENAME == "" ? "-" : FILENAME)
  }
  if (lexical_join(TRACE_PARSER_STATE, $0)) {
    lexical_obs(TRACE_PARSER_STATE["line"], TRACE_PARSER_STATE, TRACE_PARSER_OBS)
    lexical_step(TRACE_PARSER_STATE, TRACE_PARSER_OBS)
    trace_parser_print(0)
    if (TRACE_OBS) {
      trace_parser_print_obs(TRACE_PARSER_OBS)
    }
    if (TRACE_PARSER_OBS["attach"]) {
      printf("%4d ============ => %s:[%s]%s\n", FNR, TRACE_PARSER_OBS["anchor"],
             trace_parser_name(TRACE_PARSER_OBS),
             TRACE_PARSER_OBS["with_section"] ? " +section" : "")
    }
  } else {
    trace_parser_print(1)
  }
}

# print the current line with the state after it
function trace_parser_print(joined, #locals
                            text, prefix) {
  text = $0
  sub(/\r$/, "", text)
  text = string_replace("\t", "\\t", text)
  prefix = TRACE_PARSER_STATE["c"] == "\t" ? "\\t" : TRACE_PARSER_STATE["c"]
  printf("%4d %d %d %2d %2d %-2s |%s\n", FNR, joined, TRACE_PARSER_STATE["r"],
         TRACE_PARSER_STATE["dn"], TRACE_PARSER_STATE["sn"], prefix,
         text == "" ? "" : " " text)
}

# print an observation (not for neutral lines): <kind>, then its string fields as key:[value]
# in the order of the line (the anchor is the key of the name), then its flags
function trace_parser_print_obs(obs, #locals
                                line) {
  if (obs["kind"] == "neutral") {
    return
  }
  line = sprintf("%4d ============ -> <%s>", FNR, obs["kind"])
  if (obs["anchor"] != "") {
    line = line trace_parser_field(obs["anchor"], obs["name"])
  }
  if (obs["operator"] != "") {
    line = line trace_parser_field("operator", obs["operator"]) \
                trace_parser_field("value", obs["value"])
  }
  if (obs["comment"] != "") {
    line = line trace_parser_field("comment", obs["comment"])
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
  print line
}

# a field of an observation, as key:[value] (tabs shown as \t)
function trace_parser_field(key, value) {
  return " " key ":[" string_replace("\t", "\\t", value) "]"
}

# the name of an anchor, as the current parser shows it
function trace_parser_name(obs, #locals
                           name) {
  name = obs["name"]
  gsub(/[ \t]+/, " ", name)
  if (obs["grouped"]) {
    name = name "&"
  }
  if (obs["double"]) {
    name = name "~" (++TRACE_PARSER_DOUBLE[name])
  }
  return name
}

END {
  exit
}
