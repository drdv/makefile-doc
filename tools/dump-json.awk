# Print, as JSON, what makefile-doc.awk gets from the Makefiles instead of the help: the
# interface (every documented definition, as parsed), the anchors that would be displayed
# (after the options: VARS, DEPRECATED, SUB, DSUB), and the warnings. Load it before the
# script, so that its END runs first (its exit skips the END of the script):
#   awk -f tools/dump-json.awk -f makefile-doc.awk Makefile
# The layout options (COLOR, PADDING, OFFSET, OUTPUT_FORMAT, the L, M, N, ... of SUB) do not
# apply. Docs and sections are as stored: their lines joined by \n, each with the space that
# followed its token.

# a string as a JSON string (with the escapes of \, ", and the newlines, tabs and CRs)
function json_string(text) {
  text = string_replace("\\", "\\\\", text)
  text = string_replace("\"", "\\\"", text)
  text = string_replace("\n", "\\n", text)
  text = string_replace("\t", "\\t", text)
  text = string_replace("\r", "\\r", text)
  return "\"" text "\""
}

# the fields of the record array[k] as a JSON object (fields: names separated by spaces; a
# field that is not set is left out)
function json_record(array, k, fields, #locals
                     n, f, j, out) {
  n = split(fields, f, " ")
  for (j = 1; j <= n; j++) {
    if ((k, f[j]) in array) {
      out = (out == "" ? "" : out ", ") json_string(f[j]) ": " json_string(array[k, f[j]])
    }
  }
  return "{" out "}"
}

# the words of text as a JSON array of strings
function json_words(text, #locals
                    n, words, k, out) {
  n = split(text, words, " ")
  for (k = 1; k <= n; k++) {
    out = (k == 1 ? "" : out ", ") json_string(words[k])
  }
  return "[" out "]"
}

END {
  prepare_rendering()
  print "{"
  print "  \"files\": " json_words(FILES_PROCESSED) ","

  print "  \"anchors\": [" (ANCHOR_COUNT ? "" : "],")
  for (k = 1; k <= ANCHOR_COUNT; k++) {
    print "    " json_record(ANCHORS, k, "kind name tag doc section override") (k < ANCHOR_COUNT ? "," : "")
  }
  if (ANCHOR_COUNT) {
    print "  ],"
  }

  print "  \"display\": [" (DISPLAY_COUNT ? "" : "],")
  for (k = 1; k <= DISPLAY_COUNT; k++) {
    record = json_record(DISPLAY, k, "kind name tag doc section override")
    if (DISPLAY[k, "values"] != "") {
      record = substr(record, 1, length(record) - 1) ", \"values\": " \
               json_words(DISPLAY[k, "values"]) "}"
    }
    print "    " record (k < DISPLAY_COUNT ? "," : "")
  }
  if (DISPLAY_COUNT) {
    print "  ],"
  }

  print "  \"warnings\": [" (WARNING_COUNT ? "" : "]")
  for (k = 1; k <= WARNING_COUNT; k++) {
    printf("    {\"kind\": %s, \"message\": %s}%s\n", json_string(WARNING_KINDS[k]),
           json_string(WARNINGS[k]), k < WARNING_COUNT ? "," : "")
  }
  if (WARNING_COUNT) {
    print "  ]"
  }
  print "}"
  exit
}
