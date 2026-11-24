# Check process_options: the defaults of the options, and the report of the invalid ones
# (without exiting: BEGIN exits when process_options returns a number other than 0).

# as if no option was given with -v
function clear_options() {
  OUTPUT_FORMAT = VARS = PADDING = DEPRECATED = OFFSET = COLOR = RECIPEPREFIX = ""
  SUB = DSUB = EXPORT_THEME = ""
  COLOR_DEFAULT = COLOR_ATTENTION = COLOR_DEPRECATED = COLOR_SECTION = COLOR_BACKTICKS = ""
}

function test_process_options_defaults() {
  init_globals()
  clear_options()
  check("process_options: no option, no invalid option", process_options(), 0)
  check("process_options: the defaults",
        OUTPUT_FORMAT " " VARS " " DEPRECATED " " OFFSET " [" PADDING "]", "ANSI 1 1 2 [ ]")
  check("process_options: the default recipe prefix is a tab", RECIPEPREFIX, "\t")
  clear_options()
  init_globals()
}

function test_process_options_errors() {
  init_globals()
  clear_options()
  OUTPUT_FORMAT = "pdf"
  VARS = 2
  PADDING = "ab"
  OFFSET = -1
  check("process_options: returns the number of invalid options", process_options(), 4)
  check("process_options: reports every invalid option",
        stderr_text(),
        "ERROR: OUTPUT_FORMAT should be ANSI, HTML or LATEX\n" \
        "ERROR: VARS should be 0 or 1\n" \
        "ERROR: PADDING should have length 1\n" \
        "ERROR: OFFSET should be a non-negative integer\n")
  check("process_options: does not stop the script (BEGIN does)", ABORT, 0)
  clear_options()
  init_globals()
}

BEGIN {
  test_process_options_defaults()
  test_process_options_errors()
  done()
}
