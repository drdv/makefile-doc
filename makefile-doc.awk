#!/usr/bin/awk -f
# Generate docs for Makefile variables and targets
#
#    File: makefile-doc.awk
#  Author: Dimitar Dimitrov
# License: Apache-2.0
# Project: https://github.com/drdv/makefile-doc

### Commentary

#### Usage
# (the README.md of the project has the details and examples)
#   awk [-v OPTION=value ...] -f makefile-doc.awk [Makefile ...]
#   (without a Makefile, it is read from stdin; if stdin is empty, the help is printed)

#### Docs
#   * Targets and variables are called anchors.
#   * The docs of an anchor are comments placed above it or inline (the inline docs are
#     ignored if there are docs above). They start with one of the tokens:
#       ##   a default anchor (displayed in COLOR_DEFAULT)
#       ##!  an anchor that needs attention (displayed in COLOR_ATTENTION)
#       ##%  a deprecated anchor (displayed in COLOR_DEPRECATED)
#   * Lines that start with ##@ form a section (displayed in COLOR_SECTION, above the next
#     displayed anchor).

#### Options
#   Passed with -v OPTION=value. print_help() lists them (run the script with an empty
#   stdin), and README.md describes them, with examples. The checks are in process_options().

#### Code conventions
#   * Locals are declared as extra parameters (awk has no other way): after a `#locals`
#     comment on the next line, or after four spaces when there are no parameters (awk
#     accepts no comment right after the parenthesis):
#             function f(x, y, #locals          function g(    k, n) {
#                        k, n) {
#   * Globals are upper case (a global in lower case is a local that was not declared).
#   * Only POSIX awk, for all the major awks: no match() with an array, no arrays of arrays,
#     no gensub. Groups are read with RSTART and RLENGTH.
#   * `for (key in array)` has no order: an ordered array uses the keys 1, 2, ... up to its
#     *_INDEX (the next free key) or *_COUNT.

#### Structure of the code
#   Helpers                pure functions (no global variables)
#   Global initialization  init_globals: the global variables, grouped by who writes them
#   Options                the options: defaults, checks and derived settings
#   Output formats         everything that depends on OUTPUT_FORMAT
#   Parsing                the parser that reads the Makefiles, and its helpers
#   Rendering              what is displayed (DISPLAY), then its layout in the output format
#   Flow                   BEGIN and END
# A function is in the section that owns the variables it writes: Options writes the
# settings, Parsing the interface (see init_globals), which Rendering reads. Output formats
# is the exception: it groups a feature across these steps.

#### Terminology
#   * Rule: `targets [&]:[:] [prerequisites] [; inline recipe]` or
#     `targets [&]:[:] variable assignment`, then its recipe lines. The parser and its terms
#     are described in misc/docs/parser-model.tex.
#   * A single-colon target has one recipe, so one doc (the last one wins); a double-colon
#     target has a recipe per rule, so a doc per documented rule (t~1, t~2, ...).


### Code

#### Helpers
# Pure functions: they use no global variables.

function max(x, y) {
  return (x >= y) ? x : y
}

function min(x, y) {
  return (x <= y) ? x : y
}

# string repeated n times. n must be a non-negative integer (the only n that comes from the
# user, OFFSET, is checked by process_options). (A loop, not gsub, which would need & and \
# escaped.)
function repeated_string(string, n, #locals
                         s, k) {
  s = ""
  for (k = 1; k <= n; k++) {
    s = s string
  }
  return s
}

# n spaces (see repeated_string)
function spaces(n) {
  return repeated_string(" ", n)
}

# copy the elements of the array from to the array to (emptied first)
function copy_array(from, to, #locals
                    key) {
  split("", to)
  for (key in from) {
    to[key] = from[key]
  }
}

# array[key], or "" if there is no such key (unlike reading array[key], it does not create it)
function array_get(array, key) {
  return (key in array) ? array[key] : ""
}

# in POSIX-compliant AWK the length function works on strings but not on arrays
function length_array_posix(array, #locals
                            key, n) {
  n = 0
  for (key in array) {
    n++
  }
  return n
}

# join the elements 1..n of an array (e.g., n and the array of split())
function join(array, n, delimiter, #locals
              string, k) {
  string = ""
  for (k = 1; k <= n; k++) {
    if (k == 1) {
      string = array[k]
    } else {
      string = string delimiter array[k]
    }
  }
  return string
}

# Replace every occurrence of string in text with replacement, without using a regex.
# With gsub, the characters that are special in a regex (in string) or in a replacement
# (& and \) would have to be escaped; here string comes from the user (DSUB) and
# replacement contains & and \ (HTML and LaTeX escapes).
function string_replace(string, replacement, text, #locals
                        k, len, result) {
  if (string == "") { # not `if (!string)`: a string that looks like 0 is false
    return text
  }
  # a loop and not a recursion: mawk has a small stack (about 200 nested calls)
  len = length(string)
  result = ""
  while ((k = index(text, string)) > 0) {
    result = result substr(text, 1, k - 1) replacement
    text = substr(text, k + len)
  }
  return result text
}

function strip_start_end_spaces_tabs(string) {
  sub(/^[ \t]*/, "", string)
  sub(/[ \t]*$/, "", string)
  return string
}

# Remove spaces and tabs at the end of each line (e.g., the padding and the offset of an
# empty doc). No regex: on the long runs of spaces of the padding, a regex such
# as /[ \t]+\n/ takes time quadratic in their length.
function strip_trailing_blanks(text, #locals
                               n, lines, k, line, last) {
  last = substr(text, length(text), 1) # lint: ignore[substr: start index] ("" for an empty text)
  if (!index(text, " \n") && !index(text, "\t\n") && last != " " && last != "\t") {
    return text # nothing to strip (the usual case)
  }
  n = split(text, lines, "\n")
  text = ""
  for (k = 1; k <= n; k++) {
    line = lines[k]
    while (line != "" && index(" \t", substr(line, length(line), 1))) {
      line = substr(line, 1, length(line) - 1)
    }
    text = text (k > 1 ? "\n" : "") line
  }
  return text
}

# true if the string ends with an odd number of backslashes (a line continuation)
function has_odd_terminal_backslashes(string, #locals
                                      n, k) {
  n = 0
  for (k = length(string); k > 0 && substr(string, k, 1) == "\\"; k--) {
    n++
  }
  return n % 2
}

function is_bool(value) {
  return value ~ /^[01]$/
}

# a color of 6 hex digits (without a leading #)
function is_hex_color(value) {
  return length(value) == 6 && value ~ /^[0-9A-Fa-f]+$/
}

# the name of the color of label in the HTML and LaTeX output (an HTML class, a LaTeX color),
# e.g., makefile-doc-default
function color_name(label) {
  return "makefile-doc-" tolower(label)
}

#### Global initialization
# The global state that does not depend on the options: constants and empty arrays.

# Set the global state that does not depend on user options. It is called from BEGIN and
# can be called from unit tests (also to reset the state between tests).
function init_globals() {
  # The options (COLOR, VARS, SUB, ...) are not initialized here: -v sets them before BEGIN,
  # and process_options gives them their defaults (print_help lists them).

  # ---------------------------------------------------------------------------------------
  # The control of the run
  # ---------------------------------------------------------------------------------------

  # can be overridden with -v STDERR=file (used by the unit tests)
  STDERR = STDERR == "" ? "/dev/stderr" : STDERR
  ABORT = 0 # set to the exit status when BEGIN fails (END must not print anything)
  OPTION_ERRORS = 0 # number of invalid options (see option_error)

  # ---------------------------------------------------------------------------------------
  # Constants (never changed after init_globals)
  # ---------------------------------------------------------------------------------------

  VERSION = "v2.1" # the only place where the version is defined

  # The special built-in targets of GNU Make (see parser_observe). Suffix rules, which
  # GNU Make also counts as special targets, are not among them: they are displayed.
  SPECIAL_TARGETS_REGEX = "^[ \t]*\\.(PHONY|SUFFIXES|DEFAULT|PRECIOUS|INTERMEDIATE|" \
                          "NOTINTERMEDIATE|SECONDARY|SECONDEXPANSION|DELETE_ON_ERROR|" \
                          "IGNORE|LOW_RESOLUTION_TIME|SILENT|EXPORT_ALL_VARIABLES|" \
                          "NOTPARALLEL|ONESHELL|POSIX)[ \t]*:"

  # the tag at the start of a doc line (the order of the alternatives matters for goawk
  # v1.29.1 and below, fixed in v1.30.0)
  TAG_REGEX = "^(##!|##%|##)"

  # stands in for a character during a split or a replacement (see form_substitutions,
  # parse_substitution_params, latex_escape); assumed absent from options and
  # docs. Not SUBSEP, though it has the same default value.
  PLACEHOLDER = "\034"

  # the tables of the HTML and LaTeX output formats
  define_ansi_to_html_attributes()
  define_ansi_to_latex_function()

  HEADER_TARGETS = "Available targets:"
  HEADER_VARIABLES = "Variables:"
  DOUBLE_COLON_SEPARATOR = "~" # decorates double-colon targets, e.g., t~1

  # ---------------------------------------------------------------------------------------
  # Settings: derived from the options by process_options, read when rendering
  # ---------------------------------------------------------------------------------------

  # the colors of the HTML and LaTeX output (process_options applies EXPORT_THEME)
  define_ansi_to_html_colors()

  # the color codes of each kind of text (see initialize_colors)
  COLOR_DEFAULT_CODE = COLOR_ATTENTION_CODE = COLOR_DEPRECATED_CODE = ""
  COLOR_SECTION_CODE = COLOR_BACKTICKS_CODE = COLOR_RESET_CODE = ""

  # the text before and after the documentation (see initialize_output_format)
  OUTPUT_HEADER = OUTPUT_FOOTER = ""

  # SUB and DSUB (see form_substitutions). The parameters of each substitution, with the
  # defaults filled in, are in the rows of a table: SUB_PARAM[name, key] (keys L, M, N, S, P,
  # I, T) and DSUB_PARAM[name, key] (keys A, D). The row "" holds the defaults: it is the
  # row of an anchor without SUB (a name is never empty).
  set_sub_param_defaults(SUB_PARAM)
  split("", SUB_LABELS)
  split("", SUB_VALUES)
  set_dsub_param_defaults(DSUB_PARAM)
  split("", DSUB_VALUES)
  split("", DSUB_NAMES)
  DSUB_COUNT = 0 # number of DSUB substitutions

  # ---------------------------------------------------------------------------------------
  # The interface between parsing and rendering: written while parsing (see record_anchor
  # and add_warning), read when rendering (see prepare_rendering)
  # ---------------------------------------------------------------------------------------

  # every definition of a documented anchor, in file order (a redefinition too):
  # ANCHORS[k, field], k = 1..ANCHOR_COUNT, with the fields
  #   kind     target or variable
  #   name     as written (blanks collapsed, & for grouped targets, ~N for double-colon rules)
  #   doc      its lines without their tags, joined by \n
  #   tag      the tag of its first line: ##, ##! or ##%
  #   section  the section just before it, its lines joined by \n (only if there is one)
  #   override 1 for a variable set with override (only then)
  split("", ANCHORS)
  ANCHOR_COUNT = 0

  # the warnings about the Makefiles: index -> message and kind (see add_warning)
  split("", WARNINGS)
  split("", WARNING_KINDS)
  WARNING_COUNT = 0

  FILES_PROCESSED = "" # the names of the files read, separated by spaces

  # ---------------------------------------------------------------------------------------
  # The state of the parser
  # ---------------------------------------------------------------------------------------

  # As in misc/docs/parser-model.tex (see parser_init, called in BEGIN once RECIPEPREFIX is
  # known):
  #   PARSER_STATE    the state x_i = (r_i, d_i, s_i, c_i)
  #   PARSER_DATA     the data that travels with it: the pending text D_i and S_i
  #   PARSER_OBS      the observation of the last logical line l_i
  # and outside the model:
  #   PARSER_JOINER   the physical lines joined into the next logical line (see parser_join)
  #   PARSER_CONTEXT  the file being read, and what names and warnings need (see record_anchor)
  split("", PARSER_STATE)
  split("", PARSER_DATA)
  split("", PARSER_OBS)
  parser_join_init(PARSER_JOINER)
  split("", PARSER_CONTEXT)

  # ---------------------------------------------------------------------------------------
  # The state of the rendering: written by prepare_rendering (what is displayed)
  # ---------------------------------------------------------------------------------------

  # the anchors to display, in order (the targets, then the variables): DISPLAY[k, field],
  # k = 1..DISPLAY_COUNT, with the fields
  #   kind, tag  as in ANCHORS (of the last definition)
  #   name       the displayed name (see display_name)
  #   label      the text of the name column: name, with " (fixed)" after it for override
  #   doc        the doc after DSUB
  #   section    the section above it after DSUB (only if there is one, see place_sections)
  #   values     its SUB values, space-separated ("" if none)
  #   sub_row    its row in SUB_PARAM: its name if it has a SUB, "" (the defaults) otherwise
  #   override   1 for a variable set with override (only then; displayed as "(fixed)")
  split("", DISPLAY)
  DISPLAY_COUNT = 0
  DOCUMENTED_COUNT = 0 # the documented anchors, displayed or not
}

# Empty a table of SUB parameters, then set its row of defaults, "" (see init_globals)
function set_sub_param_defaults(table) {
  split("", table)
  table["", "L"] = 1 # 0: start display on current line, 1: start display on next line
  table["", "M"] = 1 # 1: multi-line display, 0: single-line display
  table["", "N"] = -1 # max number of elements to display (-1 means no limit)
  table["", "S"] = "" # separator
  table["", "P"] = "" # prefix
  table["", "I"] = "" # initial string, e.g., (
  table["", "T"] = "" # termination string, e.g., )
}

# Empty a table of DSUB parameters, then set its row of defaults, "" (see init_globals)
function set_dsub_param_defaults(table) {
  split("", table)
  table["", "A"] = 0 # 1: replace in the names of anchors too
  table["", "D"] = 1 # 1: replace in the docs and section titles
}

#### Options
# The options given with -v: their defaults, their checks and the settings derived from them
# (those of the output formats are in Output formats).

# Check the options and derive the settings. All the invalid options are reported (see
# option_error); return their number (BEGIN exits when it is not 0).
function process_options(    sub_names, dummy_array_labels) {
  OUTPUT_FORMAT = OUTPUT_FORMAT == "" ? "ANSI" : toupper(OUTPUT_FORMAT)
  if (OUTPUT_FORMAT != "ANSI" && OUTPUT_FORMAT != "HTML" && OUTPUT_FORMAT != "LATEX") {
    option_error("OUTPUT_FORMAT should be ANSI, HTML or LATEX")
    OUTPUT_FORMAT = "ANSI"
  }

  initialize_colors()
  initialize_output_format()

  RECIPEPREFIX = RECIPEPREFIX == "" ? "\t" : substr(RECIPEPREFIX, 1, 1)

  VARS = VARS == "" ? 1 : VARS
  PADDING = PADDING == "" ? " " : PADDING
  DEPRECATED = DEPRECATED == "" ? 1 : DEPRECATED
  OFFSET = OFFSET == "" ? 2 : OFFSET
  if (!is_bool(VARS)) {
    option_error("VARS should be 0 or 1")
  }
  if (length(PADDING) != 1) {
    option_error("PADDING should have length 1")
  }
  if (!is_bool(DEPRECATED)) {
    option_error("DEPRECATED should be 0 or 1")
  }
  if (OFFSET !~ /^[0-9]+$/) {
    option_error("OFFSET should be a non-negative integer")
  }

  # (with "", gawk --lint does not warn when the option is not set)
  form_substitutions(SUB "", SUB_PARAM, SUB_LABELS, SUB_VALUES, sub_names, 0)
  form_substitutions(DSUB "", DSUB_PARAM, dummy_array_labels, DSUB_VALUES, DSUB_NAMES, 1)
  DSUB_COUNT = length_array_posix(DSUB_NAMES)

  report_assignment_operands()
  return OPTION_ERRORS
}

# Report an invalid value of an option. The script goes on, so that all the invalid options
# are reported, and stops after process_options() (see BEGIN).
function option_error(message) {
  printf("ERROR: %s\n", message) > STDERR
  OPTION_ERRORS++
}

# Report the operands that are assignments, e.g., VARS=0: awk makes them after BEGIN, too
# late for the options, which must be given with -v (see option_error)
function report_assignment_operands(    k) {
  for (k = 1; k < ARGC; k++) {
    if (ARGV[k] ~ /^[A-Za-z_][A-Za-z0-9_]*=/) {
      option_error(sprintf("'%s' is an assignment: give options with -v (-v %s)",
                           ARGV[k], ARGV[k]))
    }
  }
}

# Parse spec, the value of SUB or DSUB (items separated by ;, \; is a ; in an item), each
# with optional parameters <p1:v1,...>, stored in the rows of the table param_table (see
# init_globals, and the store_*_params functions):
#   SUB   NAME:VALUES, NAME:LABEL:VALUES or NAME::VALUES (an empty label is no label)
#   DSUB  NAME:VALUE (no_labels is set)
# The value is everything after the last separator, so it can hold colons; for SUB,
# t::/a:b gives the value /a:b, while t:/a:b gives the label /a and the value b.
# Empty items are skipped; invalid ones (no colon, no name, a name given twice) are reported
# (see option_error) and skipped, as are invalid parameters.
function form_substitutions(spec, param_table, sub_labels_array,
                            sub_values_array, sub_names_array, no_labels, #locals
                            split_substitutions, k, n, string, substitution_params,
                            substitution_rest, name, label, values, colon,
                            has_label, n_substitutions, option) {
  if (no_labels) {
    set_dsub_param_defaults(param_table)
  } else {
    set_sub_param_defaults(param_table)
  }
  split("", sub_labels_array)
  split("", sub_values_array)
  split("", sub_names_array) # names in the order they are given

  option = no_labels ? "DSUB" : "SUB"
  n = 0
  gsub(/\\;/, PLACEHOLDER, spec) # an escaped ; does not separate items
  n_substitutions = split(spec, split_substitutions, ";")
  for (k = 1; k <= n_substitutions; k++) {
    string = split_substitutions[k]
    gsub(PLACEHOLDER, ";", string)
    if (string ~ /^[ \t]*$/) {
      continue
    }

    # Extract optional params in a <...> prefix
    if (match(string, /^<([^>]*)>/)) {
      substitution_params = substr(string, RSTART+1, RLENGTH-2) # strip < and >
      substitution_rest = substr(string, RSTART + RLENGTH)
    } else {
      substitution_params = ""
      substitution_rest = string
    }

    colon = index(substitution_rest, ":")
    if (colon == 0) {
      option_error(sprintf("%s: '%s' should be %s", option, string,
                           no_labels ? "NAME:VALUE" : "NAME:[[LABEL]:][VALUES]"))
      continue
    }
    name = substr(substitution_rest, 1, colon - 1)
    values = substr(substitution_rest, colon + 1)
    has_label = 0
    colon = no_labels ? 0 : index(values, ":")
    if (colon > 0) {
      label = substr(values, 1, colon - 1)
      label = strip_start_end_spaces_tabs(label)
      values = substr(values, colon + 1)
      has_label = (label != "") # NAME::VALUES (or a blank label) has no label
    }
    name = strip_start_end_spaces_tabs(name)

    if (name == "") {
      option_error(sprintf("%s: '%s' has an empty NAME", option, string))
      continue
    }
    if (name in sub_values_array) {
      option_error(sprintf("%s: '%s' is given more than once", option, name))
      continue
    }
    if (no_labels) {
      store_dsub_params(param_table, name, substitution_params)
    } else {
      store_sub_params(param_table, name, substitution_params)
    }

    sub_names_array[++n] = name
    sub_values_array[name] = values
    if (has_label) {
      sub_labels_array[name] = label
    }
  }
}

# Split the parameters of a substitution, "k1:v1,k2:v2,...", into params[key] = value and
# keys[1..n] (the keys in the order given); return n. In a pair, only the first colon is a
# separator, and a comma in a value is written \,
function parse_substitution_params(string, params, keys, #locals
                                   k, n, n_pairs, key_values, pair, key) {
  split("", params)
  split("", keys)

  # temporarily replace escaped commas
  gsub(/\\,/, PLACEHOLDER, string)
  n_pairs = split(string, key_values, ",")
  n = 0
  for (k = 1; k <= n_pairs; k++) {
    if (key_values[k] ~ /^[ \t]*$/) {
      continue # an empty pair, e.g., after a trailing comma
    }
    gsub(PLACEHOLDER, ",", key_values[k]) # restore commas
    split(key_values[k], pair, ":")
    key = strip_start_end_spaces_tabs(pair[1])
    params[key] = substr(key_values[k], length(pair[1]) + 2) # after the first colon
    keys[++n] = key
  }
  return n
}

# Copy the row of defaults of a table of parameters, "", to the row name (the keys of the row
# "" are found first: adding elements to an array while looping over it is undefined)
function copy_param_defaults(table, name, #locals
                             key, defaults) {
  for (key in table) {
    if (index(key, SUBSEP) == 1) {
      defaults[substr(key, length(SUBSEP) + 1)] = table[key]
    }
  }
  for (key in defaults) {
    table[name, key] = defaults[key]
  }
}

# Start the row name of table with the defaults (see copy_param_defaults), and parse its
# parameters, string_with_parameters (see parse_substitution_params). Report the repeated
# parameters and the unknown ones (allowed: the known keys, as written in the message, e.g.,
# "A or D"; see option_error), and return the others: keys[1..n] in the order given and
# params[key] their values. option is SUB or DSUB.
function checked_params(option, allowed, table, name, string_with_parameters, params,
                        keys, #locals
                        all_params, all_keys, k, n, n_all, key, seen) {
  copy_param_defaults(table, name)
  split("", params)
  split("", keys)
  split("", seen)
  n = 0
  n_all = parse_substitution_params(string_with_parameters, all_params, all_keys)
  for (k = 1; k <= n_all; k++) {
    key = all_keys[k]
    if (key in seen) {
      option_error(sprintf("%s: parameter %s of %s is given more than once", option, key,
                           name))
    } else if (!(("", key) in table)) {
      option_error(sprintf("%s: unknown parameter %s of %s (use %s)", option, key, name,
                           allowed))
    } else {
      keys[++n] = key
      params[key] = all_params[key]
    }
    seen[key] = 1
  }
  return n
}

# Store the parameters of the SUB substitution of name in its row of table: the defaults (the
# row ""), replaced by the valid parameters of string_with_parameters; the invalid ones are
# reported (see option_error). L, M and N are stored as numbers.
function store_sub_params(table, name, string_with_parameters, #locals
                          params, keys, k, n, key, value) {
  n = checked_params("SUB", "L, M, N, S, P, I or T", table, name, string_with_parameters,
                     params, keys)
  for (k = 1; k <= n; k++) {
    key = keys[k]
    value = strip_start_end_spaces_tabs(params[key])
    if ((key == "L" || key == "M") && !is_bool(value)) {
      option_error(sprintf("SUB: parameter %s of %s should be 0 or 1", key, name))
    } else if (key == "N" && value !~ /^(-1|[0-9]+)$/) {
      option_error(sprintf("SUB: parameter N of %s should be -1 or a non-negative integer",
                           name))
    } else {
      # S, P, I and T as given (their blanks are part of them)
      table[name, key] = (key == "L" || key == "M" || key == "N") ? value + 0 : params[key]
    }
  }
}

# Store the parameters of the DSUB substitution of name in its row of table, as numbers: the
# defaults (the row ""), replaced by the valid parameters of string_with_parameters; the
# invalid ones are reported (see option_error):
#   A  0: (default) the names of anchors are not changed, 1: name is replaced in them too
#   D  0: the docs and section titles are not changed, 1: (default) name is replaced in them
function store_dsub_params(table, name, string_with_parameters, #locals
                           params, keys, k, n, key, value) {
  n = checked_params("DSUB", "A or D", table, name, string_with_parameters, params, keys)
  for (k = 1; k <= n; k++) {
    key = keys[k]
    value = strip_start_end_spaces_tabs(params[key])
    if (!is_bool(value)) {
      option_error(sprintf("DSUB: parameter %s of %s should be 0 or 1", key, name))
    } else {
      table[name, key] = value + 0
    }
  }
  if (!table[name, "A"] && !table[name, "D"]) {
    option_error(sprintf("DSUB: %s is replaced nowhere (A and D are both 0)", name))
  }
}

# the help: the usage, then the options with their current values (shown in double quotes,
# so that empty values and blanks are visible)
function print_help() {
  print "Usage: awk [-v option=value] -f makefile-doc.awk [Makefile ...] (default: stdin)"
  print "Description: Generate docs for Makefile variables and targets"
  print "Version: " VERSION
  print "Options (current values):"
  print_option("VARS", "show documented variables (0 or 1)", VARS)
  print_option("DEPRECATED", "show deprecated anchors (0 or 1)", DEPRECATED)
  print_option("PADDING", "character between anchors and docs", PADDING)
  print_option("OFFSET", "spaces between anchors and docs", OFFSET)
  print_option("COLOR", "use colors (0 or 1)", COLOR)
  print_option("OUTPUT_FORMAT", "ANSI, HTML or LATEX", OUTPUT_FORMAT)
  # (EXPORT_THEME, SUB and DSUB have no default: with "", gawk --lint does not warn about them)
  print_option("EXPORT_THEME", "colors of the HTML and LaTeX output", EXPORT_THEME "")
  print_option("SUB", "rename anchors and list values", SUB "")
  print_option("DSUB", "replace text in docs and names", DSUB "")
  print_option("RECIPEPREFIX", "the .RECIPEPREFIX of the Makefile",
               RECIPEPREFIX == "\t" ? "\\t" : RECIPEPREFIX)
  print_option("COLOR_DEFAULT", "anchors documented with ##", COLOR_DEFAULT)
  print_option("COLOR_ATTENTION", "anchors documented with ##!", COLOR_ATTENTION)
  print_option("COLOR_DEPRECATED", "anchors documented with ##%", COLOR_DEPRECATED)
  print_option("COLOR_SECTION", "sections", COLOR_SECTION)
  print_option("COLOR_BACKTICKS", "text in backticks", COLOR_BACKTICKS)
}

# one line of the help: an option, its description and its value
function print_option(name, description, value) {
  printf("  %-16s  %-35s  \"%s\"\n", name, description, value)
}

#### Output formats
# Everything that depends on OUTPUT_FORMAT (ANSI, HTML, LATEX): colors, themes, escapes,
# header and footer. Rendering does not read OUTPUT_FORMAT: it calls the functions fmt_*
# (fmt_escape, fmt_color, fmt_document), and uses the color codes of fmt_color_code.

function initialize_colors() {
  COLOR = COLOR == "" ? default_color_option() : COLOR
  if (!is_bool(COLOR)) {
    option_error("COLOR should be 0 or 1")
    COLOR = 1
  }

  set_user_defined_color_theme() # EXPORT_THEME overrides colors of EXPORT_PALETTE

  COLOR_DEFAULT = validate_ansi_param("COLOR_DEFAULT",
                                      COLOR_DEFAULT == "" ? 34 : COLOR_DEFAULT)
  COLOR_ATTENTION = validate_ansi_param("COLOR_ATTENTION",
                                        COLOR_ATTENTION == "" ? 31 : COLOR_ATTENTION)
  COLOR_DEPRECATED = validate_ansi_param("COLOR_DEPRECATED",
                                         COLOR_DEPRECATED == "" ? 33 : COLOR_DEPRECATED)
  COLOR_SECTION = validate_ansi_param("COLOR_SECTION",
                                      COLOR_SECTION == "" ? 32 : COLOR_SECTION)
  COLOR_BACKTICKS = validate_ansi_param("COLOR_BACKTICKS",
                                        COLOR_BACKTICKS == "" ? 33 : COLOR_BACKTICKS)
  if (!COLOR) {
    COLOR_DEFAULT = COLOR_ATTENTION = COLOR_DEPRECATED = COLOR_SECTION = COLOR_BACKTICKS = 0
  }

  COLOR_DEFAULT_CODE = fmt_color_code(COLOR_DEFAULT, "DEFAULT")
  COLOR_ATTENTION_CODE = fmt_color_code(COLOR_ATTENTION, "ATTENTION")
  COLOR_DEPRECATED_CODE = fmt_color_code(COLOR_DEPRECATED, "DEPRECATED")
  COLOR_SECTION_CODE = fmt_color_code(COLOR_SECTION, "SECTION")
  COLOR_BACKTICKS_CODE = fmt_color_code(COLOR_BACKTICKS, "BACKTICKS")
  COLOR_RESET_CODE = fmt_color_code(-1)
}

# the default of the COLOR option: 0 if NO_COLOR is set to a non-empty value (no-color.org)
function default_color_option() {
  return ("NO_COLOR" in ENVIRON && ENVIRON["NO_COLOR"] != "") ? 0 : 1
}

# Return the ANSI color parameter given for a COLOR_* option (0 means no color). An
# unsupported value is reported (see option_error).
function validate_ansi_param(option, ansi_param) {
  # the supported parameters: the colors (EXPORT_PALETTE) and the attributes, e.g., bold
  if (ansi_param in EXPORT_PALETTE || ansi_param in ANSI_TO_HTML_VALUE) {
    # The explicit cast to int here is needed only because of a busybox awk bug,
    # see misc/busybox_awk_bug_20251107.awk
    return int(ansi_param)
  }
  option_error(sprintf("%s should be one of 0, 1, 3, 4, 9, 30-37, 40-47, 90-97, 100-107",
                       option))
  return 0
}

# The colors of the HTML and LaTeX output (EXPORT_THEME can change them):
#   EXPORT_PALETTE[param]  the hex color of an ANSI color parameter (30-37, 40-47, 90-97,
#                          100-107); the solarized theme is used by default
#                          https://github.com/altercation/solarized?tab=readme-ov-file#the-values
#   EXPORT_FG_BG[FG|BG]    the colors of the text and of the background ("" if not set)
function define_ansi_to_html_colors(    k) {
  EXPORT_FG_BG["FG"] = ""
  EXPORT_FG_BG["BG"] = ""

  EXPORT_PALETTE[30] = "073642" # black
  EXPORT_PALETTE[31] = "dc322f" # red
  EXPORT_PALETTE[32] = "859900" # green
  EXPORT_PALETTE[33] = "b58900" # yellow
  EXPORT_PALETTE[34] = "268bd2" # blue
  EXPORT_PALETTE[35] = "d33682" # magenta
  EXPORT_PALETTE[36] = "2aa198" # cyan
  EXPORT_PALETTE[37] = "eee8d5" # white

  EXPORT_PALETTE[90] = "002b36" # brblack
  EXPORT_PALETTE[91] = "cb4b16" # brred
  EXPORT_PALETTE[92] = "586e75" # brgreen
  EXPORT_PALETTE[93] = "657b83" # bryellow
  EXPORT_PALETTE[94] = "839496" # brblue
  EXPORT_PALETTE[95] = "6c71c4" # brmagenta
  EXPORT_PALETTE[96] = "93a1a1" # brcyan
  EXPORT_PALETTE[97] = "fdf6e3" # brwhite

  for (k = 30; k <= 37; k++) { EXPORT_PALETTE[k+10] = EXPORT_PALETTE[k] }
  for (k = 90; k <= 97; k++) { EXPORT_PALETTE[k+10] = EXPORT_PALETTE[k] }
}

# Apply EXPORT_THEME, ANSI_PARAM:HEX_COLOR[,...]: the colors of the parameters 30-37, 40-47,
# 90-97 and 100-107, and FG and BG (invalid entries are reported, see option_error)
function set_user_defined_color_theme(    html_colors_split, k, n, ansi_html_map,
                                          ansi_param, html_color_code) {
  n = split(EXPORT_THEME, html_colors_split, ",")
  for (k = 1; k <= n; k++) {
    if (html_colors_split[k] ~ /^[ \t]*$/) {
      continue # an empty entry, e.g., after a trailing comma
    }
    split(html_colors_split[k], ansi_html_map, ":")
    ansi_param = ansi_html_map[1]
    html_color_code = array_get(ansi_html_map, 2) # "" if there is no colon
    if (ansi_param != "FG" && ansi_param != "BG" && !(ansi_param in EXPORT_PALETTE)) {
      option_error(sprintf("EXPORT_THEME: '%s' should start with FG, BG or one of %s",
                           html_colors_split[k], "30-37, 40-47, 90-97, 100-107"))
    } else if (!is_hex_color(html_color_code)) {
      option_error(sprintf("EXPORT_THEME: '%s' should end with a color of 6 hex digits",
                           html_colors_split[k]))
    } else if (ansi_param in EXPORT_PALETTE) {
      EXPORT_PALETTE[ansi_param] = html_color_code
    } else {
      EXPORT_FG_BG[ansi_param] = html_color_code
    }
  }
}

# The CSS property of each ANSI parameter, and the value of the attributes (the colors are
# in EXPORT_PALETTE)
function define_ansi_to_html_attributes(    k) {
  ANSI_TO_HTML_VALUE[0] = ""
  ANSI_TO_HTML_VALUE[1] = "bold"
  ANSI_TO_HTML_VALUE[3] = "italic"
  ANSI_TO_HTML_VALUE[4] = "underline"
  ANSI_TO_HTML_VALUE[9] = "line-through"

  ANSI_TO_HTML_ATTR[0] = ""
  ANSI_TO_HTML_ATTR[1] = "font-weight"
  ANSI_TO_HTML_ATTR[3] = "font-style"
  ANSI_TO_HTML_ATTR[4] = "text-decoration"
  ANSI_TO_HTML_ATTR[9] = "text-decoration"

  for (k = 30; k <= 37; k++) { ANSI_TO_HTML_ATTR[k] = "color" }
  for (k = 40; k <= 47; k++) { ANSI_TO_HTML_ATTR[k] = "background-color" }
  for (k = 90; k <= 97; k++) { ANSI_TO_HTML_ATTR[k] = "color" }
  for (k = 100; k <= 107; k++) { ANSI_TO_HTML_ATTR[k] = "background-color" }
}

function define_ansi_to_latex_function(    k) {
  ANSI_TO_LATEX_FUN[0] = ""
  ANSI_TO_LATEX_FUN[1] = "\\textbf"
  ANSI_TO_LATEX_FUN[3] = "\\emph"
  ANSI_TO_LATEX_FUN[4] = "\\uline"
  ANSI_TO_LATEX_FUN[9] = "\\sout"

  for (k = 30; k <= 37; k++) { ANSI_TO_LATEX_FUN[k] = "\\textcolor" }
  for (k = 40; k <= 47; k++) { ANSI_TO_LATEX_FUN[k] = "\\bgcolor" }
  for (k = 90; k <= 97; k++) { ANSI_TO_LATEX_FUN[k] = "\\textcolor" }
  for (k = 100; k <= 107; k++) { ANSI_TO_LATEX_FUN[k] = "\\bgcolor" }
}

# The color code that starts text of the color of color_label_key in the output format, for
# ansi_color_param:
# == 0: no color ("")
#  > 0: some color
#  < 0: the code that ends a color (the user cannot set -1, see validate_ansi_param())
function fmt_color_code(ansi_color_param, color_label_key) {
  if (!ansi_color_param) {
    return "" # token for "no color annotation should be applied at all"
  }

  if (OUTPUT_FORMAT == "ANSI") {
    if (ansi_color_param == -1) {
      return "\033[0m"
    } else {
      return "\033[" ansi_color_param "m"
    }
  } else if (OUTPUT_FORMAT == "HTML") {
    if (ansi_color_param == -1) {
      return "</span>"
    } else {
      return "<span class=\"" color_name(color_label_key) "\">"
    }
  } else if (OUTPUT_FORMAT == "LATEX") {
    if (ansi_color_param == -1) {
      return "}"
    } else {
      if (ansi_color_param > 9) {
        return ANSI_TO_LATEX_FUN[ansi_color_param] "{" color_name(color_label_key) "}{"
      } else {
        return ANSI_TO_LATEX_FUN[ansi_color_param] "{"
      }
    }
  }
}

# Return the CSS rule (one line) for a color option, or "" if there is nothing to style
function ansi_color_param_to_html_style(ansi_color_param, label, #locals
                                        value) {
  if (!ansi_color_param) {
    return ""
  }
  if (ansi_color_param in EXPORT_PALETTE) {
    value = "#" EXPORT_PALETTE[ansi_color_param]
  } else {
    value = ANSI_TO_HTML_VALUE[ansi_color_param]
  }
  return sprintf("  .%s { %s: %s; }\n",
                 color_name(label), ANSI_TO_HTML_ATTR[ansi_color_param], value)
}

# the CSS rule (one line) of the element with the class makefile-doc: as wide as its text (a
# div is as wide as the page, which a background shows), with FG and BG if they are set
function html_box_style(    style) {
  style = "display: inline-block;"
  if (EXPORT_FG_BG["FG"] != "") {
    style = style " color: #" EXPORT_FG_BG["FG"] ";"
  }
  if (EXPORT_FG_BG["BG"] != "") {
    style = style " background-color: #" EXPORT_FG_BG["BG"] ";"
  }
  return "  .makefile-doc { " style " }\n"
}

# Set OUTPUT_HEADER and OUTPUT_FOOTER, printed around the documentation (each ends with a
# newline; empty for ANSI). Called after initialize_colors, whose colors it uses.
function initialize_output_format() {
  OUTPUT_HEADER = OUTPUT_FOOTER = ""
  if (OUTPUT_FORMAT == "HTML") {
    OUTPUT_FOOTER = "</pre>\n</div>\n"
    # an HTML fragment (to paste into a page): the styles, then the documentation
    OUTPUT_HEADER = "<style>\n" \
        ansi_color_param_to_html_style(COLOR_ATTENTION, "ATTENTION") \
        ansi_color_param_to_html_style(COLOR_SECTION, "SECTION") \
        ansi_color_param_to_html_style(COLOR_DEPRECATED, "DEPRECATED") \
        ansi_color_param_to_html_style(COLOR_DEFAULT, "DEFAULT") \
        ansi_color_param_to_html_style(COLOR_BACKTICKS, "BACKTICKS") \
        html_box_style() \
        "</style>\n<div class=\"makefile-doc\">\n<pre>\n"
  } else if (OUTPUT_FORMAT == "LATEX") {
    OUTPUT_FOOTER = "\\end{alltt}\n\\end{varwidth}\n\\end{document}\n"
    OUTPUT_HEADER = latex_header() "\n"
  }
}

# a \definecolor line: the color of label (see color_name) is hex_color
function latex_definecolor(label, hex_color) {
  return sprintf("\\definecolor{%s}{HTML}{%s}\n", color_name(label), hex_color)
}

# the hex color of an ANSI parameter (black for an attribute, e.g., bold, or for no color)
function latex_hex_color(ansi_color_param) {
  return (ansi_color_param in EXPORT_PALETTE) ? EXPORT_PALETTE[ansi_color_param] : "000000"
}

# the preamble of the LaTeX output, up to the start of the documentation
function latex_header(    header) {
  header = "\\documentclass{article}\n"
  header = header "\\usepackage[utf8]{inputenc}\n"
  header = header "\\usepackage{xcolor}\n"
  header = header "\\usepackage{alltt}\n"
  header = header "\\usepackage[top=0cm, bottom=0cm, left=0cm, right=0cm]{geometry}\n"
  header = header "\\usepackage{varwidth}\n"
  header = header "\\usepackage[active,tightpage]{preview}\n"
  header = header "\\usepackage[normalem]{ulem}\n"
  header = header "\n"
  header = header "\\setlength{\\fboxsep}{0pt}\n"
  header = header "\n"
  header = header "\\newcommand{\\bgcolor}[2]{\\colorbox{#1}{\\vphantom{Ay}#2}}\n"
  header = header "\n"
  header = header "\\PreviewEnvironment{varwidth}\n"
  header = header "\n"
  # FG and BG only if they are set (FG is given to each line, see fmt_document)
  if (EXPORT_FG_BG["FG"] != "") {
    header = header latex_definecolor("FG", EXPORT_FG_BG["FG"])
  }
  if (EXPORT_FG_BG["BG"] != "") {
    header = header latex_definecolor("BG", EXPORT_FG_BG["BG"])
  }
  header = header latex_definecolor("ATTENTION", latex_hex_color(COLOR_ATTENTION))
  header = header latex_definecolor("SECTION", latex_hex_color(COLOR_SECTION))
  header = header latex_definecolor("DEPRECATED", latex_hex_color(COLOR_DEPRECATED))
  header = header latex_definecolor("DEFAULT", latex_hex_color(COLOR_DEFAULT))
  header = header latex_definecolor("BACKTICKS", latex_hex_color(COLOR_BACKTICKS))
  header = header "\n"
  header = header "\\pagestyle{empty}\n"
  header = header "\\begin{document}\n"
  header = header "\n"
  header = header "\\begin{varwidth}{\\linewidth}\n"
  if (EXPORT_FG_BG["BG"] != "") {
    header = header "\\pagecolor{" color_name("BG") "}\n"
  }
  header = header "\n"
  header = header "\\begin{alltt}"
  return header
}

# <, > and & would be interpreted as HTML markup (& first, so that the & of the other
# replacements is not escaped again; string_replace because & is special in gsub)
function html_escape(text) {
  text = string_replace("&", "&amp;", text)
  text = string_replace("<", "&lt;", text)
  return string_replace(">", "&gt;", text)
}

# In \begin{alltt} ... \end{alltt}, only \, { and } are special. The backslashes go through
# PLACEHOLDER: escaping them first would escape the braces of \textbackslash{}, and
# escaping them last would escape the backslashes of \{ and \}.
function latex_escape(text) {
  text = string_replace("\\", PLACEHOLDER, text)
  gsub(/\{/, "\\{", text)
  gsub(/\}/, "\\}", text)
  return string_replace(PLACEHOLDER, "\\textbackslash{}", text)
}

# ---------------------------------------------------------------------------------------
# What rendering calls (with fmt_color_code)
# ---------------------------------------------------------------------------------------

# text with the escapes of the output format (none in ANSI), applied before the colors are
# added
function fmt_escape(text) {
  if (OUTPUT_FORMAT == "HTML") {
    return html_escape(text)
  } else if (OUTPUT_FORMAT == "LATEX") {
    return latex_escape(text)
  }
  return text
}

# Color text with color_code (see fmt_color_code), each line on its own (color_code ...
# COLOR_RESET_CODE), so that no color group crosses a line break: in LaTeX, varwidth cannot
# crop the page to the text of such a group. Empty lines are not colored. In ANSI, a reset
# inside text (e.g., after text in backticks) turns off all the colors: color_code is
# restored after it.
function fmt_color(text, color_code, #locals
                   n, lines, k) {
  if (color_code == "") {
    return text
  }
  if (OUTPUT_FORMAT == "ANSI") {
    text = string_replace(COLOR_RESET_CODE, COLOR_RESET_CODE color_code, text)
  }
  n = split(text, lines, "\n")
  for (k = 1; k <= n; k++) {
    if (lines[k] != "") {
      lines[k] = color_code lines[k] COLOR_RESET_CODE
    }
  }
  return join(lines, n, "\n")
}

# The document: body between OUTPUT_HEADER and OUTPUT_FOOTER. In LaTeX, the default text
# color (FG) is given to each line: with one \color for the whole documentation, varwidth
# would not crop the page to the text.
function fmt_document(body) {
  if (OUTPUT_FORMAT == "LATEX" && EXPORT_FG_BG["FG"] != "") {
    body = fmt_color(body, "\\textcolor{" color_name("FG") "}{")
  }
  return OUTPUT_HEADER body OUTPUT_FOOTER
}

#### Parsing
# The parser follows misc/docs/parser-model.tex, whose names the comments use (in ASCII: l_i
# is the logical line i, r_bar the bar over r, ...). A physical line is joined with the next
# ones while it ends with a backslash (parser_join); each logical line is then processed by
# parser_process: observed (parser_obs), the state updated (parser_step), a documented anchor
# recorded in the interface variables (record_anchor, see init_globals), and the pending text
# updated (parser_carry). The rules at the end of the section run it.

# Record a warning about the Makefiles (printed before the docs). kind is "target",
# "variable" or "file".
function add_warning(kind, message) {
  WARNINGS[++WARNING_COUNT] = message
  WARNING_KINDS[WARNING_COUNT] = kind
}

# A last line that ends with a backslash cannot be joined, so it is not parsed. awk has no
# hook at the end of a file: this is called at the next file and in END. A continued recipe
# line is not reported (its rule ends with the file anyway).
function warn_about_continued_last_line() {
  if (PARSER_JOINER["joining"] &&
      !(PARSER_STATE["r"] && substr(PARSER_JOINER["pending"], 1, 1) == PARSER_STATE["c"])) {
    add_warning("file", sprintf("[%s] the last line ends with a backslash",
                                PARSER_CONTEXT["file"]))
  }
}

# the tag of a doc line (##, ##! or ##%), or "" if it does not start with one
function get_doc_tag(string) {
  return match(string, TAG_REGEX) ? substr(string, 1, RLENGTH) : ""
}

# Observe a logical line, without the state (questions 2-7 of the model, and the comment that
# question 8 reads; question 1 depends on the state: see parser_obs). Fill obs with:
#   obs["kind"]     assignment, rule, special rule, neutral, banner, section, doc, other
#   obs["anchor"]   target or variable (assignment and rule), "" otherwise
#   obs["name"]     the name of the anchor, as written in the line
#   obs["comment"]  the comment, from its # to the end of the line ("" if none)
# The examples are in test/parser.spec (see test/unit/test_parser.awk).
function parser_observe(line, obs, #locals
                        first_word, define_name) {
  split("", obs)
  obs["kind"] = ""
  obs["anchor"] = ""
  obs["name"] = ""
  obs["comment"] = ""

  if (line ~ /^[ \t]*$/) {
    obs["kind"] = "neutral"
    return
  }
  if (line ~ /^[ \t]*#/) {
    obs["kind"] = line ~ /^[ \t]*###+[ \t]*$/ ? "banner" : \
                  line ~ /^[ \t]*##@/ ? "section" : \
                  line ~ /^[ \t]*##/ ? "doc" : "neutral"
    return
  }

  parser_scan(line, obs) # kind: assignment, rule or ""
  if (obs["kind"] == "assignment") {
    return
  }

  first_word = line
  sub(/^[ \t]+/, "", first_word)
  sub(/[ \t(].*$/, "", first_word)
  define_name = parser_define_name(line)
  if (first_word ~ /^(ifeq|ifneq|ifdef|ifndef|else|endif)$/) {
    parser_clear(obs, "neutral")
  } else if (define_name != "") { # before the directives: `export define V`
    parser_clear(obs, "assignment")
    obs["anchor"] = "variable"
    obs["name"] = define_name
    match(line, /^[ \t]*((export|override|private)[ \t]+)*/)
    obs["override"] = (" " substr(line, 1, RLENGTH)) ~ /[ \t]override[ \t]/
  } else if (first_word ~ /^(include|-include|sinclude|vpath|export|unexport|undefine|endef)$/) {
    parser_clear(obs, "other")
  } else if (obs["kind"] == "rule") {
    if ((obs["name"] ":") ~ SPECIAL_TARGETS_REGEX) {
      parser_clear(obs, "special rule")
    }
  } else {
    parser_clear(obs, "other")
  }
}

# set the kind of obs, without anchor, name and comment
function parser_clear(obs, kind) {
  obs["kind"] = kind
  obs["anchor"] = ""
  obs["name"] = ""
  obs["comment"] = ""
}

# the name of the variable of a define line (e.g., `override define V :=`), "" if not one
function parser_define_name(line, #locals
                            rest) {
  rest = line
  sub(/^[ \t]*((export|override|private)[ \t]+)*/, "", rest)
  if (rest !~ /^define[ \t]+[^ \t]/) {
    return ""
  }
  sub(/^define[ \t]+/, "", rest)
  sub(/[ \t].*$/, "", rest)
  sub(/(:::=|::=|:=|\+=|\?=|!=|=)$/, "", rest) # an operator without a blank before it
  return rest
}

# Fill obs with the structure of a line (the searches of the lexical layer): obs["kind"] is
# assignment, rule or "" (neither), with obs["anchor"], obs["name"] and obs["comment"]; for
# an assignment to a variable, also obs["operator"] and obs["value"] (without its comment,
# leading blanks removed). The searches run on the masked line; the texts are cut from the
# line.
function parser_scan(line, obs, #locals
                     masked, p, c, q, start, end, after, rest, hit, name) {
  masked = parser_mask(line)
  p = match(masked, /[#=:]/)
  if (!p) {
    return
  }
  c = substr(masked, p, 1)
  if (c == "#") {
    obs["comment"] = substr(line, p)
    return
  }
  q = p # the end of a run of colons
  while (substr(masked, q + 1, 1) == ":") {
    q++
  }
  if (c == "=" || substr(masked, q + 1, 1) == "=") { # an operator before any separating colon
    start = (c == "=" && p > 1 && substr(masked, p - 1, 1) ~ /[?+!]/) ? p - 1 : p
    name = parser_variable_name(substr(line, 1, start - 1), substr(masked, 1, start - 1))
    if (name != "") {
      end = c == "=" ? p : q + 1 # the = of the operator
      obs["kind"] = "assignment"
      obs["anchor"] = "variable"
      obs["name"] = name
      obs["override"] = parser_has_override(substr(masked, 1, start - 1))
      obs["comment"] = parser_rest_from(line, masked, end, "#")
      obs["operator"] = substr(line, start, end - start + 1)
      obs["value"] = substr(line, end + 1, length(line) - end - length(obs["comment"]))
      sub(/^[ \t]+/, "", obs["value"])
    }
    return
  }

  # p is the separating colon (:, :: or &:)
  name = substr(line, 1, p - 1)
  sub(/[ \t]*&$/, "", name)
  sub(/^[ \t]+/, "", name)
  sub(/[ \t]+$/, "", name)
  if (name == "") {
    return
  }
  obs["kind"] = "rule"
  obs["anchor"] = "target"
  obs["name"] = name
  obs["double"] = q > p # a double-colon rule
  obs["grouped"] = substr(line, 1, p - 1) ~ /&[ \t]*$/ # grouped targets (&:)
  after = q + 1
  rest = substr(masked, after) # not inline in match(): misc/onetrue_awk_bug_20261123.awk
  hit = match(rest, /[#;=]/)
  if (!hit) {
    return
  }
  hit += after - 1
  c = substr(masked, hit, 1)
  if (c == "#") {
    obs["comment"] = substr(line, hit)
  } else if (c == "=") { # a target-specific assignment: after its operator, ; hides #
    obs["kind"] = "assignment"
    obs["comment"] = parser_rest_from(line, masked, hit, "#;")
  }
}

# The comment of line after position p: from the first character of chars found in masked
# after p, if it is a #; "" otherwise. (One match, not a loop over the characters: in some
# awks, e.g., the one true awk and wak, substr and length take time linear in the length of
# the string, so such a loop is quadratic.)
function parser_rest_from(line, masked, p, chars, #locals
                          rest, k) {
  rest = substr(masked, p + 1)
  k = match(rest, chars == "#" ? "#" : "[#;]")
  return (k && substr(rest, k, 1) == "#") ? substr(line, p + k) : ""
}

# true if the left side of an assignment has the qualifier override (before its name, the
# last word)
function parser_has_override(text) {
  sub(/[ \t]*[^ \t]+[ \t]*$/, "", text)
  return (" " text " ") ~ /[ \t]override[ \t]/
}

# The variable of the left side of an assignment, with its qualifiers (export, override,
# private): the single word after them, "" if there is not exactly one word. The words are
# found in masked (a reference is part of a word), the name is cut from text.
function parser_variable_name(text, masked, #locals
                              word_start, before, n, words, k) {
  if (!match(masked, /[^ \t]+[ \t]*$/)) {
    return ""
  }
  word_start = RSTART
  before = substr(masked, 1, word_start - 1)
  n = split(before, words, /[ \t]+/)
  for (k = 1; k <= n; k++) {
    if (words[k] != "" && words[k] !~ /^(export|override|private)$/) {
      return ""
    }
  }
  text = substr(text, word_start)
  sub(/[ \t]+$/, "", text)
  return text
}

# The line with what GNU Make does not read as syntax replaced by _, so that the searches can
# look for #, :, = and ; directly. The masked line has the same length as the line (the
# positions are the same). Masked:
#   * a reference: from $( or ${ to its matching bracket (only the same kind of bracket
#     nests), or to the end of the line if it is not closed
#   * $ and any other character that follows it: a one-character reference (e.g., $@, $#;
#     $$ is a literal $)
#   * the escape pairs \\, \#, \: and \; (read from left to right: in a run of backslashes,
#     only an odd last one escapes the character that follows)
function parser_mask(line, #locals
                     n, k, c, next_char, end, out, rest) {
  if (!index(line, "$") && !index(line, "\\")) {
    return line # nothing to mask (the usual case)
  }
  n = length(line)
  out = ""
  k = 1
  while (k <= n) {
    # the characters up to the next $ or \ are copied in one piece (see parser_rest_from)
    rest = substr(line, k)
    if (!match(rest, /[$\\]/)) {
      return out rest
    }
    if (RSTART > 1) {
      out = out substr(rest, 1, RSTART - 1)
      k += RSTART - 1
    }
    c = substr(line, k, 1)
    next_char = substr(line, k + 1, 1)
    if (c == "$" && (next_char == "(" || next_char == "{")) {
      end = parser_reference_end(line, k)
      out = out repeated_string("_", end - k + 1)
      k = end + 1
    } else if ((c == "$" && next_char != "") ||
               (c == "\\" && next_char != "" && index("\\#:;", next_char) > 0)) {
      out = out "__"
      k += 2
    } else {
      out = out c
      k++
    }
  }
  return out
}

# The end of the reference $( or ${ at position k of line: the position of its matching
# bracket (only the same kind of bracket nests), or the end of the line if it is not closed.
# (match could jump from bracket to bracket instead of reading each character, but there is
# no point: a reference is short, so it would be faster only on lines of thousands of
# references, which Makefiles do not have.)
function parser_reference_end(line, k, #locals
                              n, opening, closing, depth, c) {
  n = length(line)
  opening = substr(line, k + 1, 1)
  closing = opening == "(" ? ")" : "}"
  depth = 0
  for (k = k + 1; k <= n; k++) {
    c = substr(line, k, 1)
    if (c == opening) {
      depth++
    } else if (c == closing) {
      depth--
      if (depth == 0) {
        return k
      }
    }
  }
  return n
}

# ---------------------------------------------------------------------------------------
# The model: its arrays are
#   state   the state x_i: state["r"] (a rule is open), state["d"] (a doc is pending),
#           state["s"] (a section is pending), state["c"] (the recipe prefix)
#   data    the pending text: data["doc", k], k = 1..data["dn"] (D_i, data["doc_tag"] the
#           tag of its first line) and data["section", k], k = 1..data["sn"] (S_i). dn and sn
#           are the lengths of D_i and S_i: D_i is not empty if and only if d_i = 1 (and S_i
#           if and only if s_i = 1)
#   obs     the observation of l_i (see parser_obs)
# ---------------------------------------------------------------------------------------

# x_0 = (0, 0, 0, c_0), D_0 = S_0 = empty (c_0: the RECIPEPREFIX option, a tab by default)
function parser_init(state, data, prefix) {
  split("", state)
  state["r"] = 0
  state["d"] = 0
  state["s"] = 0
  state["c"] = prefix == "" ? "\t" : substr(prefix, 1, 1)
  split("", data)
  data["dn"] = 0
  data["sn"] = 0
}

# At the first line of a file (b_i = 1), the rule is closed and the doc dropped, with its text
# (a section and the recipe prefix carry over):
#   r_bar_{i-1} = 0 if b_i = 1, r_{i-1} otherwise
#   d_bar_{i-1} = 0 if b_i = 1, d_{i-1} otherwise
#   D_bar_{i-1} = empty if b_i = 1, D_{i-1} otherwise
function parser_file_start(state, data) {
  state["r"] = 0
  state["d"] = 0
  data["dn"] = 0
}

# (k_i, a_i, c_i; T_i, A_i) = obs(l_i, r_bar_{i-1}, c_{i-1}): parser_observe, plus question 1
# (a recipe line: inside a rule, the line starts with the recipe prefix), question 8 and
# question 9. state is read, not changed. Besides the fields of parser_observe, obs gets:
#   obs["inline"]      a_i: the comment is an inline doc
#   obs["prefix"]      c_i: the recipe prefix after the line (see parser_new_prefix)
#   obs["text"]        T_i: the text of a doc or section line, without its token
#   obs["inline_doc"]  A_i: the inline doc, without its token ("" if none)
#   obs["tag"]         the token of a doc line or of the inline doc: ##, ##! or ##%
function parser_obs(line, state, obs) {
  if (state["r"] && substr(line, 1, 1) == state["c"]) {
    split("", obs)
    parser_clear(obs, "recipe")
  } else {
    parser_observe(line, obs)
  }
  obs["inline"] = obs["anchor"] != "" && obs["comment"] ~ /^##/ && obs["comment"] !~ /^##@/
  obs["prefix"] = state["c"]
  # (a define has no operator: its value is on the next lines)
  if (obs["kind"] == "assignment" && obs["anchor"] == "variable" &&
      obs["name"] == ".RECIPEPREFIX" && ("operator" in obs)) {
    obs["prefix"] = parser_new_prefix(state["c"], obs["operator"], obs["value"])
  }
  obs["text"] = ""
  obs["inline_doc"] = ""
  obs["tag"] = ""
  if (obs["kind"] == "doc") {
    obs["text"] = line
    sub(/^[ \t]+/, "", obs["text"])
    obs["tag"] = get_doc_tag(obs["text"])
    sub(TAG_REGEX, "", obs["text"])
  } else if (obs["kind"] == "section") {
    obs["text"] = line
    sub(/^[ \t]*##@/, "", obs["text"])
  } else if (obs["inline"]) {
    obs["inline_doc"] = obs["comment"]
    obs["tag"] = get_doc_tag(obs["inline_doc"])
    sub(TAG_REGEX, "", obs["inline_doc"])
  }
}

# The recipe prefix after an assignment to .RECIPEPREFIX, from the prefix before it: the
# first character of the value (a tab if it is empty). With += the first character does not
# change; with != or an expanded reference (:=, ::=), the value is not known: the prefix does
# not change either.
function parser_new_prefix(prefix, operator, value) {
  if (operator == "+=" || operator == "!=" || (operator ~ /^:+=$/ && index(value, "$") > 0)) {
    return prefix
  }
  return value == "" ? "\t" : substr(value, 1, 1)
}

# (r_i, d_i, s_i, e_i) = step(r_bar_{i-1}, d_bar_{i-1}, s_{i-1}, k_i, a_i): state holds
# x_{i-1} and becomes x_i; return e_i. The step never reads the text of the line.
function parser_step(state, obs, #locals
                     k, e) {
  k = obs["kind"]
  # e_i = 1 if k_i in {rule, assignment} and (d_bar_{i-1} = 1 or a_i = 1), 0 otherwise
  e = (k == "rule" || k == "assignment") && (state["d"] || obs["inline"])
  if (k == "recipe" || k == "rule" || k == "special rule") {
    state["r"] = 1                   # r_i = 1             if k_i in {recipe, rule, special rule}
  } else if (k == "assignment" || k == "other") {
    state["r"] = 0                   #       0             if k_i in {assignment, other}
  }                                  #       r_bar_{i-1}   otherwise
  if (k == "doc") {
    state["d"] = 1                   # d_i = 1             if k_i = doc
  } else if (k == "recipe" || k == "banner" || k == "rule" || k == "assignment" ||
             k == "other") {
    state["d"] = 0                   #       0             if k_i in {recipe, banner, rule,
  }                                  #                       assignment, other}
                                     #       d_bar_{i-1}   otherwise
  if (k == "section") {
    state["s"] = 1                   # s_i = 1             if k_i = section
  } else if (e) {
    state["s"] = 0                   #       0             if e_i = 1
  }                                  #       s_{i-1}       otherwise
  state["c"] = obs["prefix"]         # c_i (from the observation)
  return e
}

# The pending text after the step: data holds D_bar_{i-1} and S_{i-1}, and becomes D_i and
# S_i, from the kind k_i and the text T_i of the line, and the new state x_i.
function parser_carry(data, state, obs) {
  if (obs["kind"] == "doc") {
    if (data["dn"] == 0) {
      data["doc_tag"] = obs["tag"]               # the tag of the doc: that of its first line
    }
    data["doc", ++data["dn"]] = obs["text"]      # D_i = D_bar_{i-1} + T_i   if k_i = doc
  } else if (!state["d"]) {
    data["dn"] = 0                               #       empty               if d_i = 0
  }                                              #       D_bar_{i-1}         otherwise
  if (obs["kind"] == "section") {
    data["section", ++data["sn"]] = obs["text"]  # S_i = S_{i-1} + T_i       if k_i = section
  } else if (!state["s"]) {
    data["sn"] = 0                               #       empty               if s_i = 0
  }                                              #       S_{i-1}             otherwise
}

# Process the logical line l_i (line, from the physical line line_number of the file): state
# and data hold x_{i-1} and D_bar_{i-1}, S_{i-1} (after parser_file_start at the first line of
# a file), and become x_i and D_i, S_i. The record of a documented anchor reads the state
# before the step (x_{i-1}, kept in before) and the pending text before parser_carry.
function parser_process(state, data, context, obs, line, line_number, #locals
                        before, e) {
  parser_obs(line, state, obs)     # (k_i, a_i, c_i; T_i, A_i) = obs(l_i, r_bar_{i-1}, c_{i-1})
  copy_array(state, before)        # x_{i-1}
  e = parser_step(state, obs)      # (r_i, d_i, s_i, e_i) = step(...)
  if (e) {
    record_anchor(context, obs, before, data, line_number)
  }
  parser_carry(data, state, obs)   # (D_i, S_i)
}

# Record a documented anchor (e_i = 1) in the interface, in the file order, with (before is
# x_{i-1}; data holds D_bar_{i-1} and S_{i-1}):
#   doc     = D_bar_{i-1} if d_bar_{i-1} = 1, A_i otherwise (with the tag of its first line)
#   section = S_{i-1} if s_{i-1} = 1, none otherwise
# Outside the model: the name of a target (see form_target_name), and the warning about a
# redefined doc (context holds the file and the anchors already documented).
function record_anchor(context, obs, before, data, line_number, #locals
                       kind, name) {
  kind = obs["anchor"]
  name = kind == "target" ? form_target_name(context, obs) : obs["name"]
  if (("seen", kind, name) in context) {
    add_warning(kind, sprintf("[%s:%s] redefined docs of %s: %s", context["file"],
                              line_number, kind, name))
  }
  context["seen", kind, name] = 1
  ANCHOR_COUNT++
  ANCHORS[ANCHOR_COUNT, "kind"] = kind
  ANCHORS[ANCHOR_COUNT, "name"] = name
  if (before["d"]) {
    ANCHORS[ANCHOR_COUNT, "doc"] = data_lines(data, "doc", data["dn"])
    ANCHORS[ANCHOR_COUNT, "tag"] = data["doc_tag"]
  } else {
    ANCHORS[ANCHOR_COUNT, "doc"] = obs["inline_doc"]
    ANCHORS[ANCHOR_COUNT, "tag"] = obs["tag"]
  }
  if (before["s"]) {
    ANCHORS[ANCHOR_COUNT, "section"] = data_lines(data, "section", data["sn"])
  }
  if (("override" in obs) && obs["override"]) { # the command line cannot change it
    ANCHORS[ANCHOR_COUNT, "override"] = 1
  }
}

# the lines data[key, 1..n] joined with \n
function data_lines(data, key, n, #locals
                    k, lines) {
  lines = ""
  for (k = 1; k <= n; k++) {
    lines = k == 1 ? data[key, k] : lines "\n" data[key, k]
  }
  return lines
}

# The name of a documented target as displayed: blanks collapsed (GNU Make reads any run of
# blanks between names as one separator), & after grouped targets, ~N after the Nth
# documented rule of a double-colon target (counted across files, in context)
function form_target_name(context, obs, #locals
                          name) {
  name = obs["name"]
  gsub(/[ \t]+/, " ", name)
  if (obs["grouped"]) {
    name = name "&"
  }
  if (obs["double"]) {
    context["dc", name] = array_get(context, "dc" SUBSEP name) + 1
    name = name DOUBLE_COLON_SEPARATOR context["dc", name]
  }
  return name
}

# ---------------------------------------------------------------------------------------
# The input of the model: the logical lines. joiner holds the line being joined:
# joiner["joining"] (a line continues on the next one), joiner["pending"] (its text so far),
# joiner["start"] (the number of its first physical line) and, when it is complete,
# joiner["line"].
# ---------------------------------------------------------------------------------------

# At the first line of a file: a line continued at the end of the previous file is dropped
function parser_join_init(joiner) {
  split("", joiner)
  joiner["joining"] = 0
  joiner["pending"] = ""
}

# Add a physical line (number line_number in its file): return 1 when a logical line is
# complete (in joiner["line"], from the physical line joiner["start"]), 0 when the line
# continues on the next one (an odd number of final backslashes, recipe lines included). As
# in GNU Make, the backslash, the newline and the blanks around them become one space. The
# searches run on the physical line only, not on the text joined so far (see
# parser_rest_from): a continued line of only blanks adds nothing.
function parser_join(joiner, physical, line_number, #locals
                     stripped) {
  sub(/\r$/, "", physical) # CRLF line endings
  if (!joiner["joining"]) {
    joiner["start"] = line_number
  }
  if (!has_odd_terminal_backslashes(physical)) {
    if (joiner["joining"]) {
      sub(/^[ \t]+/, "", physical)
      physical = joiner["pending"] " " physical
      joiner["joining"] = 0
    }
    joiner["line"] = physical
    return 1
  }
  physical = substr(physical, 1, length(physical) - 1) # without the backslash
  stripped = physical
  sub(/[ \t]+$/, "", stripped)
  if (joiner["joining"]) {
    sub(/^[ \t]+/, "", stripped)
    if (stripped != "") {
      joiner["pending"] = joiner["pending"] " " stripped
    }
  } else {
    # a recipe line of only its prefix (e.g., a tab, then the backslash) keeps the prefix
    joiner["pending"] = stripped == "" ? substr(physical, 1, 1) : stripped
    joiner["joining"] = 1
  }
  return 0
}

# stdin is named - (POSIX leaves FILENAME unspecified for it; most awks set it to -)
FNR == 1 {
  warn_about_continued_last_line()
  parser_join_init(PARSER_JOINER)
  parser_file_start(PARSER_STATE, PARSER_DATA) # b_i = 1
  PARSER_CONTEXT["file"] = FILENAME == "" ? "-" : FILENAME
  FILES_PROCESSED = (FILES_PROCESSED == "" ? "" : FILES_PROCESSED " ") PARSER_CONTEXT["file"]
}

{
  if (parser_join(PARSER_JOINER, $0, FNR)) {
    parser_process(PARSER_STATE, PARSER_DATA, PARSER_CONTEXT, PARSER_OBS, PARSER_JOINER["line"],
                   PARSER_JOINER["start"])
  }
}

#### Rendering
# The display of the documentation, in two stages: prepare_rendering decides what is
# displayed (the DISPLAY records), then format_documentation lays it out in the output format
# (print_documentation runs both and prints the result).

# Print the warnings recorded while parsing, except those about variables with VARS=0 (they
# are not displayed)
function print_warnings(    k) {
  for (k = 1; k <= WARNING_COUNT; k++) {
    if (!(WARNING_KINDS[k] == "variable" && !VARS)) {
      printf("WARNING: %s\n", WARNINGS[k]) > STDERR
    }
  }
}

# Fill DISPLAY from the interface and the settings: each displayed anchor once, at its first
# definition, with the doc and tag of its last one; the targets, then the variables
function prepare_rendering(    k, key, n, order, last, sections, kind) {
  split("", order)
  split("", last)
  split("", sections)
  n = 0
  for (k = 1; k <= ANCHOR_COUNT; k++) {
    key = ANCHORS[k, "kind"] SUBSEP ANCHORS[k, "name"]
    if (!(key in last)) {
      order[++n] = key
    }
    last[key] = k
  }
  DOCUMENTED_COUNT = n
  place_sections(last, sections)
  for (kind = 1; kind <= 2; kind++) {
    for (k = 1; k <= n; k++) {
      key = order[k]
      if ((ANCHORS[last[key], "kind"] == "target") == (kind == 1) && is_displayed(last[key])) {
        add_display_record(last[key], key, sections)
      }
    }
  }
}

# true if the anchor whose last definition is ANCHORS[k] is displayed: not a variable with
# VARS=0, nor a deprecated anchor with DEPRECATED=0
function is_displayed(k) {
  return (ANCHORS[k, "kind"] == "target" || VARS) && !(!DEPRECATED && ANCHORS[k, "tag"] == "##%")
}

# Give each section to the next displayed anchor after it in the Makefiles: sections[key],
# with last[key] the last definition of each anchor. Sections with no displayed anchor after
# them are dropped, consecutive ones are merged, and a later section of the same anchor
# replaces an earlier one.
function place_sections(last, sections, #locals
                        k, key, has_section, section) {
  has_section = 0
  for (k = 1; k <= ANCHOR_COUNT; k++) {
    if ((k, "section") in ANCHORS) {
      section = has_section ? section "\n" ANCHORS[k, "section"] : ANCHORS[k, "section"]
      has_section = 1
    }
    key = ANCHORS[k, "kind"] SUBSEP ANCHORS[k, "name"]
    if (has_section && is_displayed(last[key])) {
      sections[key] = section
      has_section = 0
    }
  }
}

# Add the record of an anchor to DISPLAY (k: its last definition in ANCHORS, key: its key in
# sections), with what will be displayed: its displayed name, its doc and section after DSUB,
# and its SUB values and parameters
function add_display_record(k, key, sections, #locals
                            name) {
  name = ANCHORS[k, "name"]
  DISPLAY_COUNT++
  DISPLAY[DISPLAY_COUNT, "kind"] = ANCHORS[k, "kind"]
  DISPLAY[DISPLAY_COUNT, "name"] = display_name(name)
  DISPLAY[DISPLAY_COUNT, "tag"] = ANCHORS[k, "tag"]
  DISPLAY[DISPLAY_COUNT, "doc"] = apply_doc_substitutions(ANCHORS[k, "doc"])
  if (key in sections) {
    DISPLAY[DISPLAY_COUNT, "section"] = apply_doc_substitutions(sections[key])
  }
  if ((k, "override") in ANCHORS) {
    DISPLAY[DISPLAY_COUNT, "override"] = 1
  }
  # "(fixed)": the command line cannot change a variable set with override
  DISPLAY[DISPLAY_COUNT, "label"] = DISPLAY[DISPLAY_COUNT, "name"] \
                                    (((k, "override") in ANCHORS) ? " (fixed)" : "")
  DISPLAY[DISPLAY_COUNT, "values"] = array_get(SUB_VALUES, name)
  DISPLAY[DISPLAY_COUNT, "sub_row"] = (name in SUB_VALUES) ? name : ""
}

# The displayed name of an anchor: its SUB label if it has one, otherwise its name after the
# DSUB substitutions with A:1, in order. SUB is looked up with the name as written, so DSUB
# never changes which SUB applies.
function display_name(anchor, #locals
                      k, name) {
  if (anchor in SUB_LABELS) {
    return SUB_LABELS[anchor]
  }
  for (k = 1; k <= DSUB_COUNT; k++) {
    name = DSUB_NAMES[k]
    if (DSUB_PARAM[name, "A"]) {
      anchor = string_replace(name, DSUB_VALUES[name], anchor)
    }
  }
  return anchor
}

# Apply the DSUB substitutions to the text of docs or section titles (those with D:1), in
# the order given.
function apply_doc_substitutions(text, #locals
                                 k) {
  for (k = 1; k <= DSUB_COUNT; k++) {
    if (DSUB_PARAM[DSUB_NAMES[k], "D"]) {
      text = string_replace(DSUB_NAMES[k], DSUB_VALUES[DSUB_NAMES[k]], text)
    }
  }
  return text
}

function get_separator(character, len_anchors) {
  return repeated_string(character, max(len_anchors,
                                        max(length(HEADER_TARGETS),
                                            length(HEADER_VARIABLES))))
}

function substitute_backticks_patterns(string, #locals
                                       before_match, inside_match, after_match) {
  # (gensub with a back-reference would do this in one call, but it is only in gawk)
  while (match(string, /`([^`]+)`/)) {
    before_match = substr(string, 1, RSTART - 1)
    inside_match = substr(string, RSTART + 1, RLENGTH - 2)
    after_match = substr(string, RSTART + RLENGTH)

    string = before_match fmt_color(inside_match, COLOR_BACKTICKS_CODE) after_match
  }
  return string
}

function colorize_doc_backticks(doc) {
  if (COLOR_BACKTICKS) {
    return substitute_backticks_patterns(doc)
  }
  return doc
}

# the color code of an anchor, given by the tag of its doc
function anchor_color(tag) {
  if (tag == "##!") {
    return COLOR_ATTENTION_CODE
  } else if (tag == "##%") {
    return COLOR_DEPRECATED_CODE
  }
  return COLOR_DEFAULT_CODE # ## (a doc starts with one of the three tags)
}

# A doc laid out after names of width len_anchors: the first line offset from the name, the
# next lines aligned with it, with the escapes of the output format and the colors of the
# text in backticks
function format_doc(doc, len_anchors, #locals
                    n, lines, indentation) {
  n = split(doc, lines, "\n")
  indentation = spaces(OFFSET + len_anchors) # aligned with the first line
  doc = spaces(OFFSET) join(lines, n, "\n" indentation)
  return colorize_doc_backticks(fmt_escape(doc))
}

# a section, with the escapes of the output format and the colors of the text in backticks
function format_section(section) {
  section = strip_trailing_blanks(section)
  return colorize_doc_backticks(fmt_escape(section))
}

# Return the text that follows the doc of an anchor: the values of its SUB substitution
# (space-separated, with the parameters in the row sub_row of SUB_PARAM), then a newline.
# Each value is made into an item (P before it, S after it, I before the first one, T after
# the last one instead of S); the items are on one line (M=0) or on one line each (M=1). The
# first line follows the doc (L=0) or starts on the next line (L=1).
function display_substitutions(sub_values, sub_row, len_anchors, #locals
                               values, n, k, item, lines, n_lines, initial, prefix,
                               separator, termination, indentation, next_indentation,
                               output) {
  n = split(sub_values, values, " ")
  if (SUB_PARAM[sub_row, "N"] >= 0) {
    n = min(n, SUB_PARAM[sub_row, "N"])
  }
  if (n == 0) {
    return "\n"
  }

  initial = SUB_PARAM[sub_row, "I"]
  prefix = SUB_PARAM[sub_row, "P"]
  separator = SUB_PARAM[sub_row, "S"]
  termination = SUB_PARAM[sub_row, "T"]

  n_lines = 0
  for (k = 1; k <= n; k++) {
    item = prefix values[k]
    if (k == 1) {
      item = initial item
    }
    if (k < n) {
      item = item separator
    } else {
      item = item termination
    }
    item = colorize_doc_backticks(fmt_escape(item))
    if (SUB_PARAM[sub_row, "M"] || k == 1) {
      lines[++n_lines] = item
    } else {
      lines[n_lines] = lines[n_lines] " " item
    }
  }

  # the + 1 assumes the usual space after the token (as in `## doc`), so that the values
  # line up with the text of the doc
  indentation = spaces(len_anchors + OFFSET + 1)
  output = (SUB_PARAM[sub_row, "L"] ? "\n" indentation : " ") lines[1]
  # the lines after the first are aligned with the first value (after I)
  next_indentation = indentation spaces(length(initial))
  for (k = 2; k <= n_lines; k++) {
    output = output "\n" next_indentation lines[k]
  }
  return output "\n"
}

# Return the text of DISPLAY[k], after names of width len_anchors: its section, then its name
# (colored by its tag, padded), its doc and its SUB values
function format_anchor(k, len_anchors, #locals
                       section, label, formatted_anchor, padding, color, output) {
  output = ""
  section = ((k, "section") in DISPLAY) ? format_section(DISPLAY[k, "section"]) : ""
  if (section) {
    output = fmt_color(section, COLOR_SECTION_CODE) "\n"
  }

  label = DISPLAY[k, "label"]
  formatted_anchor = fmt_escape(label)
  # the padding is measured on the label (an HTML or LaTeX escape is longer than
  # its character), then escaped too (PADDING can be any character)
  padding = fmt_escape(repeated_string(PADDING, len_anchors - length(label)))
  color = anchor_color(DISPLAY[k, "tag"])
  if (color) {
    formatted_anchor = color formatted_anchor padding COLOR_RESET_CODE
  } else {
    formatted_anchor = formatted_anchor padding
  }

  output = output formatted_anchor format_doc(DISPLAY[k, "doc"], len_anchors) \
           display_substitutions(DISPLAY[k, "values"], DISPLAY[k, "sub_row"], len_anchors)
  return strip_trailing_blanks(output)
}

# Return the documentation of the DISPLAY records (see prepare_rendering) in the output
# format: the targets, then the variables, each under a header, all names padded to the
# longest one (see fmt_document).
function format_documentation(    k, len_anchors, separator, body) {
  len_anchors = 0
  for (k = 1; k <= DISPLAY_COUNT; k++) {
    len_anchors = max(len_anchors, length(DISPLAY[k, "label"]))
  }
  separator = get_separator("-", len_anchors)

  body = ""
  for (k = 1; k <= DISPLAY_COUNT; k++) {
    if (k == 1 || DISPLAY[k, "kind"] != DISPLAY[k - 1, "kind"]) {
      if (k > 1) {
        body = body "\n" # a blank line after the targets
      }
      body = body separator "\n" \
             (DISPLAY[k, "kind"] == "target" ? HEADER_TARGETS : HEADER_VARIABLES) "\n" \
             separator "\n"
    }
    body = body format_anchor(k, len_anchors)
  }
  if (DISPLAY_COUNT > 0) {
    body = body separator "\n"
  }
  return fmt_document(body)
}

# Display the documentation (all its output is printed from here): the warnings on stderr,
# then the documentation on stdout.
function print_documentation(    document) {
  prepare_rendering()
  print_warnings() # (on stderr, before the docs)
  document = format_documentation()
  if (DISPLAY_COUNT == 0 && FILES_PROCESSED != "") {
    if (DOCUMENTED_COUNT > 0) {
      printf("WARNING: all documented targets/variables are hidden in %s\n",
             FILES_PROCESSED) > STDERR
    } else {
      printf("WARNING: no documented targets/variables in %s\n", FILES_PROCESSED) > STDERR
    }
  }
  printf("%s", document)
}

#### Flow
# BEGIN: the initialization and the options; END: the rendering (or the help).

# Initialize the global variables and process the options (the script exits here if an
# option is invalid).
BEGIN {
  init_globals()
  if (!UNIT_TEST) {
    if (process_options() > 0) {
      ABORT = 1
      exit 1
    }
    parser_init(PARSER_STATE, PARSER_DATA, RECIPEPREFIX)
  }
}

# Display the documentation (or print the help); nothing if BEGIN exited on an error
END {
  if (ABORT) {
    exit ABORT
  }
  if (!UNIT_TEST) {
    # Without a Makefile, awk reads stdin: if it is empty (e.g., < /dev/null, or Ctrl-D in
    # a terminal), print the help
    if (ARGC == 1 && NR == 0) {
      print_help()
      exit 1
    }
    warn_about_continued_last_line()
    print_documentation()
  }
}

### makefile-doc.awk ends here
