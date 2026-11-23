# Run the script with the new parser (parser.awk) in place of the current one. Load it before
# the script and the new parser, so that its rule sees each line first and ends with `next`
# (the parsing rules of the script never run; its BEGIN and END do):
#   awk -f tools/drive-parser.awk -f makefile-doc.awk -f parser.awk Makefile
# The parser tells what each line is; this driver keeps the text of the pending doc and
# section (DESCRIPTION_DATA, SECTION_DATA) and fills the interface variables of the script
# through associate_data_with_anchor, as the current parser does.

BEGIN {
  DRIVE_PARSER_STARTED = 0
}

{
  if (!DRIVE_PARSER_STARTED) { # after the BEGIN of the script (RECIPEPREFIX is processed)
    lexical_init(DRIVE_PARSER_STATE, RECIPEPREFIX)
    DRIVE_PARSER_STARTED = 1
  }
  if (FNR == 1) {
    drive_parser_file_start()
  }
  if (lexical_join(DRIVE_PARSER_STATE, $0)) {
    drive_parser_line(DRIVE_PARSER_STATE["line"])
  }
  drive_parser_set_continued()
  next
}

# At the first line of a file: the warning about the previous file, then a new file (the
# pending doc is dropped, the pending section is kept)
function drive_parser_file_start() {
  warn_about_continued_last_line()
  lexical_file_start(DRIVE_PARSER_STATE)
  forget_descriptions_data()
  # stdin is named - (POSIX leaves FILENAME unspecified for it; most awks set it to -)
  CURRENT_FILE = FILENAME == "" ? "-" : FILENAME
  FILES_PROCESSED = FILES_PROCESSED == "" ? CURRENT_FILE : FILES_PROCESSED " " CURRENT_FILE
}

# A logical line: observe it, keep the text of a doc or section line, update the state, and
# give the doc to the anchor that takes it
function drive_parser_line(line, #locals
                           kind, text) {
  lexical_obs(line, DRIVE_PARSER_STATE, DRIVE_PARSER_OBS)
  kind = DRIVE_PARSER_OBS["kind"]
  text = line
  sub(/^[ \t]+/, "", text)
  if (kind == "doc") {
    save_description_data(text)
  } else if (kind == "section") {
    sub(/^##@/, "", text) # the tags are not needed anymore
    save_section_data(text)
  }

  lexical_step(DRIVE_PARSER_STATE, DRIVE_PARSER_OBS)
  if (DRIVE_PARSER_OBS["attach"]) {
    if (DESCRIPTION_DATA_INDEX == 1) { # no pending doc: the inline doc
      save_description_data(DRIVE_PARSER_OBS["comment"])
    }
    if (DRIVE_PARSER_OBS["anchor"] == "target") {
      associate_data_with_anchor(drive_parser_target_name(DRIVE_PARSER_OBS),
                                 TARGETS_DESCRIPTION_DATA, TARGETS_TAG, "target")
    } else {
      associate_data_with_anchor(DRIVE_PARSER_OBS["name"], VARIABLES_DESCRIPTION_DATA,
                                 VARIABLES_TAG, "variable")
    }
  }
  if (!DRIVE_PARSER_STATE["d"]) {
    forget_descriptions_data()
  }
}

# the name of a documented target, as the current parser forms it: blanks collapsed, a & after
# grouped targets, ~N after the documented rules of a double-colon target (counted across
# files)
function drive_parser_target_name(obs, #locals
                                  name, nominal) {
  name = obs["name"]
  gsub(/[ \t]+/, " ", name)
  if (obs["grouped"]) {
    name = name "&"
  }
  if (obs["double"]) {
    nominal = name
    name = form_dc_target_name(nominal)
    TARGETS_DC_COUNTER[nominal]++
  }
  return name
}

# for warn_about_continued_last_line (at the next file and in END): a line other than a recipe
# line is waiting for its continuation
function drive_parser_set_continued(    pending) {
  pending = DRIVE_PARSER_STATE["pending"]
  IN_CONTINUED_LINE = DRIVE_PARSER_STATE["joining"] &&
                      !(DRIVE_PARSER_STATE["r"] &&
                        substr(pending, 1, 1) == DRIVE_PARSER_STATE["c"])
}
