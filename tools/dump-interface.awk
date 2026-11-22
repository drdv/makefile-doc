# Print the interface variables (see init_globals in makefile-doc.awk) after parsing, one
# line per element, instead of the help. Load it before the script, so that its END runs
# first (its exit skips the END of the script):
#   awk -f tools/dump-interface.awk -f makefile-doc.awk Makefile

# a value on one line, with its SUBSEP visible
function quote(value) {
  gsub(/\n/, "\\n", value)
  gsub(SUBSEP, "\" SUBSEP \"", value)
  return "\"" value "\""
}

# the elements of an array (in no defined order)
function dump_array(name, array, #locals
                    key) {
  for (key in array) {
    print name "[" (key ~ /^[0-9]+$/ ? key : quote(key)) "] = " quote(array[key])
  }
}

END {
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
  exit
}
