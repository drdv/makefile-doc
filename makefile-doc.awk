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
#   * All local variables of a function are declared in its signature (awk has no other way
#     to make a variable local). There are two cases (also in the unit tests):
#       * a function with parameters: the locals are on the next line, after a `#locals`
#         comment
#             function f(x, y, #locals
#                        k, n) {
#       * a function without parameters: the locals are on the same line, after four spaces
#         (awk does not accept a comment right after the parenthesis)
#             function f(    k, n) {
#   * The naming convention for global variables is:
#     * long-standing/important global variables are written in all upper case
#     * temporary variables that end-up being global (simply because of where they are
#       defined, e.g., in the pattern rules) have a prefix g_.
#   * The code is meant to run with most major awk implementations, and as a result we
#     need to stick to basic syntax. For example, we cannot use a match function with
#     a third argument (an array that stores the groups) and have to fall-back to using
#     RSTART and RLENGTH. We cannot use arrays of arrays (as in gnu awk). We cannot use
#     %* patterns, some regex features etc.
#   * awk arrays are associative: `for (key in array)` visits the keys in no defined order.
#     To store elements in a desired order, we use the keys 1, 2, 3, ... and keep an
#     additional variable that marks the end of the array: *_INDEX, the next free key (e.g.,
#     ANCHOR_ORDER_INDEX), or *_COUNT, the number of elements (e.g., WARNING_COUNT). The
#     elements are then read in order with a loop from 1 to that end.

#### Structure of the code
#   Helpers                pure functions (no global variables)
#   Global initialization  init_globals: the global variables, grouped by who writes them
#   Options                the options: defaults, checks and derived settings
#   Output formats         everything that depends on OUTPUT_FORMAT
#   Parsing                the parser that reads the Makefiles, and its helpers
#   Rendering              the display of the documentation
#   Flow                   BEGIN and END
# A function is in the section that owns the variables it writes: Options writes the
# settings, Parsing writes the interface variables (see init_globals), which Rendering
# reads. Output formats is the exception: it groups a feature, across these steps.

#### Terminology and definitions
#   * A Makefile rule (without patterns) can take one of the following forms:
#     target-name [...] [&]:[:] [prerequisites] [;] [inline recipe]
#         [recipe]
#
#     target-name [...] [&]:[:] [variable assignment]
#         [recipe]
#
#     where:
#       variable assignment: a single variable can be assigned per rule
#       prerequisites := normal-prerequisites | order-only-prerequisites
#       inline recipe := [command] [; command ...]
#       recipe := [command]
#                 [...]
#
#     with normal-prerequisites and order-only-prerequisites being space separated lists
#     of target names.
#   * Recipe: a sequence of commands executed in the shell. Here, a line that starts with
#     the recipe prefix is a recipe line if it comes after a rule and before a line that
#     closes it (see lexical_step).
#   * Target: an abstraction representing a task/goal to achieve which is defined in
#     terms of, potentially, many rules.
#     * Normal (single-colon) targets can have only one recipe and to mirror this we
#       allow for them to have only one description.
#     * double-colon targets (i.e., targets defined by double-colon rules) can have
#       multiple descriptions (as they can have multiple recipes).
#   * Target line: the top-line (the header) of a Makefile rule
#   * Target name: a (string) label for a target
#   * Description of a rule: comments starting with ##, ##! or ##% placed above the
#     target line of a rule or inline. Inline descriptions placed after an inline recipe
#     are ignored.
#   * The last rule with a description defines the description of a normal target, while
#     every double-colon rule with a description defines a new description.


### Code

#### Helpers
# Pure functions: they use no global variables.

function max(x, y) {
  return (x >= y) ? x : y
}

function min(x, y) {
  return (x <= y) ? x : y
}

# 1. An empty string means a space.
# 2. A loop rather than gsub, which would need & and \ in string to be escaped. The strings
#    here are short, so the loop costs nothing noticeable.
# 3. n must be a non-negative integer (a non-numeric n loops forever). The only n that comes
#    from the user is OFFSET, which process_options() validates before any output.
function repeated_string(string, n, #locals
                         s, k) {
  if (string == "") {
    string = " "
  }
  s = ""
  for (k = 1; k <= n; k++) {
    s = s string
  }
  return s
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

# join the elements 1..n of an array (e.g., one produced by split())
function join(array, delimiter, #locals
              string, k, n_elements) {
  string = ""
  n_elements = length_array_posix(array)
  for (k = 1; k <= n_elements; k++) {
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
# empty description). No regex: on the long runs of spaces of the padding, a regex such
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

  # The special built-in targets of GNU Make (see lexical_observe). Suffix rules, which
  # GNU Make also counts as special targets, are not among them: they are displayed.
  SPECIAL_TARGETS_REGEX = "^[ \t]*\\.(PHONY|SUFFIXES|DEFAULT|PRECIOUS|INTERMEDIATE|" \
                          "NOTINTERMEDIATE|SECONDARY|SECONDEXPANSION|DELETE_ON_ERROR|" \
                          "IGNORE|LOW_RESOLUTION_TIME|SILENT|EXPORT_ALL_VARIABLES|" \
                          "NOTPARALLEL|ONESHELL|POSIX)[ \t]*:"

  # the tag at the start of a doc line (the order of the alternatives matters for goawk
  # v1.29.1 and below, fixed in v1.30.0)
  TAG_REGEX = "^(##!|##%|##)"

  initialize_substitution_parameter_defaults()

  # the tables of the HTML and LaTeX output formats
  define_ansi_to_html_attributes()
  define_ansi_to_latex_function()

  HEADER_TARGETS = "Available targets:"
  HEADER_VARIABLES = "Command-line arguments:"
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

  # SUB and DSUB (see form_substitutions and set_dsub_scopes)
  split("", SUB_PARAMS)
  split("", SUB_LABELS)
  split("", SUB_VALUES)
  split("", DSUB_PARAMS)
  split("", DSUB_VALUES)
  split("", DSUB_NAMES)
  split("", DSUB_IN_ANCHORS)
  split("", DSUB_IN_DOCS)
  DSUB_COUNT = 0 # number of DSUB substitutions

  # ---------------------------------------------------------------------------------------
  # The interface between parsing and rendering: written while parsing (see
  # associate_data_with_anchor and add_warning), read when rendering (see
  # print_documentation). An *_INDEX is the next free index of its array.
  # ---------------------------------------------------------------------------------------

  # name -> doc (its lines without their tags, joined by \n; the last definition wins)
  split("", TARGETS_DESCRIPTION_DATA)
  split("", VARIABLES_DESCRIPTION_DATA)

  # name -> tag of the doc (##, ##! or ##%)
  split("", TARGETS_TAG)
  split("", VARIABLES_TAG)

  # the anchors in the order in which they get docs (redefinitions included), across targets
  # and variables: index -> kind SUBSEP name; and index -> the section just before (if any)
  split("", ANCHOR_ORDER)
  ANCHOR_ORDER_INDEX = 1
  split("", SECTION_BEFORE)

  # the warnings about the Makefiles: index -> message and kind (see add_warning)
  split("", WARNINGS)
  split("", WARNING_KINDS)
  WARNING_COUNT = 0

  FILES_PROCESSED = "" # the names of the files read, separated by spaces

  # ---------------------------------------------------------------------------------------
  # The state of the parser
  # ---------------------------------------------------------------------------------------

  # the lines of the pending doc and section (to be associated with the next anchor)
  split("", DESCRIPTION_DATA)
  DESCRIPTION_DATA_INDEX = 1
  split("", SECTION_DATA)
  SECTION_DATA_INDEX = 1

  # the index for the next double-colon rule with description (the key doesn't include ~k)
  split("", TARGETS_DC_COUNTER)

  CURRENT_FILE = "" # the name of the file being read, - for stdin (set at its first line)

  # the state of the parser (see lexical_init, called in BEGIN once RECIPEPREFIX is known) and
  # the observation of the last logical line (see lexical_obs)
  split("", PARSER_STATE)
  split("", PARSER_OBS)

  # ---------------------------------------------------------------------------------------
  # The state of the rendering: written by prepare_rendering (the anchors to display and
  # their sections), and while printing
  # ---------------------------------------------------------------------------------------

  # the documented anchors, once each, in file order: index -> name (set by
  # build_anchor_lists)
  split("", TARGETS)
  TARGETS_INDEX = 1
  split("", VARIABLES)
  VARIABLES_INDEX = 1

  # name -> section (set by place_sections)
  split("", TARGETS_SECTION_DATA)
  split("", VARIABLES_SECTION_DATA)

  split("", SUB_PARAMS_CURRENT) # the parameters of the substitution being displayed
  OUTPUT_BODY = "" # the documentation being printed (see append_output)
}

function initialize_substitution_parameter_defaults() {
  SUB_PARAMS_DEFAULTS["L"] = 1 # 0: start display on current line, 1: start display on next line
  SUB_PARAMS_DEFAULTS["M"] = 1 # 1: multi-line display, 0: single-line display
  SUB_PARAMS_DEFAULTS["N"] = -1 # max number of elements to display (-1 means no limit)
  SUB_PARAMS_DEFAULTS["S"] = "" # separator
  SUB_PARAMS_DEFAULTS["P"] = "" # prefix
  SUB_PARAMS_DEFAULTS["I"] = "" # initial string, e.g., (
  SUB_PARAMS_DEFAULTS["T"] = "" # termination string, e.g., )
}

#### Options
# The options given with -v: their defaults, their checks and the settings derived from them
# (those of the output formats are in Output formats).

# Process the user options (called from BEGIN, but not in unit-test mode: it exits on an
# invalid option, and an exit in BEGIN would end the unit test before its checks run).
# Every invalid option is reported, then the script exits with status 1 without any other
# output.
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
  form_substitutions(SUB "", SUB_PARAMS, SUB_LABELS, SUB_VALUES, sub_names, 0)
  form_substitutions(DSUB "", DSUB_PARAMS, dummy_array_labels, DSUB_VALUES, DSUB_NAMES, 1)
  DSUB_COUNT = length_array_posix(DSUB_NAMES)
  set_dsub_scopes()

  report_assignment_operands()

  if (OPTION_ERRORS > 0) {
    ABORT = 1
    exit 1
  }
}

# Report an invalid value of an option. The script goes on, so that all the invalid options
# are reported, and stops at the end of process_options().
function option_error(message) {
  printf("ERROR: %s\n", message) > STDERR
  OPTION_ERRORS++
}

# Report the operands that awk takes for assignments, e.g., VARS=0 (see option_error). awk
# makes such an assignment only when it reaches the operand, i.e., after BEGIN, where the
# options are validated and used: options must be given with -v. Assignments to other
# variables are reported too (they could only change the internal state of the script).
function report_assignment_operands(    k) {
  for (k = 1; k < ARGC; k++) {
    if (ARGV[k] ~ /^[A-Za-z_][A-Za-z0-9_]*=/) {
      option_error(sprintf("'%s' is an assignment: give options with -v (-v %s)",
                           ARGV[k], ARGV[k]))
    }
  }
}

# Parse spec, the value of the option SUB or DSUB (substitutions separated by ;):
# SUB:  NAME:VALUES, NAME:LABEL:VALUES or NAME::VALUES (the first two colons are
#       separators; an empty label is no label)
# DSUB: NAME:VALUE (only the first colon is a separator, no_labels is set)
# Both can start with parameters, <p1:v1,...> (see the validate_*_params functions).
# Everything after the last separator is the value, so it can contain colons.
#
# Caveat: for SUB, NAME:A:B is always read as NAME:LABEL:VALUES, so A is the label.
# To give a value that contains a colon without renaming, leave the label empty:
# t::/a:b gives the value /a:b, while t:/a:b gives the label /a and the value b.
#
# Empty items (e.g., after a trailing ;) are skipped. Invalid items are reported (see
# option_error) and skipped: no colon, an empty name, invalid parameters, a name that is
# already given.
function form_substitutions(spec, sub_params_array, sub_labels_array,
                            sub_values_array, sub_names_array, no_labels, #locals
                            split_substitutions, k, n, string, substitution_params,
                            substitution_rest, name, label, values, colon,
                            has_label, n_substitutions, option) {
  split("", sub_params_array)
  split("", sub_labels_array)
  split("", sub_values_array)
  split("", sub_names_array) # names in the order they are given

  option = no_labels ? "DSUB" : "SUB"
  n = 0
  n_substitutions = split(spec, split_substitutions, ";")
  for (k = 1; k <= n_substitutions; k++) {
    string = split_substitutions[k]
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
    if (no_labels) {
      validate_dsub_params(name, substitution_params)
    } else {
      validate_substitution_params(name, substitution_params)
    }

    if (name in sub_values_array) {
      option_error(sprintf("%s: '%s' is given more than once", option, name))
      continue
    }

    sub_names_array[++n] = name
    sub_params_array[name] = substitution_params
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
                                   temp_placeholder, k, n, n_pairs, key_values, pair, key) {
  split("", params)
  split("", keys)
  temp_placeholder = "\034" # the "file separator" ASCII control character

  # temporarily replace escaped commas
  gsub(/\\,/, temp_placeholder, string)
  n_pairs = split(string, key_values, ",")
  n = 0
  for (k = 1; k <= n_pairs; k++) {
    if (key_values[k] ~ /^[ \t]*$/) {
      continue # an empty pair, e.g., after a trailing comma
    }
    gsub(temp_placeholder, ",", key_values[k]) # restore commas
    split(key_values[k], pair, ":")
    key = strip_start_end_spaces_tabs(pair[1])
    params[key] = substr(key_values[k], length(pair[1]) + 2) # after the first colon
    keys[++n] = key
  }
  return n
}

# Report the invalid parameters of the substitution of name (see option_error)
function validate_substitution_params(name, string_with_parameters, #locals
                                      params, keys, k, n, key, value, seen) {
  split("", seen)
  n = parse_substitution_params(string_with_parameters, params, keys)
  for (k = 1; k <= n; k++) {
    key = keys[k]
    value = strip_start_end_spaces_tabs(params[key])
    if (key in seen) {
      option_error(sprintf("SUB: parameter %s of %s is given more than once", key, name))
      continue
    }
    seen[key] = 1
    if (!(key in SUB_PARAMS_DEFAULTS)) {
      option_error(sprintf("SUB: unknown parameter %s of %s (use L, M, N, S, P, I or T)",
                           key, name))
    } else if ((key == "L" || key == "M") && !is_bool(value)) {
      option_error(sprintf("SUB: parameter %s of %s should be 0 or 1", key, name))
    } else if (key == "N" && value !~ /^(-1|[0-9]+)$/) {
      option_error(sprintf("SUB: parameter N of %s should be -1 or a non-negative integer",
                           name))
    }
  }
}

# Report the invalid parameters of the DSUB substitution of name (see option_error):
#   A  0: (default) the names of anchors are not changed, 1: name is replaced in them too
#   D  0: the docs and section titles are not changed, 1: (default) name is replaced in them
function validate_dsub_params(name, string_with_parameters, #locals
                              params, keys, k, n, key, value, a, d, seen) {
  a = 0
  d = 1
  split("", seen)
  n = parse_substitution_params(string_with_parameters, params, keys)
  for (k = 1; k <= n; k++) {
    key = keys[k]
    value = strip_start_end_spaces_tabs(params[key])
    if (key in seen) {
      option_error(sprintf("DSUB: parameter %s of %s is given more than once", key, name))
      continue
    }
    seen[key] = 1
    if (key != "A" && key != "D") {
      option_error(sprintf("DSUB: unknown parameter %s of %s (use A or D)", key, name))
    } else if (!is_bool(value)) {
      option_error(sprintf("DSUB: parameter %s of %s should be 0 or 1", key, name))
    } else if (key == "A") {
      a = value + 0
    } else {
      d = value + 0
    }
  }
  if (!a && !d) {
    option_error(sprintf("DSUB: %s is replaced nowhere (A and D are both 0)", name))
  }
}

# Set where each name of DSUB is replaced: DSUB_IN_ANCHORS[name] (parameter A, default 0)
# and DSUB_IN_DOCS[name] (parameter D, default 1). The parameters have already been
# checked by validate_dsub_params.
function set_dsub_scopes(    k, name, params, keys) {
  split("", DSUB_IN_ANCHORS)
  split("", DSUB_IN_DOCS)
  for (k = 1; k <= DSUB_COUNT; k++) {
    name = DSUB_NAMES[k]
    parse_substitution_params(array_get(DSUB_PARAMS, name), params, keys)
    DSUB_IN_ANCHORS[name] = ("A" in params) ? params["A"] + 0 : 0
    DSUB_IN_DOCS[name] = ("D" in params) ? params["D"] + 0 : 1
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
# header and footer.

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

  COLOR_DEFAULT_CODE = define_color(COLOR_DEFAULT, "DEFAULT")
  COLOR_ATTENTION_CODE = define_color(COLOR_ATTENTION, "ATTENTION")
  COLOR_DEPRECATED_CODE = define_color(COLOR_DEPRECATED, "DEPRECATED")
  COLOR_SECTION_CODE = define_color(COLOR_SECTION, "SECTION")
  COLOR_BACKTICKS_CODE = define_color(COLOR_BACKTICKS, "BACKTICKS")
  COLOR_RESET_CODE = define_color(-1)
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

# The user can change the colors of the parameters 30-37, 40-47, 90-97 and 100-107 and set
# FG and BG. Format: ANSI_PARAM:HEX_COLOR[,...] (invalid entries are reported, see
# option_error).
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

# ansi_color_param:
# == 0: no color
#  > 0: some color
#  < 0: reset token  (the user cannot set -1 from outside, see validate_ansi_param())
function define_color(ansi_color_param, color_label_key) {
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

# Return the CSS rule (one line) of the whole output (the element with the class
# makefile-doc): as wide as its text (a div is as wide as the page by default, which shows
# with a background color), with the colors FG and BG of EXPORT_THEME if they are set
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

# Set what is printed before and after the documentation: OUTPUT_HEADER and OUTPUT_FOOTER
# (each ends with a newline; both are empty for ANSI). It uses the colors, so it is called
# after initialize_colors.
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
  # FG and BG only if they are set (FG is given to each line, see print_documentation)
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
function escape_for_html_output(text) {
  if (OUTPUT_FORMAT == "HTML") {
    text = string_replace("&", "&amp;", text)
    text = string_replace("<", "&lt;", text)
    text = string_replace(">", "&gt;", text)
  }
  return text
}

# In \begin{alltt} ... \end{alltt}, only \, { and } are special. The backslashes go through
# a placeholder: escaping them first would escape the braces of \textbackslash{}, and
# escaping them last would escape the backslashes of \{ and \}.
function escape_for_latex_output(text, #locals
                                 placeholder) {
  if (OUTPUT_FORMAT == "LATEX") {
    placeholder = "\034"
    text = string_replace("\\", placeholder, text)
    gsub(/\{/, "\\{", text)
    gsub(/\}/, "\\}", text)
    text = string_replace(placeholder, "\\textbackslash{}", text)
  }
  return text
}

# the escapes of the output format (HTML or LaTeX), applied before the colors are added
function apply_output_specific_formatting(text) {
  return escape_for_latex_output(escape_for_html_output(text))
}

#### Parsing
# The parser that reads the Makefiles, one line at a time, and its helpers. It follows the
# model of misc/docs/parser-model.tex: each physical line is joined with the next ones if it
# ends with a backslash (lexical_join), each logical line is observed (lexical_obs: what kind
# of line it is, what it would document) and updates the state (lexical_step: inside a rule,
# a doc pending, a section pending, the recipe prefix). The rule at the end of this section
# runs it, keeps the text of the pending doc and section, and gives the doc to the anchor
# that takes it. Parsing fills the interface variables (see init_globals) and reads no
# option but RECIPEPREFIX.

# Record a warning about the Makefiles (printed by print_warnings, before the docs). kind is
# what it is about: "target", "variable" or "file".
function add_warning(kind, message) {
  WARNINGS[++WARNING_COUNT] = message
  WARNING_KINDS[WARNING_COUNT] = kind
}

# A file whose last line ends with a backslash: the line cannot be joined with a next one,
# so it is not parsed (awk has no hook at the end of a file, hence the check at the start of
# the next file and in END). A continued recipe line is not reported (it is part of a rule
# that ends with the file).
function warn_about_continued_last_line() {
  if (PARSER_STATE["joining"] &&
      !(PARSER_STATE["r"] && substr(PARSER_STATE["pending"], 1, 1) == PARSER_STATE["c"])) {
    add_warning("file", sprintf("[%s] the last line ends with a backslash", CURRENT_FILE))
  }
}

# the tag of a doc line (##, ##! or ##%), or "" if it does not start with one
function get_tag_from_description(string) {
  return match(string, TAG_REGEX) ? substr(string, 1, RLENGTH) : ""
}

function save_description_data(string) {
  DESCRIPTION_DATA[DESCRIPTION_DATA_INDEX++] = string
}

function forget_descriptions_data() {
  split("", DESCRIPTION_DATA)
  DESCRIPTION_DATA_INDEX = 1
}

function save_section_data(string) {
  SECTION_DATA[SECTION_DATA_INDEX++] = string
}

function forget_section_data() {
  split("", SECTION_DATA)
  SECTION_DATA_INDEX = 1
}

function form_dc_target_name(target_name_nominal) {
  if (!(target_name_nominal in TARGETS_DC_COUNTER)) {
    TARGETS_DC_COUNTER[target_name_nominal] = 1
  }

  return sprintf("%s%s%s",
                 target_name_nominal,
                 DOUBLE_COLON_SEPARATOR,
                 TARGETS_DC_COUNTER[target_name_nominal])
}

# Attach the pending doc to an anchor (target or variable), and record the anchor and the
# pending section in ANCHOR_ORDER and SECTION_BEFORE
function associate_data_with_anchor(anchor_name,
                                    anchors_description_data,
                                    anchors_tags,
                                    anchor_type, #locals
                                    tag, k) {
  tag = get_tag_from_description(DESCRIPTION_DATA[1]) # the tag of the first line decides
  if (anchor_name in anchors_description_data) {
    add_warning(anchor_type, sprintf("[%s:%s] redefined docs of %s: %s",
                                     CURRENT_FILE, FNR, anchor_type, anchor_name))
  }

  # the doc is stored without its tags (the tag of the first line is stored separately)
  for (k = 1; k < DESCRIPTION_DATA_INDEX; k++) {
    sub(TAG_REGEX, "", DESCRIPTION_DATA[k])
  }
  anchors_tags[anchor_name] = tag
  anchors_description_data[anchor_name] = join(DESCRIPTION_DATA, "\n")
  forget_descriptions_data()

  # the file order, with the pending section (placed by place_sections, when rendering)
  ANCHOR_ORDER[ANCHOR_ORDER_INDEX] = anchor_type SUBSEP anchor_name
  if (length_array_posix(SECTION_DATA) > 0) {
    SECTION_BEFORE[ANCHOR_ORDER_INDEX] = join(SECTION_DATA, "\n")
    forget_section_data()
  }
  ANCHOR_ORDER_INDEX++
}

# Observe a logical line (questions 2-8 of the model, without question 1: a recipe line
# depends on the state). Fill obs with:
#   obs["kind"]     assignment, rule, special rule, neutral, banner, section, doc, other
#   obs["anchor"]   target or variable (assignment and rule), "" otherwise
#   obs["name"]     the name of the anchor, as written in the line
#   obs["comment"]  the comment, from its # to the end of the line ("" if none)
# The examples are in test/lexical.spec (see test/unit/test_lexical.awk).
function lexical_observe(line, obs, #locals
                         first_word) {
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

  lexical_scan(line, obs) # kind: assignment, rule or ""
  if (obs["kind"] == "assignment") {
    return
  }

  first_word = line
  sub(/^[ \t]+/, "", first_word)
  sub(/[ \t(].*$/, "", first_word)
  if (first_word ~ /^(ifeq|ifneq|ifdef|ifndef|else|endif)$/) {
    lexical_clear(obs, "neutral")
  } else if (first_word ~ /^(include|-include|sinclude|vpath|export|unexport|undefine|endef)$/) {
    lexical_clear(obs, "other")
  } else if (lexical_define_name(line) != "") {
    lexical_clear(obs, "assignment")
    obs["anchor"] = "variable"
    obs["name"] = lexical_define_name(line)
  } else if (obs["kind"] == "rule") {
    if ((obs["name"] ":") ~ SPECIAL_TARGETS_REGEX) {
      lexical_clear(obs, "special rule")
    }
  } else {
    lexical_clear(obs, "other")
  }
}

# set the kind of obs, without anchor, name and comment
function lexical_clear(obs, kind) {
  obs["kind"] = kind
  obs["anchor"] = ""
  obs["name"] = ""
  obs["comment"] = ""
}

# the name of the variable of a define line (e.g., `override define V :=`), "" if not one
function lexical_define_name(line, #locals
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
function lexical_scan(line, obs, #locals
                      masked, p, c, q, start, end, after, rest, hit, name) {
  masked = lexical_mask(line)
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
    name = lexical_variable_name(substr(line, 1, start - 1), substr(masked, 1, start - 1))
    if (name != "") {
      end = c == "=" ? p : q + 1 # the = of the operator
      obs["kind"] = "assignment"
      obs["anchor"] = "variable"
      obs["name"] = name
      obs["comment"] = lexical_rest_from(line, masked, end, "#")
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
    obs["comment"] = lexical_rest_from(line, masked, hit, "#;")
  }
}

# The comment of line after position p: from the first character of chars found in masked
# after p, if it is a #; "" otherwise
function lexical_rest_from(line, masked, p, chars, #locals
                           k, c) {
  for (k = p + 1; k <= length(masked); k++) {
    c = substr(masked, k, 1)
    if (index(chars, c) > 0) {
      return c == "#" ? substr(line, k) : ""
    }
  }
  return ""
}

# The variable of the left side of an assignment, with its qualifiers (export, override,
# private): the single word after them, "" if there is not exactly one word. The words are
# found in masked (a reference is part of a word), the name is cut from text.
function lexical_variable_name(text, masked, #locals
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
function lexical_mask(line, #locals
                      n, k, c, next_char, opening, closing, depth, start, out) {
  n = length(line)
  out = ""
  k = 1
  while (k <= n) {
    c = substr(line, k, 1)
    next_char = substr(line, k + 1, 1)
    if (c == "$" && (next_char == "(" || next_char == "{")) {
      opening = next_char
      closing = opening == "(" ? ")" : "}"
      depth = 0
      start = k
      for (k = k + 1; k <= n; k++) {
        c = substr(line, k, 1)
        if (c == opening) {
          depth++
        } else if (c == closing) {
          depth--
          if (depth == 0) {
            break
          }
        }
      }
      if (k > n) { # not closed: masked to the end of the line
        k = n
      }
      out = out repeated_string("_", k - start + 1)
      k++
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

# ---------------------------------------------------------------------------------------
# The state machine (the model, with its state in an array): state["r"] (inside a rule),
# state["d"] (a doc is pending), state["s"] (a section is pending), state["c"] (the recipe
# prefix), the numbers of pending doc and section lines (state["dn"], state["sn"]), and the
# line being joined (state["joining"], state["pending"]).
# ---------------------------------------------------------------------------------------

function lexical_init(state, prefix) {
  split("", state)
  state["r"] = 0
  state["d"] = 0
  state["s"] = 0
  state["c"] = prefix == "" ? "\t" : substr(prefix, 1, 1)
  state["dn"] = 0
  state["sn"] = 0
  state["joining"] = 0
  state["pending"] = ""
}

# At the first line of a file: no open rule and no pending doc (a section and the recipe
# prefix carry over). A line continued at the end of the previous file is dropped.
function lexical_file_start(state) {
  state["r"] = 0
  state["d"] = 0
  state["dn"] = 0
  state["joining"] = 0
  state["pending"] = ""
}

# Add a physical line: return 1 when a logical line is complete (in state["line"]), 0 when the
# line continues on the next one (an odd number of final backslashes, recipe lines included).
# As in GNU Make, the backslash, the newline and the blanks around them become one space.
function lexical_join(state, physical, #locals
                      stripped) {
  sub(/\r$/, "", physical) # CRLF line endings
  if (state["joining"]) {
    sub(/^[ \t]+/, "", physical)
    physical = state["pending"] " " physical
    state["joining"] = 0
  }
  if (has_odd_terminal_backslashes(physical)) {
    physical = substr(physical, 1, length(physical) - 1)
    stripped = physical
    sub(/[ \t]+$/, "", stripped)
    # a recipe line of only its prefix (e.g., a tab, then the backslash) keeps the prefix
    physical = stripped == "" ? substr(physical, 1, 1) : stripped
    state["pending"] = physical
    state["joining"] = 1
    return 0
  }
  state["line"] = physical
  return 1
}

# Observe a logical line with the state (all the questions of the model): lexical_observe,
# plus question 1 (a recipe line: inside a rule, the line starts with the recipe prefix),
# obs["inline"] (a_i: the comment is an inline doc) and question 9 (an assignment to
# .RECIPEPREFIX changes state["c"], for the next lines).
function lexical_obs(line, state, obs) {
  if (state["r"] && substr(line, 1, 1) == state["c"]) {
    split("", obs)
    lexical_clear(obs, "recipe")
  } else {
    lexical_observe(line, obs)
  }
  obs["inline"] = obs["anchor"] != "" && obs["comment"] ~ /^##/ && obs["comment"] !~ /^##@/
  if (obs["kind"] == "assignment" && obs["anchor"] == "variable" &&
      obs["name"] == ".RECIPEPREFIX") {
    lexical_set_prefix(state, obs["operator"], obs["value"])
  }
}

# The recipe prefix after an assignment to .RECIPEPREFIX: the first character of the value (a
# tab if it is empty). With += the first character does not change; with != or an expanded
# reference (:=, ::=), the value is not known: the prefix does not change either.
function lexical_set_prefix(state, operator, value) {
  if (operator == "+=" || operator == "!=" || (operator ~ /^:+=$/ && index(value, "$") > 0)) {
    return
  }
  state["c"] = value == "" ? "\t" : substr(value, 1, 1)
}

# Update the state with an observation (the step table of the model). obs["attach"] is 1 when
# the line is an anchor that gets documented (by a pending doc or its inline doc), and
# obs["with_section"] is 1 when the pending section goes with it.
function lexical_step(state, obs, #locals
                      kind, documented) {
  kind = obs["kind"]
  documented = state["d"] || obs["inline"]
  obs["attach"] = 0
  obs["with_section"] = 0
  if (kind == "recipe") {
    state["r"] = 1
    lexical_drop_doc(state)
  } else if (kind == "doc") {
    state["d"] = 1
    state["dn"]++
  } else if (kind == "section") {
    state["s"] = 1
    state["sn"]++
  } else if (kind == "banner") {
    lexical_drop_doc(state)
  } else if (kind == "rule" || kind == "assignment") {
    state["r"] = kind == "rule"
    if (documented) {
      obs["attach"] = 1
      obs["with_section"] = state["s"]
      state["s"] = 0
      state["sn"] = 0
    }
    lexical_drop_doc(state)
  } else if (kind == "special rule") {
    state["r"] = 1
  } else if (kind == "other") {
    state["r"] = 0
    lexical_drop_doc(state)
  } # neutral: no change
}

function lexical_drop_doc(state) {
  state["d"] = 0
  state["dn"] = 0
}


# At the first line of a file: the warning about the previous file, then a new file (the
# pending doc is dropped, the pending section is kept: it goes to the next documented anchor,
# which can be in this file)
function parse_file_start() {
  warn_about_continued_last_line()
  lexical_file_start(PARSER_STATE)
  forget_descriptions_data()
  # stdin is named - (POSIX leaves FILENAME unspecified for it; most awks set it to -)
  CURRENT_FILE = FILENAME == "" ? "-" : FILENAME
  FILES_PROCESSED = FILES_PROCESSED == "" ? CURRENT_FILE : FILES_PROCESSED " " CURRENT_FILE
}

# A logical line: observe it (in PARSER_OBS), keep the text of a doc or section line, update
# the state, and give the doc to the anchor that takes it (without a pending doc, its inline
# doc). The pending doc is dropped when the state says so.
function parse_line(line, #locals
                    kind, text) {
  lexical_obs(line, PARSER_STATE, PARSER_OBS)
  kind = PARSER_OBS["kind"]
  text = line
  sub(/^[ \t]+/, "", text)
  if (kind == "doc") {
    save_description_data(text)
  } else if (kind == "section") {
    sub(/^##@/, "", text) # the tags are not needed anymore
    save_section_data(text)
  }

  lexical_step(PARSER_STATE, PARSER_OBS)
  if (PARSER_OBS["attach"]) {
    if (DESCRIPTION_DATA_INDEX == 1) {
      save_description_data(PARSER_OBS["comment"])
    }
    if (PARSER_OBS["anchor"] == "target") {
      associate_data_with_anchor(form_target_name(PARSER_OBS), TARGETS_DESCRIPTION_DATA,
                                 TARGETS_TAG, "target")
    } else {
      associate_data_with_anchor(PARSER_OBS["name"], VARIABLES_DESCRIPTION_DATA, VARIABLES_TAG,
                                 "variable")
    }
  }
  if (!PARSER_STATE["d"]) {
    forget_descriptions_data()
  }
}

# The name of a documented target: blanks collapsed (GNU Make treats any run of blanks
# between target names as one separator), a & after grouped targets, ~N after the documented
# rules of a double-colon target (see form_dc_target_name; counted across files)
function form_target_name(obs, #locals
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

FNR == 1 {
  parse_file_start()
}

{
  if (lexical_join(PARSER_STATE, $0)) {
    parse_line(PARSER_STATE["line"])
  }
}

#### Rendering
# The display of the documentation, from the interface variables and the settings.

# Print the warnings recorded while parsing, except those about variables with VARS=0 (they
# are not displayed)
function print_warnings(    k) {
  for (k = 1; k <= WARNING_COUNT; k++) {
    if (!(WARNING_KINDS[k] == "variable" && !VARS)) {
      printf("WARNING: %s\n", WARNINGS[k]) > STDERR
    }
  }
}

# The rendering state, derived from the interface: the anchors to display, in order, and
# their sections. What follows (print_documentation) only formats and prints it.
function prepare_rendering() {
  build_anchor_lists()
  place_sections()
}

# Build TARGETS and VARIABLES from ANCHOR_ORDER: the documented anchors of each kind, once
# each, in file order (at their first definition)
function build_anchor_lists(    k, parts, seen) {
  split("", seen)
  for (k = 1; k < ANCHOR_ORDER_INDEX; k++) {
    if (ANCHOR_ORDER[k] in seen) {
      continue
    }
    seen[ANCHOR_ORDER[k]] = 1
    split(ANCHOR_ORDER[k], parts, SUBSEP)
    if (parts[1] == "target") {
      TARGETS[TARGETS_INDEX++] = parts[2]
    } else {
      VARIABLES[VARIABLES_INDEX++] = parts[2]
    }
  }
}

# Give each section to the next displayed anchor after it in the Makefiles (TARGETS_SECTION_DATA
# and VARIABLES_SECTION_DATA). Hidden anchors (variables with VARS=0, deprecated anchors with
# DEPRECATED=0) are skipped, sections with no displayed anchor after them are dropped, and
# consecutive sections are merged. A later section of the same anchor replaces an earlier one.
function place_sections(    k, parts, name, has_section, section) {
  has_section = 0
  for (k = 1; k < ANCHOR_ORDER_INDEX; k++) {
    if (k in SECTION_BEFORE) {
      section = has_section ? section "\n" SECTION_BEFORE[k] : SECTION_BEFORE[k]
      has_section = 1
    }
    split(ANCHOR_ORDER[k], parts, SUBSEP)
    name = parts[2]
    if (!has_section) {
      continue
    }
    if (parts[1] == "target" && !is_hidden_anchor(name, TARGETS_TAG)) {
      TARGETS_SECTION_DATA[name] = section
      has_section = 0
    } else if (parts[1] == "variable" && VARS && !is_hidden_anchor(name, VARIABLES_TAG)) {
      VARIABLES_SECTION_DATA[name] = section
      has_section = 0
    }
  }
}

# true for an anchor documented with ##% when deprecated anchors are not displayed
function is_hidden_anchor(anchor, anchors_tags) {
  return !DEPRECATED && anchors_tags[anchor] == "##%"
}

# The name that is displayed for an anchor: its SUB label if it has one, otherwise its name
# after the DSUB substitutions with the parameter A:1 (in the order given).
# SUB is looked up with the name as written in the Makefile, so DSUB never affects which
# SUB applies.
function display_name(anchor, #locals
                      k, name) {
  if (anchor in SUB_LABELS) {
    return SUB_LABELS[anchor]
  }
  for (k = 1; k <= DSUB_COUNT; k++) {
    name = DSUB_NAMES[k]
    if (DSUB_IN_ANCHORS[name]) {
      anchor = string_replace(name, DSUB_VALUES[name], anchor)
    }
  }
  return anchor
}

# the length of the longest displayed anchor (0 if no anchor is displayed)
function get_max_anchor_length(anchors, anchors_tags, #locals
                               max_len, key, anchor, n) {
  max_len = 0
  for (key in anchors) { # order is not important
    anchor = anchors[key]
    if (is_hidden_anchor(anchor, anchors_tags)) {
      continue
    }
    n = length(display_name(anchor))
    if (n > max_len) {
      max_len = n
    }
  }
  return max_len
}

function get_separator(character, len_anchors) {
  return repeated_string(character, max(len_anchors,
                                        max(length(HEADER_TARGETS),
                                            length(HEADER_VARIABLES))))
}

# Color each line of text on its own (color_code ... COLOR_RESET_CODE), so that no color
# group crosses a line break: in LaTeX, varwidth cannot crop the page to the text of such a
# group. Empty lines are not colored.
function color_lines(text, color_code, #locals
                     n, lines, k) {
  n = split(text, lines, "\n")
  for (k = 1; k <= n; k++) {
    if (lines[k] != "") {
      lines[k] = color_code lines[k] COLOR_RESET_CODE
    }
  }
  return join(lines, "\n")
}

function substitute_backticks_patterns(string, #locals
                                       before_match, inside_match, after_match) {
  # (gensub with a back-reference would do this in one call, but it is only in gawk)
  while (match(string, /`([^`]+)`/)) {
    before_match = substr(string, 1, RSTART - 1)
    inside_match = substr(string, RSTART + 1, RLENGTH - 2)
    after_match = substr(string, RSTART + RLENGTH)

    string = before_match color_lines(inside_match, COLOR_BACKTICKS_CODE) after_match
  }
  return string
}

function colorize_description_backticks(description) {
  if (COLOR_BACKTICKS) {
    return substitute_backticks_patterns(description)
  }
  return description
}

# the color code of an anchor, given by the tag of its doc
function anchor_color(anchor_name, anchors_tags, #locals
                      tag) {
  tag = anchors_tags[anchor_name]
  if (tag == "##!") {
    return COLOR_ATTENTION_CODE
  } else if (tag == "##%") {
    return COLOR_DEPRECATED_CODE
  }
  return COLOR_DEFAULT_CODE # ## (a doc starts with one of the three tags)
}

# The doc of an anchor (stored without its tags), ready to display: the first line offset
# from the anchor and the next lines aligned with it, with the DSUB substitutions, the
# escapes of the output format and the colors of the text in backticks
function format_description_data(anchor_name,
                                 anchors_description_data,
                                 len_anchor_names,
                                 #locals
                                 lines, indentation, description) {
  split(anchors_description_data[anchor_name], lines, "\n")
  indentation = repeated_string("", OFFSET + len_anchor_names) # aligned with the first line
  description = repeated_string("", OFFSET) join(lines, "\n" indentation)

  description = apply_doc_substitutions(description)

  return colorize_description_backticks(apply_output_specific_formatting(description))
}

# Apply the DSUB substitutions to the text of docs or section titles (those with D:1), in
# the order given.
function apply_doc_substitutions(text, #locals
                                 k) {
  for (k = 1; k <= DSUB_COUNT; k++) {
    if (DSUB_IN_DOCS[DSUB_NAMES[k]]) {
      text = string_replace(DSUB_NAMES[k], DSUB_VALUES[DSUB_NAMES[k]], text)
    }
  }
  return text
}

function get_associated_section_data(anchor_name,
                                     anchor_section_data, #locals
                                     section) {
  if (anchor_name in anchor_section_data) {
    section = strip_trailing_blanks(apply_doc_substitutions(anchor_section_data[anchor_name]))
    return colorize_description_backticks(apply_output_specific_formatting(section))
  }
  return "" # means that there is no section data associated with this anchor
}

# Set SUB_PARAMS_CURRENT to the parameters of a substitution (with the defaults for those
# that are not given)
function extract_substitution_params(string_with_parameters, #locals
                                     keys, key) {
  parse_substitution_params(string_with_parameters, SUB_PARAMS_CURRENT, keys)

  for (key in SUB_PARAMS_DEFAULTS) {
    if (!(key in SUB_PARAMS_CURRENT)) {
      SUB_PARAMS_CURRENT[key] = SUB_PARAMS_DEFAULTS[key]
    }
  }
  # L, M and N are used as numbers (the value above is a string, e.g., "0" would be true)
  SUB_PARAMS_CURRENT["L"] += 0
  SUB_PARAMS_CURRENT["M"] += 0
  SUB_PARAMS_CURRENT["N"] += 0
}

# Return the text that follows the doc of an anchor: the values of its SUB substitution
# (with the parameters in SUB_PARAMS_CURRENT), then a newline. Each value is made into an
# item (P before it, S after it, I before the first one, T after the last one instead of S);
# the items are on one line (M=0) or on one line each (M=1). The first line follows the doc
# (L=0) or starts on the next line (L=1).
function display_substitutions(anchor, len_anchors, #locals
                               values, n, k, item, lines, n_lines, initial, prefix,
                               separator, termination, indentation, next_indentation,
                               output) {
  n = split(array_get(SUB_VALUES, anchor), values, " ")
  if (SUB_PARAMS_CURRENT["N"] >= 0) {
    n = min(n, SUB_PARAMS_CURRENT["N"])
  }
  if (n == 0) {
    return "\n"
  }

  initial = SUB_PARAMS_CURRENT["I"]
  prefix = SUB_PARAMS_CURRENT["P"]
  separator = SUB_PARAMS_CURRENT["S"]
  termination = SUB_PARAMS_CURRENT["T"]

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
    item = colorize_description_backticks(apply_output_specific_formatting(item))
    if (SUB_PARAMS_CURRENT["M"] || k == 1) {
      lines[++n_lines] = item
    } else {
      lines[n_lines] = lines[n_lines] " " item
    }
  }

  # the + 1 assumes the usual space after the token (as in `## doc`), so that the values
  # line up with the text of the doc
  indentation = repeated_string("", len_anchors + OFFSET + 1)
  output = (SUB_PARAMS_CURRENT["L"] ? "\n" indentation : " ") lines[1]
  # the lines after the first are aligned with the first value (after I)
  next_indentation = indentation repeated_string("", length(initial))
  for (k = 2; k <= n_lines; k++) {
    output = output "\n" next_indentation lines[k]
  }
  return output "\n"
}

# Display an anchor (if show is true) with its doc, its section and the values of its SUB
# substitution; color is the color code of the anchor
function display_anchor_with_data(anchor, description, section, len_anchors, color,
                                  show, #locals
                                  renamed_anchor, formatted_anchor, padding, output) {
  extract_substitution_params(array_get(SUB_PARAMS, anchor))

  # (only displayed anchors have a section, see place_sections)
  if (show) {
    if (section) {
      if (COLOR_SECTION_CODE) {
        # In ANSI output a reset (e.g., after a backtick region) turns off all colors, so
        # the section color has to be restored after each reset.
        if (OUTPUT_FORMAT == "ANSI") {
          section = string_replace(COLOR_RESET_CODE,
                                   COLOR_RESET_CODE COLOR_SECTION_CODE,
                                   section)
        }
        section = color_lines(section, COLOR_SECTION_CODE)
      }
      append_output(section "\n")
    }

    renamed_anchor = display_name(anchor)
    formatted_anchor = apply_output_specific_formatting(renamed_anchor)

    # The length of the padding is computed from the displayed name, not from the formatted
    # one (an HTML or LaTeX escape is longer than the character it stands for). The padding
    # is then escaped too, since PADDING can be any character.
    padding = repeated_string(PADDING, len_anchors - length(renamed_anchor))
    padding = apply_output_specific_formatting(padding)
    if (color) {
      formatted_anchor = sprintf("%s%s%s%s",
                                 color,
                                 formatted_anchor,
                                 padding,
                                 COLOR_RESET_CODE)
    } else {
      formatted_anchor = sprintf("%s%s", formatted_anchor, padding)
    }

    output = formatted_anchor description display_substitutions(anchor, len_anchors)
    append_output(strip_trailing_blanks(output))
  }
}

# Display the anchors of one kind (TARGETS or VARIABLES) with their docs and sections.
function print_anchors(anchors, description_data, tags, section_data, max_anchor_length,
                       #locals
                       n_elements, indx, anchor, description, section) {
  n_elements = length_array_posix(anchors)
  for (indx = 1; indx <= n_elements; indx++) {
    anchor = anchors[indx]
    description = format_description_data(anchor,
                                          description_data,
                                          max_anchor_length)
    section = get_associated_section_data(anchor, section_data)
    display_anchor_with_data(anchor, description, section, max_anchor_length,
                             anchor_color(anchor, tags),
                             !is_hidden_anchor(anchor, tags))
  }
}

# add text to the documentation (OUTPUT_BODY, printed by print_documentation)
function append_output(text) {
  OUTPUT_BODY = OUTPUT_BODY text
}

# Display the documentation (all its output is printed from here).
function print_documentation(    max_target_length, max_variable_length, max_anchor_length,
                             separator) {
  prepare_rendering()
  max_target_length = get_max_anchor_length(TARGETS, TARGETS_TAG)
  # 0 when the variables are not shown (VARS=0)
  max_variable_length = VARS ? get_max_anchor_length(VARIABLES, VARIABLES_TAG) : 0
  max_anchor_length = max(max_target_length, max_variable_length)
  separator = get_separator("-", max_anchor_length)
  OUTPUT_BODY = ""
  print_warnings() # (on stderr, before the docs)

  # process targets
  if (max_target_length > 0) {
    append_output(separator "\n" HEADER_TARGETS "\n" separator "\n")
    print_anchors(TARGETS, TARGETS_DESCRIPTION_DATA, TARGETS_TAG, TARGETS_SECTION_DATA,
                  max_anchor_length)
  }

  # process variables
  if (max_variable_length > 0) {
    if (max_target_length > 0) {
      append_output("\n") # a blank line after the targets
    }
    append_output(separator "\n" HEADER_VARIABLES "\n" separator "\n")
    print_anchors(VARIABLES, VARIABLES_DESCRIPTION_DATA, VARIABLES_TAG, VARIABLES_SECTION_DATA,
                  max_anchor_length)
  }

  if (max_target_length > 0 || max_variable_length > 0) {
    append_output(separator "\n")
  } else {
    if (FILES_PROCESSED != "") {
      if (TARGETS_INDEX > 1 || VARIABLES_INDEX > 1) { # documented, but hidden
        printf("WARNING: all documented targets/variables are hidden in %s\n",
               FILES_PROCESSED) > STDERR
      } else {
        printf("WARNING: no documented targets/variables in %s\n",
               FILES_PROCESSED) > STDERR
      }
    }
  }

  # In LaTeX, the default text color (FG) is given to each line: with one \color for the
  # whole documentation, varwidth would not crop the page to the text
  if (OUTPUT_FORMAT == "LATEX" && EXPORT_FG_BG["FG"] != "") {
    OUTPUT_BODY = color_lines(OUTPUT_BODY, "\\textcolor{" color_name("FG") "}{")
  }
  printf("%s%s%s", OUTPUT_HEADER, OUTPUT_BODY, OUTPUT_FOOTER)
}

#### Flow
# BEGIN: the initialization and the options; END: the rendering (or the help).

# Initialize the global variables and process the options (the script exits here if an
# option is invalid).
BEGIN {
  init_globals()
  if (!UNIT_TEST) {
    process_options()
    lexical_init(PARSER_STATE, RECIPEPREFIX)
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
