# Print the state of makefile-doc.awk after parsing (see the groups in init_globals), one line
# per element, instead of the help. Load it before the script, so that its END runs first
# (its exit skips the END of the script):
#   awk -f tools/dump-state.awk -f makefile-doc.awk Makefile

# a value on one line, with its SUBSEP visible
function quote(value) {
  gsub(/\n/, "\\n", value)
  gsub(SUBSEP, "\" SUBSEP \"", value)
  return "\"" value "\""
}

function banner(title) {
  print "# ------------------------------------------------------------------------------"
  print "# " title
  print "# ------------------------------------------------------------------------------"
}

# the elements of an array (in no defined order)
function dump_array(name, array, #locals
                    key) {
  for (key in array) {
    print name "[" (key ~ /^[0-9]+$/ ? key : quote(key)) "] = " quote(array[key])
  }
}

END {
  banner("Settings: derived from the options by process_options")
  dump_array("SUB_PARAMS", SUB_PARAMS)
  dump_array("SUB_LABELS", SUB_LABELS)
  dump_array("SUB_VALUES", SUB_VALUES)
  dump_array("DSUB_PARAMS", DSUB_PARAMS)
  dump_array("DSUB_VALUES", DSUB_VALUES)
  dump_array("DSUB_NAMES", DSUB_NAMES)
  dump_array("DSUB_IN_ANCHORS", DSUB_IN_ANCHORS)
  dump_array("DSUB_IN_DOCS", DSUB_IN_DOCS)
  print "DSUB_COUNT = " DSUB_COUNT

  banner("The interface: written while parsing")
  dump_array("TARGETS_DESCRIPTION_DATA", TARGETS_DESCRIPTION_DATA)
  dump_array("VARIABLES_DESCRIPTION_DATA", VARIABLES_DESCRIPTION_DATA)
  dump_array("TARGETS_TAG", TARGETS_TAG)
  dump_array("VARIABLES_TAG", VARIABLES_TAG)
  dump_array("ANCHOR_ORDER", ANCHOR_ORDER)
  print "ANCHOR_ORDER_INDEX = " ANCHOR_ORDER_INDEX
  dump_array("SECTION_BEFORE", SECTION_BEFORE)
  dump_array("WARNINGS", WARNINGS)
  dump_array("WARNING_KINDS", WARNING_KINDS)
  print "WARNING_COUNT = " WARNING_COUNT
  print "FILES_PROCESSED = " quote(FILES_PROCESSED)

  banner("The state of the rendering: written by prepare_rendering")
  prepare_rendering()
  dump_array("TARGETS", TARGETS)
  print "TARGETS_INDEX = " TARGETS_INDEX
  dump_array("VARIABLES", VARIABLES)
  print "VARIABLES_INDEX = " VARIABLES_INDEX
  dump_array("TARGETS_SECTION_DATA", TARGETS_SECTION_DATA)
  dump_array("VARIABLES_SECTION_DATA", VARIABLES_SECTION_DATA)
  exit
}
