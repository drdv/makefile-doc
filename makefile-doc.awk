#!/usr/bin/awk -f
# Generate docs for Makefile variables and targets
#
#    File: makefile-doc.awk
#  Author: Dimitar Dimitrov
# License: Apache-2.0
# Project: https://github.com/drdv/makefile-doc

### Commentary

#### Usage
#   awk [-v OPTION=value ...] -f makefile-doc.awk [Makefile ...]
# Without a Makefile, the script reads stdin. If stdin is empty, it prints the help. The
# README.md of the project has the details and examples.

#### Docs
#   * Targets and variables are called anchors.
#   * The docs of an anchor are comments above it or inline. Docs above win over inline
#     docs. They start with one of the tags:
#       ##   a default anchor (displayed in COLOR_DEFAULT)
#       ##!  an anchor that needs attention (displayed in COLOR_ATTENTION)
#       ##%  a deprecated anchor (displayed in COLOR_DEPRECATED)
#   * Lines that start with ##@ form a section (displayed in COLOR_SECTION). We define the
#     kind of a section to be the kind (target or variable) of the first documented anchor
#     after it. The kind is set while parsing, so hiding anchors (VARS, DEPRECATED) does
#     not impact it. A section is displayed above the first displayed anchor of its kind.

#### Options
#   They are passed with -v OPTION=value and checked in opt_process(). The help lists them:
#   run the script with an empty stdin. README.md describes them, with examples.

#### Code conventions
#   * The parameters of a function come in groups, in this order:
#       inputs    (no marker)
#       #update   the arrays that it updates
#       #fill     the arrays that it fills (their old content does not matter)
#       #locals   the local variables (awk declares them as extra parameters)
#     Each group is on its own line, followed by its marker. The last group closes the
#     parenthesis, so its marker comes after the {: awk accepts no newline before the
#     parenthesis. For example:
#       function f(x, y,
#                  out, #fill
#                  k, n) { #locals
#
#     A signature with a single group is on one line:
#       function g(k, n) { #locals
#
#   * A function comment lists the arrays that it updates under Update:, and those that it
#     fills under Fill:. An entry written as code has the form name[key] = VALUE, where VALUE
#     is a placeholder. Other entries have the form name[key]: description. The descriptions
#     of a list are aligned, with their continuation lines. The code entries are not.
#   * Globals are upper case (a global in lower case is a local that was not declared).
#   * Only POSIX awk, for all the major awks: no match() with an array, no arrays of arrays,
#     no gensub. Groups are read with RSTART and RLENGTH.
#   * `for (key in array)` has no order. An ordered array uses the keys 1, 2, ..., up to its
#     *_COUNT.

#### Structure of the code
#   Helpers                pure functions (no global variables)
#   Global initialization  init_globals: the global variables, grouped by who writes them
#   Options                the options: defaults, checks and derived settings
#   Output formats         everything that depends on OUTPUT_FORMAT
#   Parsing                the parser that reads the Makefiles, and its helpers
#   Rendering              what is displayed (DISPLAY), then its layout in the output format
#   Flow                   BEGIN and END
# A function is in the section that owns the variables it writes. Options writes the
# settings. Parsing writes the interface, which Rendering reads (see init_globals). Rendering
# uses the output formats only through the functions fmt_* and the color codes. Parsing does
# not use them.

#### Terminology
#   * A Makefile rule (without patterns) has the form
#       target-name [...] [&]:[:] [prerequisites] [;] [inline recipe]
#           [recipe]
#
#     where:
#       prerequisites := normal-prerequisites | order-only-prerequisites
#       inline recipe := [command] [; command ...]
#       recipe := [command]
#                 [...]
#
#     with normal-prerequisites and order-only-prerequisites being space separated lists
#     of target names.
#
#   * A target-specific variable assignment has the form
#       target-name [...] [&]:[:] variable assignment
#
#     It sets a single variable and has no recipe, so it is not a rule. It closes the open
#     rule, if any. A target can have any number of them, before or after its rule, but not
#     between the rule and its recipe:
#       t: CFLAGS := -O2
#       t: LDFLAGS := -s
#       t: dep
#           recipe
#
#   * A single-colon target has one recipe, so it has one doc: the last one. A double-colon
#     target has a recipe per rule, so each documented rule has its own doc, displayed as
#     t~1, t~2, ...

### Code

#### Helpers
# Pure functions: they use no global variables.

function max(x, y) {
  return (x >= y) ? x : y
}

function min(x, y) {
  return (x <= y) ? x : y
}

# string repeated n times, with n a non-negative integer. The only n that comes from the
# user, OFFSET, is checked by opt_process. A loop is used rather than gsub, whose
# replacement would need & and \ escaped.
function repeated_string(string, n,
                         s, k) { #locals
  s = ""
  for (k = 1; k <= n; k++) {
    s = s string
  }
  return s
}

# The number of characters of a UTF-8 text, one column each.
#   - A wide character (e.g., Japanese) takes two columns on most terminals, but counts as one.
#   - Some awks count bytes (mawk, busybox, gawk in the C locale, goawk). There, the
#     continuation bytes (\200 to \277) of the multi-byte characters are not counted.
#   - The bytes are compared one by one: goawk rejects a regex such as [\200-\277], because
#     its regexes match UTF-8 characters, not bytes.
function text_length(text,
                     n, i, count, c) { #locals
  n = length(text)
  if (length("\303\251") == 1) { # the two bytes of an e with an acute accent
    return n
  }
  count = 0
  for (i = 1; i <= n; i++) {
    c = substr(text, i, 1)
    if (c < "\200" || c >= "\300") {
      count++
    }
  }
  return count
}

# n spaces (see repeated_string)
function spaces(n) {
  return repeated_string(" ", n)
}

# array[key], or "" if there is no such key. Unlike reading array[key], it does not create
# the key.
function array_get(array, key) {
  return (key in array) ? array[key] : ""
}

# in POSIX-compliant AWK the length function works on strings but not on arrays
function array_length(array,
                      key, n) { #locals
  n = 0
  for (key in array) {
    n++
  }
  return n
}

# join the elements 1..n of an array (e.g., n and the array of split())
function join(array, n, delimiter,
              string, k) { #locals
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

# Replace every occurrence of string in text with replacement, without using a regex. With
# gsub, string would be a regex, and & and \ are special in its replacement. Here string
# comes from the user (DSUB), and replacement contains & and \ (the HTML and LaTeX escapes).
function string_replace(string, replacement, text,
                        k, len, result) { #locals
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

function strip_blanks(string) {
  sub(/^[ \t]*/, "", string)
  sub(/[ \t]*$/, "", string)
  return string
}

# Remove the spaces and tabs at the end of each line, e.g., the padding and the offset of an
# empty doc. It uses no regex, because a regex such as /[ \t]+\n/ takes quadratic time on
# the long runs of spaces of the padding.
function strip_trailing_blanks(text,
                               n, lines, k, line, last) { #locals
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
function has_odd_terminal_backslashes(string,
                                      n, k) { #locals
  n = 0
  for (k = length(string); k > 0 && substr(string, k, 1) == "\\"; k--) {
    n++
  }
  return n % 2
}

# the words of a space-separated list, joined with commas and a final "or" (e.g., "a, b or c")
function or_list(words,
                 n, list, k, text) { #locals
  n = split(words, list, " ")
  text = list[1]
  for (k = 2; k <= n; k++) {
    text = text (k < n ? ", " : " or ") list[k]
  }
  return text
}

function is_bool(value) {
  return value ~ /^[01]$/
}

# a color of 6 hex digits (without a leading #)
function is_hex_color(value) {
  return length(value) == 6 && value ~ /^[0-9A-Fa-f]+$/
}

# The name of the color of label in the HTML and LaTeX output, e.g., makefile-doc-default.
# It is an HTML class and a LaTeX color.
function color_name(label) {
  return "makefile-doc-" tolower(label)
}

#### Global initialization
# The global state that does not depend on the options: constants and empty arrays.

# Set the global state that does not depend on user options. It is called from BEGIN. Unit
# tests call it too, e.g., to reset the state between tests.
function init_globals() {
  # The options (COLOR, VARS, SUB, ...) are not set here. -v sets them before BEGIN, and
  # opt_process gives them their defaults.

  # ---------------------------------------------------------------------------------------
  # The control of the run
  # ---------------------------------------------------------------------------------------

  # can be overridden with -v STDERR=file (used by the unit tests)
  STDERR = STDERR == "" ? "/dev/stderr" : STDERR
  ABORT = 0 # set to the exit status when BEGIN fails (END must not print anything)
  OPTION_ERRORS = 0 # number of invalid options (see opt_error)

  # ---------------------------------------------------------------------------------------
  # Constants (never changed after init_globals)
  # ---------------------------------------------------------------------------------------

  VERSION = "v2.3" # the source of truth for the version (tools/release.py updates it)
  OUTPUT_FORMATS = "ANSI HTML LATEX" # the values of OUTPUT_FORMAT (see fmt_init)
  PROGRAM = "makefile-doc" # the name at the start of the warnings and the errors

  # The special built-in targets of GNU Make (see parser_all_special). Suffix rules, which
  # GNU Make also counts as special targets, are not among them: they are displayed.
  SPECIAL_TARGETS_REGEX = "^\\.(PHONY|SUFFIXES|DEFAULT|PRECIOUS|INTERMEDIATE|" \
                          "NOTINTERMEDIATE|SECONDARY|SECONDEXPANSION|DELETE_ON_ERROR|" \
                          "IGNORE|LOW_RESOLUTION_TIME|SILENT|EXPORT_ALL_VARIABLES|" \
                          "NOTPARALLEL|ONESHELL|POSIX)$"

  # The tag at the start of a doc line. The order of the alternatives matters for goawk up
  # to v1.29.1 (fixed in v1.30.0).
  TAG_REGEX = "^(##!|##%|##)"

  # A character that stands in for another during a split or a replacement, e.g., in
  # opt_form_substitutions and fmt_latex_escape. It is assumed absent from options and docs.
  # It is not SUBSEP, although it has the same default value.
  PLACEHOLDER = "\034"

  # the tables of the HTML and LaTeX output formats
  fmt_define_html_attributes()
  fmt_define_latex_functions()

  HEADER_TARGETS = "Available targets:"
  HEADER_VARIABLES = "Variables:"
  DOUBLE_COLON_SEPARATOR = "~" # decorates double-colon targets, e.g., t~1

  # ---------------------------------------------------------------------------------------
  # Settings: derived from the options by opt_process, read when rendering
  # ---------------------------------------------------------------------------------------

  # the colors of the HTML and LaTeX output (opt_export_theme applies EXPORT_THEME)
  fmt_define_export_palette()

  # The settings of the output format, set by fmt_init. They are the color codes of each
  # kind of text, the text before and after the documentation, the color of each line ("" for
  # none), and whether a color must be restored after a reset.
  COLOR_DEFAULT_CODE = COLOR_ATTENTION_CODE = COLOR_DEPRECATED_CODE = ""
  COLOR_SECTION_CODE = COLOR_BACKTICKS_CODE = COLOR_RESET_CODE = ""
  OUTPUT_HEADER = OUTPUT_FOOTER = ""
  FMT_LINE_COLOR = ""
  FMT_RESTORE_AFTER_RESET = 0

  # SUB and DSUB, parsed by opt_form_substitutions. The parameters of each substitution are
  # in a row of a table, with the defaults filled in. The tables are SUB_PARAM[name, key],
  # with the keys L, M, N, S, P, I and T, and DSUB_PARAM[name, key], with the keys A and D.
  # The row "" holds the defaults, and is used for an anchor without SUB. No name is empty,
  # so this row never clashes with a name.
  set_sub_param_defaults(SUB_PARAM)
  split("", SUB_LABELS)
  split("", SUB_VALUES)
  set_dsub_param_defaults(DSUB_PARAM)
  split("", DSUB_VALUES)
  split("", DSUB_NAMES)
  DSUB_COUNT = 0 # number of DSUB substitutions

  # ---------------------------------------------------------------------------------------
  # The interface between parsing and rendering: written while parsing (see parser_record_anchor
  # and parser_add_warning), read when rendering (see render_prepare)
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

  # the warnings about the Makefiles (see parser_add_warning):
  # WARNINGS[k, field], k = 1..WARNING_COUNT, with the fields
  #   file     the file the warning is about
  #   line     the line in that file ("" if none)
  #   message  the text of the warning
  split("", WARNINGS)
  WARNING_COUNT = 0

  FILES_PROCESSED = "" # the names of the input files, separated by spaces (see parser_list_files)

  # ---------------------------------------------------------------------------------------
  # The state of the parser
  # ---------------------------------------------------------------------------------------

  # As in misc/docs/parser-model.tex (see parser_init, called in BEGIN once RECIPEPREFIX is
  # known):
  #   PARSER_STATE    the state x_i = (r_i, d_i, s_i, p_i)
  #   PARSER_MEMORY   the memory: the pending text D_i and S_i
  #   PARSER_OBS      the observations of the last logical line L_i
  #   PARSER_DERIVED  its derived quantities: k_i and e_i
  # and outside the model:
  #   PARSER_JOINER   the physical lines joined into the next logical line (see parser_join)
  #   PARSER_CONTEXT  for the names and the warnings, PARSER_CONTEXT[key] with the keys
  #                     file                the file being read
  #                     "seen", kind, name  1 if the anchor is documented so far (see
  #                                         parser_record_anchor)
  #                     "dc", name          the number of documented rules so far of the
  #                                         double-colon target name (see parser_form_target_name)
  split("", PARSER_STATE)
  split("", PARSER_MEMORY)
  split("", PARSER_OBS)
  split("", PARSER_DERIVED)
  parser_join_init(PARSER_JOINER)
  split("", PARSER_CONTEXT)

  # ---------------------------------------------------------------------------------------
  # The state of the rendering: written by render_prepare (what is displayed)
  # ---------------------------------------------------------------------------------------

  # the anchors to display, in order (the targets, then the variables): DISPLAY[k, field],
  # k = 1..DISPLAY_COUNT, with the fields
  #   kind, tag  as in ANCHORS (of the last definition)
  #   name       the displayed name (see render_display_name)
  #   label      the text of the name column: name, with " (fixed)" after it for override
  #   doc        the doc after DSUB
  #   section    the section above it after DSUB (only if there is one, see render_place_sections)
  #   values     its SUB values, space-separated ("" if none)
  #   sub_row    its row in SUB_PARAM: its name if it has a SUB, "" (the defaults) otherwise
  #   override   1 for a variable set with override (only then; displayed as "(fixed)")
  split("", DISPLAY)
  DISPLAY_COUNT = 0
}

# Empty a table of SUB parameters, then set its row of defaults, "" (see init_globals)
function set_sub_param_defaults(table) { #fill
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
function set_dsub_param_defaults(table) { #fill
  split("", table)
  table["", "A"] = 0 # 1: replace in the names of anchors too
  table["", "D"] = 1 # 1: replace in the docs and section titles
}

#### Options
# The options given with -v: their defaults, their checks and the settings derived from them.

# Check the options and derive the settings. Report every invalid option, and return their
# number. BEGIN exits when it is not 0.
function opt_process(sub_names, dummy_array_labels) { #locals
  OUTPUT_FORMAT = OUTPUT_FORMAT == "" ? "ANSI" : toupper(OUTPUT_FORMAT)
  if (!index(" " OUTPUT_FORMATS " ", " " OUTPUT_FORMAT " ")) {
    opt_error("OUTPUT_FORMAT should be " or_list(OUTPUT_FORMATS))
    OUTPUT_FORMAT = "ANSI"
  }

  opt_colors()
  fmt_init()

  RECIPEPREFIX = RECIPEPREFIX == "" ? "\t" : substr(RECIPEPREFIX, 1, 1)

  VARS = VARS == "" ? 1 : VARS
  PADDING = PADDING == "" ? " " : PADDING
  DEPRECATED = DEPRECATED == "" ? 1 : DEPRECATED
  OFFSET = OFFSET == "" ? 3 : OFFSET
  WARN = WARN == "" ? 1 : WARN
  if (!is_bool(VARS)) {
    opt_error("VARS should be 0 or 1")
  }
  if (text_length(PADDING) != 1) {
    opt_error("PADDING should have length 1")
  }
  if (!is_bool(DEPRECATED)) {
    opt_error("DEPRECATED should be 0 or 1")
  }
  if (OFFSET !~ /^[0-9]+$/) {
    opt_error("OFFSET should be a non-negative integer")
  }
  if (!is_bool(WARN)) {
    opt_error("WARN should be 0 or 1")
  }

  # (with "", gawk --lint does not warn when the option is not set)
  opt_form_substitutions(SUB "", 0, SUB_PARAM, SUB_LABELS, SUB_VALUES, sub_names)
  opt_form_substitutions(DSUB "", 1, DSUB_PARAM, dummy_array_labels, DSUB_VALUES, DSUB_NAMES)
  DSUB_COUNT = array_length(DSUB_NAMES)

  opt_report_assignment_operands()
  return OPTION_ERRORS
}

# Report an invalid value of an option. The script goes on, so that all the invalid options
# are reported, and stops after opt_process() (see BEGIN).
function opt_error(message) {
  printf("%s: error: %s\n", PROGRAM, message) > STDERR
  OPTION_ERRORS++
}

# Report the operands that are assignments, e.g., VARS=0. awk makes them after BEGIN, which
# is too late for the options. Options must be given with -v.
function opt_report_assignment_operands(k) { #locals
  for (k = 1; k < ARGC; k++) {
    if (ARGV[k] ~ /^[A-Za-z_][A-Za-z0-9_]*=/) {
      opt_error(sprintf("'%s' is an assignment: give options with -v (-v %s)",
                        ARGV[k], ARGV[k]))
    }
  }
}

# Parse spec, the value of SUB or DSUB. Its items are separated by ;, and \; is a ; inside
# an item. Each item can start with parameters <p1:v1,...>:
#   SUB   NAME:VALUES, NAME:LABEL:VALUES or NAME::VALUES (an empty label is no label)
#   DSUB  NAME:VALUE (no_labels is set)
#
# The separators are the first colon (DSUB) or the first two colons (SUB): the value is
# everything after them, so it can hold colons. For SUB, t::/a:b gives the value /a:b, while
# t:/a:b gives the label /a and the value b.
#
# Empty items are skipped. Invalid items and parameters are reported and skipped. An item
# is invalid without a colon or a name, or when its name is given twice.
#
# Fill:
#   param_table:           the parameters, in the rows of the table (see init_globals, and the
#                          store_*_params functions)
#   sub_labels_array[NAME] = LABEL (only for a name with a label)
#   sub_values_array[NAME] = VALUES
#   sub_names_array[1..n]: the names in the order given
function opt_form_substitutions(spec, no_labels,
                                param_table, sub_labels_array, #fill
                                sub_values_array, sub_names_array, #fill
                                split_substitutions, k, n, string, substitution_params, #locals
                                substitution_rest, name, label, values, colon, has_label, #locals
                                n_substitutions, option) { #locals
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
      opt_error(sprintf("%s: '%s' should be %s", option, string,
                        no_labels ? "NAME:VALUE" : "NAME:[[LABEL]:][VALUES]"))
      continue
    }
    name = substr(substitution_rest, 1, colon - 1)
    values = substr(substitution_rest, colon + 1)
    has_label = 0
    colon = no_labels ? 0 : index(values, ":")
    if (colon > 0) {
      label = substr(values, 1, colon - 1)
      label = strip_blanks(label)
      values = substr(values, colon + 1)
      has_label = (label != "") # NAME::VALUES (or a blank label) has no label
    }
    name = strip_blanks(name)

    if (name == "") {
      opt_error(sprintf("%s: '%s' has an empty NAME", option, string))
      continue
    }
    if (name in sub_values_array) {
      opt_error(sprintf("%s: '%s' is given more than once", option, name))
      continue
    }
    if (no_labels) {
      opt_store_dsub_params(name, substitution_params, param_table)
    } else {
      opt_store_sub_params(name, substitution_params, param_table)
    }

    sub_names_array[++n] = name
    sub_values_array[name] = values
    if (has_label) {
      sub_labels_array[name] = label
    }
  }
}

# Split the parameters of a substitution, "k1:v1,k2:v2,...", and return their number n. In a
# pair, only the first colon is a separator, and a comma in a value is written \,
#
# Fill:
#   params[key] = value
#   keys[1..n]: the keys in the order given
function opt_parse_substitution_params(string,
                                       params, keys, #fill
                                       k, n, n_pairs, key_values, pair, key) { #locals
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
    key = strip_blanks(pair[1])
    params[key] = substr(key_values[k], length(pair[1]) + 2) # after the first colon
    keys[++n] = key
  }
  return n
}

# Copy the row of defaults, "", of a table of parameters to the row name. The keys of the
# row "" are collected first, because adding elements to an array while looping over it is
# undefined.
function opt_copy_param_defaults(name,
                                 table, #update
                                 key, defaults) { #locals
  for (key in table) {
    if (index(key, SUBSEP) == 1) {
      defaults[substr(key, length(SUBSEP) + 1)] = table[key]
    }
  }
  for (key in defaults) {
    table[name, key] = defaults[key]
  }
}

# Parse string_with_parameters, the parameters of name in option (SUB or DSUB). Report the
# repeated and the unknown parameters, and return the number n of the others. allowed lists
# the known keys for the message, e.g., "A or D".
#
# Update:
#   table: the row name starts with the defaults (see opt_copy_param_defaults)
#
# Fill:
#   params[key] = value, for the other parameters
#   keys[1..n]: their keys in the order given
function opt_checked_params(option, allowed, name, string_with_parameters,
                            table, #update
                            params, keys, #fill
                            all_params, all_keys, k, n, n_all, key, seen) { #locals
  opt_copy_param_defaults(name, table)
  split("", params)
  split("", keys)
  split("", seen)
  n = 0
  n_all = opt_parse_substitution_params(string_with_parameters, all_params, all_keys)
  for (k = 1; k <= n_all; k++) {
    key = all_keys[k]
    if (key in seen) {
      opt_error(sprintf("%s: parameter %s of %s is given more than once", option, key,
                        name))
    } else if (!(("", key) in table)) {
      opt_error(sprintf("%s: unknown parameter %s of %s (use %s)", option, key, name,
                        allowed))
    } else {
      keys[++n] = key
      params[key] = all_params[key]
    }
    seen[key] = 1
  }
  return n
}

# Store the parameters of the SUB substitution of name in its row of table. The row starts
# with the defaults, and the valid parameters of string_with_parameters replace them.
# Invalid parameters are reported. L, M and N are stored as numbers.
function opt_store_sub_params(name, string_with_parameters,
                              table, #update
                              params, keys, k, n, key, value) { #locals
  n = opt_checked_params("SUB", "L, M, N, S, P, I or T", name, string_with_parameters, table,
                         params, keys)
  for (k = 1; k <= n; k++) {
    key = keys[k]
    value = strip_blanks(params[key])
    if ((key == "L" || key == "M") && !is_bool(value)) {
      opt_error(sprintf("SUB: parameter %s of %s should be 0 or 1", key, name))
    } else if (key == "N" && value !~ /^(-1|[0-9]+)$/) {
      opt_error(sprintf("SUB: parameter N of %s should be -1 or a non-negative integer",
                        name))
    } else {
      # S, P, I and T as given (their blanks are part of them)
      table[name, key] = (key == "L" || key == "M" || key == "N") ? value + 0 : params[key]
    }
  }
}

# Store the parameters of the DSUB substitution of name in its row of table, as numbers. The
# row starts with the defaults, and the valid parameters of string_with_parameters replace
# them. Invalid parameters are reported. The parameters are:
#   A  0: (default) the names of anchors are not changed, 1: name is replaced in them too
#   D  0: the docs and section titles are not changed, 1: (default) name is replaced in them
function opt_store_dsub_params(name, string_with_parameters,
                               table, #update
                               params, keys, k, n, key, value) { #locals
  n = opt_checked_params("DSUB", "A or D", name, string_with_parameters, table, params, keys)
  for (k = 1; k <= n; k++) {
    key = keys[k]
    value = strip_blanks(params[key])
    if (!is_bool(value)) {
      opt_error(sprintf("DSUB: parameter %s of %s should be 0 or 1", key, name))
    } else {
      table[name, key] = value + 0
    }
  }
  if (!table[name, "A"] && !table[name, "D"]) {
    opt_error(sprintf("DSUB: %s is replaced nowhere (A and D are both 0)", name))
  }
}

# The help: the usage, then the options with their current values. The values are in double
# quotes, so that empty values and blanks show.
function opt_print_help() {
  print "Usage: awk [-v option=value] -f makefile-doc.awk [Makefile ...] (default: stdin)"
  print "Description: Generate docs for Makefile variables and targets"
  print "Version: " VERSION
  print "Options (current values):"
  opt_print_option("VARS", "show documented variables (0 or 1)", VARS)
  opt_print_option("DEPRECATED", "show deprecated anchors (0 or 1)", DEPRECATED)
  opt_print_option("PADDING", "character between anchors and docs", PADDING)
  opt_print_option("OFFSET", "spaces between names and docs", OFFSET)
  opt_print_option("WARN", "print warnings on stderr (0 or 1)", WARN)
  opt_print_option("COLOR", "use colors (0 or 1)", COLOR)
  opt_print_option("OUTPUT_FORMAT", or_list(OUTPUT_FORMATS), OUTPUT_FORMAT)
  # (EXPORT_THEME, SUB and DSUB have no default: with "", gawk --lint does not warn about them)
  opt_print_option("EXPORT_THEME", "colors of the HTML and LaTeX output", EXPORT_THEME "")
  opt_print_option("SUB", "rename anchors and list values", SUB "")
  opt_print_option("DSUB", "replace text in docs and names", DSUB "")
  opt_print_option("RECIPEPREFIX", "the .RECIPEPREFIX of the Makefile",
                   RECIPEPREFIX == "\t" ? "\\t" : RECIPEPREFIX)
  opt_print_option("COLOR_DEFAULT", "anchors documented with ##", COLOR_DEFAULT)
  opt_print_option("COLOR_ATTENTION", "anchors documented with ##!", COLOR_ATTENTION)
  opt_print_option("COLOR_DEPRECATED", "anchors documented with ##%", COLOR_DEPRECATED)
  opt_print_option("COLOR_SECTION", "sections", COLOR_SECTION)
  opt_print_option("COLOR_BACKTICKS", "text in backticks", COLOR_BACKTICKS)
}

# one line of the help: an option, its description and its value
function opt_print_option(name, description, value) {
  printf("  %-16s  %-35s  \"%s\"\n", name, description, value)
}

# Check COLOR, EXPORT_THEME and the COLOR_* options. COLOR is 1 by default, or 0 when
# NO_COLOR is set. Without colors, the COLOR_* options are 0.
function opt_colors() {
  COLOR = COLOR == "" ? opt_default_color() : COLOR
  if (!is_bool(COLOR)) {
    opt_error("COLOR should be 0 or 1")
    COLOR = 1
  }

  opt_export_theme() # EXPORT_THEME overrides colors of EXPORT_PALETTE

  COLOR_DEFAULT = opt_ansi_param("COLOR_DEFAULT", COLOR_DEFAULT == "" ? 34 : COLOR_DEFAULT)
  COLOR_ATTENTION = opt_ansi_param("COLOR_ATTENTION", COLOR_ATTENTION == "" ? 31 : COLOR_ATTENTION)
  COLOR_DEPRECATED = opt_ansi_param("COLOR_DEPRECATED",
                                    COLOR_DEPRECATED == "" ? 33 : COLOR_DEPRECATED)
  COLOR_SECTION = opt_ansi_param("COLOR_SECTION", COLOR_SECTION == "" ? 32 : COLOR_SECTION)
  COLOR_BACKTICKS = opt_ansi_param("COLOR_BACKTICKS", COLOR_BACKTICKS == "" ? 33 : COLOR_BACKTICKS)
  if (!COLOR) {
    COLOR_DEFAULT = COLOR_ATTENTION = COLOR_DEPRECATED = COLOR_SECTION = COLOR_BACKTICKS = 0
  }
}

# the default of the COLOR option: 0 if NO_COLOR is set to a non-empty value (no-color.org)
function opt_default_color() {
  return ("NO_COLOR" in ENVIRON && ENVIRON["NO_COLOR"] != "") ? 0 : 1
}

# Return the ANSI color parameter given for a COLOR_* option (0 means no color). An
# unsupported value is reported (see opt_error).
function opt_ansi_param(option, ansi_param) {
  # the supported parameters: the colors (EXPORT_PALETTE) and the attributes, e.g., bold
  if (ansi_param in EXPORT_PALETTE || ansi_param in ANSI_TO_HTML_VALUE) {
    # The explicit cast to int here is needed only because of a busybox awk bug,
    # see misc/busybox_awk_bug_20251107.awk
    return int(ansi_param)
  }
  opt_error(sprintf("%s should be one of 0, 1, 3, 4, 9, 30-37, 40-47, 90-97, 100-107",
                    option))
  return 0
}

# Apply EXPORT_THEME, a list ANSI_PARAM:HEX_COLOR[,...]. It sets the colors of the parameters
# 30-37, 40-47, 90-97 and 100-107, and of FG and BG. Invalid entries are reported.
function opt_export_theme(entries, k, n, entry, ansi_param, hex_color) { #locals
  n = split(EXPORT_THEME, entries, ",")
  for (k = 1; k <= n; k++) {
    if (entries[k] ~ /^[ \t]*$/) {
      continue # an empty entry, e.g., after a trailing comma
    }
    split(entries[k], entry, ":")
    ansi_param = entry[1]
    hex_color = array_get(entry, 2) # "" if there is no colon
    if (ansi_param != "FG" && ansi_param != "BG" && !(ansi_param in EXPORT_PALETTE)) {
      opt_error(sprintf("EXPORT_THEME: '%s' should start with FG, BG or one of %s",
                        entries[k], "30-37, 40-47, 90-97, 100-107"))
    } else if (!is_hex_color(hex_color)) {
      opt_error(sprintf("EXPORT_THEME: '%s' should end with a color of 6 hex digits",
                        entries[k]))
    } else if (ansi_param in EXPORT_PALETTE) {
      EXPORT_PALETTE[ansi_param] = hex_color
    } else {
      EXPORT_FG_BG[ansi_param] = hex_color
    }
  }
}

#### Output formats
# Everything that depends on OUTPUT_FORMAT (ANSI, HTML or LATEX): the color codes, the
# escapes, the header and the footer. The color options are checked in Options. Rendering
# does not read OUTPUT_FORMAT. It calls fmt_escape, fmt_color and fmt_document, and uses the
# color codes that fmt_init sets.

# The colors of the HTML and LaTeX output (EXPORT_THEME can change them):
#   EXPORT_PALETTE[param]  the hex color of an ANSI color parameter (30-37, 40-47, 90-97,
#                          100-107); the solarized theme is used by default
#                          https://github.com/altercation/solarized?tab=readme-ov-file#the-values
#   EXPORT_FG_BG[FG|BG]    the colors of the text and of the background ("" if not set)
function fmt_define_export_palette(k) { #locals
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

# The CSS property of each ANSI parameter, and the value of the attributes (the colors are
# in EXPORT_PALETTE)
function fmt_define_html_attributes(k) { #locals
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

function fmt_define_latex_functions(k) { #locals
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

# The code, in the output format, that starts text styled with ansi_color_param, or ends it:
#    0  no style ("")
#   -1  the code that ends a style (the user cannot set -1, see opt_ansi_param)
#   otherwise  the code that starts the color or attribute ansi_color_param (e.g., 34 or 1);
#              color_label_key names its class (HTML) or its color (LaTeX)
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
function fmt_html_style(ansi_color_param, label,
                        value) { #locals
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

# The CSS rule (one line) of the element with the class makefile-doc. It is an inline-block,
# so that a background (BG) covers only the text, not the whole width of the page as for a
# div; FG and BG are added if they are set.
function fmt_html_box_style(style) { #locals
  style = "display: inline-block;"
  if (EXPORT_FG_BG["FG"] != "") {
    style = style " color: #" EXPORT_FG_BG["FG"] ";"
  }
  if (EXPORT_FG_BG["BG"] != "") {
    style = style " background-color: #" EXPORT_FG_BG["BG"] ";"
  }
  return "  .makefile-doc { " style " }\n"
}

# Set the settings of the output format from OUTPUT_FORMAT and the color options. Only
# fmt_init, fmt_color_code and fmt_escape depend on OUTPUT_FORMAT.
function fmt_init() {
  OUTPUT_HEADER = OUTPUT_FOOTER = FMT_LINE_COLOR = ""
  FMT_RESTORE_AFTER_RESET = 0
  if (OUTPUT_FORMAT == "ANSI") {
    FMT_RESTORE_AFTER_RESET = 1 # a reset turns off all the colors (see fmt_color)
  } else if (OUTPUT_FORMAT == "HTML") {
    # an HTML fragment (to paste into a page): the styles, then the documentation
    OUTPUT_HEADER = "<style>\n" \
        fmt_html_style(COLOR_ATTENTION, "ATTENTION") \
        fmt_html_style(COLOR_SECTION, "SECTION") \
        fmt_html_style(COLOR_DEPRECATED, "DEPRECATED") \
        fmt_html_style(COLOR_DEFAULT, "DEFAULT") \
        fmt_html_style(COLOR_BACKTICKS, "BACKTICKS") \
        fmt_html_box_style() \
        "</style>\n<div class=\"makefile-doc\">\n<pre>\n"
    OUTPUT_FOOTER = "</pre>\n</div>\n"
  } else if (OUTPUT_FORMAT == "LATEX") {
    OUTPUT_HEADER = fmt_latex_header() "\n"
    OUTPUT_FOOTER = "\\end{alltt}\n\\end{varwidth}\n\\end{document}\n"
    # The text color FG is given to each line. With one \color for the whole documentation,
    # varwidth would not crop the page to the text.
    if (EXPORT_FG_BG["FG"] != "") {
      FMT_LINE_COLOR = "\\textcolor{" color_name("FG") "}{"
    }
  }

  COLOR_DEFAULT_CODE = fmt_color_code(COLOR_DEFAULT, "DEFAULT")
  COLOR_ATTENTION_CODE = fmt_color_code(COLOR_ATTENTION, "ATTENTION")
  COLOR_DEPRECATED_CODE = fmt_color_code(COLOR_DEPRECATED, "DEPRECATED")
  COLOR_SECTION_CODE = fmt_color_code(COLOR_SECTION, "SECTION")
  COLOR_BACKTICKS_CODE = fmt_color_code(COLOR_BACKTICKS, "BACKTICKS")
  COLOR_RESET_CODE = fmt_color_code(-1)
}

# a \definecolor line: the color of label (see color_name) is hex_color
function fmt_latex_definecolor(label, hex_color) {
  return sprintf("\\definecolor{%s}{HTML}{%s}\n", color_name(label), hex_color)
}

# The hex color of an ANSI parameter. It is black for an attribute, e.g., bold, and for no color.
function fmt_latex_hex_color(ansi_color_param) {
  return (ansi_color_param in EXPORT_PALETTE) ? EXPORT_PALETTE[ansi_color_param] : "000000"
}

# the preamble of the LaTeX output, up to the start of the documentation
function fmt_latex_header(header) { #locals
  header = "\\documentclass{article}\n"
  # With pdflatex, Latin Modern in T1, which has a bold monospace font for \textbf. With
  # xelatex, lualatex and tectonic, fontspec, for any Unicode text that the monospace font has.
  header = header "\\usepackage{iftex}\n"
  header = header "\\ifPDFTeX\n"
  header = header "  \\usepackage[T1]{fontenc}\n"
  header = header "  \\usepackage{lmodern}\n"
  header = header "\\else\n"
  header = header "  \\usepackage{fontspec}\n"
  header = header "\\fi\n"
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
    header = header fmt_latex_definecolor("FG", EXPORT_FG_BG["FG"])
  }
  if (EXPORT_FG_BG["BG"] != "") {
    header = header fmt_latex_definecolor("BG", EXPORT_FG_BG["BG"])
  }
  header = header fmt_latex_definecolor("ATTENTION", fmt_latex_hex_color(COLOR_ATTENTION))
  header = header fmt_latex_definecolor("SECTION", fmt_latex_hex_color(COLOR_SECTION))
  header = header fmt_latex_definecolor("DEPRECATED", fmt_latex_hex_color(COLOR_DEPRECATED))
  header = header fmt_latex_definecolor("DEFAULT", fmt_latex_hex_color(COLOR_DEFAULT))
  header = header fmt_latex_definecolor("BACKTICKS", fmt_latex_hex_color(COLOR_BACKTICKS))
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

# Escape <, > and &, which HTML reads as markup. & goes first, so that the & of the other
# escapes is not escaped again. string_replace is used because & is special in gsub.
function fmt_html_escape(text) {
  text = string_replace("&", "&amp;", text)
  text = string_replace("<", "&lt;", text)
  return string_replace(">", "&gt;", text)
}

# In \begin{alltt} ... \end{alltt}, only \, { and } are special. The backslashes go through
# PLACEHOLDER: escaping them first would escape the braces of \textbackslash{}, and
# escaping them last would escape the backslashes of \{ and \}.
function fmt_latex_escape(text) {
  text = string_replace("\\", PLACEHOLDER, text)
  gsub(/\{/, "\\{", text)
  gsub(/\}/, "\\}", text)
  return string_replace(PLACEHOLDER, "\\textbackslash{}", text)
}

# ---------------------------------------------------------------------------------------
# What rendering calls
# ---------------------------------------------------------------------------------------

# text with the escapes of the output format (none in ANSI), applied before the colors are
# added
function fmt_escape(text) {
  if (OUTPUT_FORMAT == "HTML") {
    return fmt_html_escape(text)
  } else if (OUTPUT_FORMAT == "LATEX") {
    return fmt_latex_escape(text)
  }
  return text
}

# Color text with color_code, each line on its own, so that no color crosses a line break.
# In LaTeX, varwidth cannot crop the page to a color that does. Empty lines are not colored.
# In ANSI, a reset inside text, e.g., after text in backticks, turns off all the colors, so
# color_code is restored after it (FMT_RESTORE_AFTER_RESET).
function fmt_color(text, color_code,
                   n, lines, k) { #locals
  if (color_code == "") {
    return text
  }
  if (FMT_RESTORE_AFTER_RESET) {
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

# The document: body between OUTPUT_HEADER and OUTPUT_FOOTER, each line in FMT_LINE_COLOR
# if it is set (see fmt_init)
function fmt_document(body) {
  if (FMT_LINE_COLOR != "") {
    body = fmt_color(body, FMT_LINE_COLOR)
  }
  return OUTPUT_HEADER body OUTPUT_FOOTER
}

#### Parsing
# The parser follows misc/docs/parser-model.tex, and the comments use its names, written in
# ASCII. For example, L_i is the logical line i, r_bar is r with a bar, and O_i[x] is the
# observation x of L_i.
#
# parser_file_start resets the state and the memory at the first line of each file.
# parser_join joins a physical line with the next ones while it ends with an odd number of
# backslashes. parser_process then processes each logical line in five steps:
#  1. observations       (parser_observe)
#  2. kind, and e_i      (parser_kind, parser_documented)
#  3. anchor record      (parser_record_anchor, see init_globals)
#  4. state transition   (parser_step)
#  5. memory transition  (parser_carry)
# Step 3 reads the state and the memory before steps 4 and 5 change them.
# The rules FNR == 1 and { ... } at the end of the section run the reset and the steps.

# Record a warning about line of file ("" for none), printed before the docs (see
# render_print_warnings).
function parser_add_warning(file, line, message) {
  WARNING_COUNT++
  WARNINGS[WARNING_COUNT, "file"] = file
  WARNINGS[WARNING_COUNT, "line"] = line
  WARNINGS[WARNING_COUNT, "message"] = message
}

# A last line that ends with a backslash cannot be joined, so it is not parsed. awk has no
# hook at the end of a file, so this is called at the next file and in END. A continued
# recipe line is not reported, because its rule ends with the file anyway.
function parser_warn_about_continued_last_line() {
  if (PARSER_JOINER["joining"] &&
      !(PARSER_STATE["r"] && substr(PARSER_JOINER["pending"], 1, 1) == PARSER_STATE["p"])) {
    parser_add_warning(PARSER_CONTEXT["file"], PARSER_JOINER["start"],
                       "the last line ends with a backslash")
  }
}

# the tag of a doc line (##, ##! or ##%), or "" if it does not start with one
function parser_get_doc_tag(string) {
  return match(string, TAG_REGEX) ? substr(string, 1, RLENGTH) : ""
}

# The structure of a line.
#
# Fill:
#   obs["line_kind"]:   the kind of the line as if no rule were open (assignment, rule,
#                       special rule, neutral, banner, section, doc or other)
#   obs["anchor_kind"]: target or variable for an assignment or a rule line, "" otherwise
#   obs["anchor_name"]: the (stripped) name of the anchor, "" if no anchor
#   obs["comment"]:     the comment after the anchor, from its # to the end of the line ("" if none)
#
# and, depending on the line:
#   obs["override"], obs["operator"], obs["value"], obs["double"], obs["grouped"]
#
# See the examples in test/parser.spec (and test/unit/test_parser.awk).
# See parser_observe for additional observations.
function parser_structure(line,
                          obs, #fill
                          first_word, define_name, qualifiers) { #locals
  split("", obs)
  obs["line_kind"] = ""
  obs["anchor_kind"] = ""
  obs["anchor_name"] = ""
  obs["comment"] = ""

  if (line ~ /^[ \t]*$/) {                    # question 1: a blank line
    obs["line_kind"] = "neutral"
    return
  }
  if (line ~ /^[ \t]*#/) {                    # question 2: a comment
    obs["line_kind"] = line ~ /^[ \t]*###/ ? "banner" : \
                       line ~ /^[ \t]*##@/ ? "section" : \
                       line ~ /^[ \t]*##/ ? "doc" : "neutral"
    return
  }

  parser_scan(line, obs) # questions 3 and 5: assignment, rule or ""
  if (obs["line_kind"] == "assignment") {
    return
  }

  first_word = line
  sub(/^[ \t]+/, "", first_word)
  sub(/[ \t(].*$/, "", first_word)
  define_name = parser_define_name(line, qualifiers)
  # question 4: a keyword
  if (first_word ~ /^(ifeq|ifneq|ifdef|ifndef|else|endif)$/) {
    parser_clear("neutral", obs)
  } else if (define_name != "") { # before the directives: `export define V`
    parser_clear("assignment", obs)
    obs["anchor_kind"] = "variable"
    obs["anchor_name"] = define_name
    obs["override"] = qualifiers["override"]
  } else if (first_word ~ /^(include|-include|sinclude|vpath|export|unexport|undefine|endef)$/) {
    parser_clear("other", obs)
  } else if (obs["line_kind"] == "rule") { # question 6: special targets
    if (parser_all_special(obs["anchor_name"])) {
      parser_clear("special rule", obs)
    }
  } else {
    parser_clear("other", obs)
  }
}

# 1 if every target of names is a special target (e.g., `.PHONY .SILENT`), 0 otherwise
function parser_all_special(names,
                            words, n, k) { #locals
  n = split(names, words, " ")
  for (k = 1; k <= n; k++) {
    if (words[k] !~ SPECIAL_TARGETS_REGEX) {
      return 0
    }
  }
  return n > 0
}

function parser_clear(line_kind,
                      obs) { #update
  obs["line_kind"] = line_kind
  obs["anchor_kind"] = ""
  obs["anchor_name"] = ""
  obs["comment"] = ""
}

# The name of the variable of a define line, e.g., V in `override define V :=`, or "" for
# another line. qualifiers["override"] is 1 if override comes before define.
function parser_define_name(line,
                            qualifiers, #fill
                            rest) { #locals
  rest = substr(line, parser_qualifiers(line, qualifiers))
  if (rest !~ /^define[ \t]+[^ \t]/) {
    return ""
  }
  sub(/^define[ \t]+/, "", rest)
  sub(/[ \t].*$/, "", rest)
  sub(/(:::=|::=|:=|\+=|\?=|!=|=)$/, "", rest) # an operator without a blank before it
  return rest
}

# The searches of the lexical layer: on the masked line, find whether line is an assignment
# or a rule, and cut the fields from line.
#
# Update:
#   obs["line_kind"]:   assignment (also target-specific), rule, or unchanged ("") if neither
#   obs["anchor_kind"]: variable or target
#   obs["anchor_name"]: the name of the anchor
#   obs["comment"]:     from the # to the end of the line ("" if none)
#
# for an assignment to a variable:
#   obs["override"], obs["operator"]
#   obs["value"] (leading blanks and comment removed)
#
# for a rule:
#   obs["double"], obs["grouped"]
function parser_scan(line,
                     obs, #update
                     masked, p, c, q, start, end, after, rest, hit, name, left, name_start, #locals
                     qualifiers) { #locals
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
    # The left side holds the qualifiers, then the name, a single word. A reference is part
    # of a word, so the words are found on the masked line. The name is cut from line.
    left = substr(masked, 1, start - 1)
    name_start = parser_qualifiers(left, qualifiers)
    rest = substr(left, name_start)
    sub(/[ \t]+$/, "", rest)
    end = c == "=" ? p : q + 1 # the = of the operator
    if (rest != "" && rest !~ /[ \t]/) {
      obs["line_kind"] = "assignment"
      obs["anchor_kind"] = "variable"
      obs["anchor_name"] = substr(line, name_start, length(rest))
      obs["override"] = qualifiers["override"]
      obs["comment"] = parser_comment_after(line, masked, end, 0)
      obs["operator"] = substr(line, start, end - start + 1)
      obs["value"] = substr(line, end + 1, length(line) - end - length(obs["comment"]))
      sub(/^[ \t]+/, "", obs["value"])
      return
    }
    # Not an assignment: the first colon after the operator, if no # comes before it, is the
    # separating colon (e.g., `a b = c: d` is a rule with the targets a, b, = and c).
    rest = substr(masked, end + 1)
    p = match(rest, /[#:]/)
    if (!p || substr(rest, p, 1) == "#") {
      return
    }
    p += end
    q = p
    while (substr(masked, q + 1, 1) == ":") {
      q++
    }
  }

  # p is the separating colon (:, :: or &:)
  name = substr(line, 1, p - 1)
  sub(/[ \t]*&$/, "", name)
  sub(/^[ \t]+/, "", name)
  sub(/[ \t]+$/, "", name)
  if (name == "") {
    return
  }
  obs["line_kind"] = "rule"
  obs["anchor_kind"] = "target"
  obs["anchor_name"] = name
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
    obs["line_kind"] = "assignment"
    obs["comment"] = parser_comment_after(line, masked, hit, 1)
  }
}

# The comment that follows position p in line, from its # to the end of the line, "" if none.
# The search runs on masked after p:
#   is_target_specific = 0  the first # starts the comment
#   is_target_specific = 1  the same, unless a ; comes first. Then there is no comment,
#                           because GNU Make puts everything after the ; into the value.
function parser_comment_after(line, masked, p, is_target_specific,
                              rest, k) { #locals
  rest = substr(masked, p + 1)
  k = match(rest, is_target_specific ? "[#;]" : "#")
  return (k && substr(rest, k, 1) == "#") ? substr(line, p + k) : ""
}

# Read the qualifiers export, override and private at the start of text, the left side of an
# assignment or a define line. Return the position of the first character after them and
# their blanks, or 1 if there are none.
#
# Fill:
#   qualifiers["override"]: 1 if override is among them, 0 otherwise
function parser_qualifiers(text,
                           qualifiers, #fill
                           len) { #locals
  split("", qualifiers)
  sub(/[ \t]+$/, "", text) # a last word followed only by blanks is not a qualifier
  match(text, /^[ \t]*((export|override|private)[ \t]+)*/)
  len = RLENGTH
  qualifiers["override"] = (" " substr(text, 1, len)) ~ /[ \t]override[ \t]/
  return len + 1
}

# Return line with its references and escape pairs replaced by _ (the result has the same length):
#   $(...) ${...}   a reference, up to its matching bracket
#   $c              a one-character reference
#   \\ \# \: \;     an escape pair
# See the examples in test_parser_mask (test/unit/test_parser.awk).
function parser_mask(line,
                     n, k, c, next_char, end, out, rest) { #locals
  if (!index(line, "$") && !index(line, "\\")) {
    return line # nothing to mask (the usual case)
  }
  n = length(line)
  out = ""
  k = 1
  while (k <= n) {
    # Copy the characters up to the next $ or \ in one piece, not one by one. The one true
    # awk and wak count UTF-8 characters without an index, so their substr walks the string
    # from its start. A loop over the characters would take quadratic time there. In gawk and
    # in the awks that count bytes, substr takes constant time.
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

# Return the position of the bracket that closes the reference whose $ is at position k of
# line, or the length of line if it is not closed.
#
# The characters are read one by one, because nested brackets must be counted, which a regex
# cannot do. A reference is short anyway.
function parser_reference_end(line, k,
                              n, opening, closing, depth, c) { #locals
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
# The model (misc/docs/parser-model.tex). Its arrays:
#   state                the state x_i
#     state["r"]           r_i: a rule is open
#     state["d"]           d_i: a doc is pending
#     state["s"]           s_i: a section is pending
#     state["p"]           p_i: the recipe prefix
#   memory               the memory D_i and S_i
#     memory["doc", k]     the lines of D_i, k = 1..memory["dn"]
#     memory["doc_tag"]    the tag of the first line of D_i
#     memory["section", k] the lines of S_i, k = 1..memory["sn"]
#   obs                  the observations O_i (see parser_observe)
#   derived              the derived quantities of L_i
#     derived["k"]         k_i
#     derived["e"]         e_i
# The reset at the first line of a file is applied to state and memory (see parser_file_start).
# ---------------------------------------------------------------------------------------

# The initial state and memory. prefix is p_0, the RECIPEPREFIX option (a tab by default).
#
# Fill:
#   state:  x_0 = (0, 0, 0, p_0)
#   memory: D_0 = S_0 = empty
function parser_init(prefix,
                     state, memory) { #fill
  split("", state)
  state["r"] = 0
  state["d"] = 0
  state["s"] = 0
  state["p"] = prefix == "" ? "\t" : substr(prefix, 1, 1)
  split("", memory)
  memory["dn"] = 0
  memory["sn"] = 0
}

# The reset at the first line of a file (b_i = 1): no rule is open and no doc is pending; the
# section and the recipe prefix carry over.
#
# Update:
#   state["r"] = state["d"] = 0
#   memory["dn"] = 0 (D is emptied)
function parser_file_start(state, memory) { #update
  state["r"] = 0
  state["d"] = 0
  memory["dn"] = 0
}

# O_i = obs(L_i), the observations of a line. They depend only on the line, not on the state
# or the memory.
#
# Fill (besides the fields of parser_structure):
#   obs["first_char"]: the first character of the line ("" for an empty line)
#   obs["inline"]:     1 if the line has an anchor and its comment starts with ## but not
#                      ##@ or ### (an inline doc)
#   obs["inline_doc"]: that comment without its tag and the one blank after it ("" if none)
#   obs["text"]:       the line without its leading blanks, its tag and the one blank after
#                      it, for a doc or section line ("" otherwise)
#   obs["tag"]:        the tag of a doc line or of the inline doc (##, ##! or ##%), "" otherwise
#   obs["prefix"]:     the prefix that the line assigns to .RECIPEPREFIX ("" otherwise)
function parser_observe(line,
                        obs) { #fill
  parser_structure(line, obs)
  obs["first_char"] = substr(line, 1, 1)
  obs["inline"] = obs["anchor_kind"] != "" && obs["comment"] ~ /^##/ &&
                  obs["comment"] !~ /^(##@|###)/
  obs["inline_doc"] = ""
  obs["text"] = ""
  obs["tag"] = ""
  if (obs["line_kind"] == "doc") {
    obs["text"] = line
    sub(/^[ \t]+/, "", obs["text"])
    obs["tag"] = parser_get_doc_tag(obs["text"])
    sub(TAG_REGEX, "", obs["text"])
    sub(/^[ \t]/, "", obs["text"])                 # the one blank after the tag
  } else if (obs["line_kind"] == "section") {
    obs["text"] = line
    sub(/^[ \t]*##@/, "", obs["text"])
    sub(/^[ \t]/, "", obs["text"])                 # the one blank after the tag
  } else if (obs["inline"]) {
    obs["inline_doc"] = obs["comment"]
    obs["tag"] = parser_get_doc_tag(obs["inline_doc"])
    sub(TAG_REGEX, "", obs["inline_doc"])
    sub(/^[ \t]/, "", obs["inline_doc"])           # the one blank after the tag
  }
  obs["prefix"] = ""
  # obs["prefix"] is set only when the assignment to .RECIPEPREFIX is on the line itself.
  #   - A define is not followed, because its value is on the next lines: after
  #       define .RECIPEPREFIX
  #       >
  #       endef
  #     GNU Make uses the prefix >, and the parser keeps the previous one.
  #   - A target-specific assignment (t: .RECIPEPREFIX = >) does not change the prefix, as in
  #     GNU Make.
  # The operators are handled by parser_new_prefix.
  if (obs["line_kind"] == "assignment" && obs["anchor_kind"] == "variable" &&
      obs["anchor_name"] == ".RECIPEPREFIX" && ("operator" in obs)) {
    obs["prefix"] = parser_new_prefix(obs["operator"], obs["value"])
  }
}

# The prefix set by an assignment to .RECIPEPREFIX, from its operator and its value. It is ""
# when the prefix does not change, and a tab for an empty value.
#
# As GNU Make:
#   =         the first character of the value, as written (GNU Make does not expand it), e.g.,
#             .RECIPEPREFIX = $a changes the prefix to $
#   :=, ::=   the first character of the value, when it has no reference ($)
#   ?=        "": .RECIPEPREFIX is always defined (origin default), so nothing changes
#   +=        "", when .RECIPEPREFIX has a value: its first character does not change
#   \#        a value that starts with an escaped # gives #: GNU Make removes the backslash
#
# Unlike GNU Make (we return ""):
#   :=, ::=   with a reference: GNU Make expands it (its value is not known from the line)
#   !=        GNU Make runs the command (its output is not known from the line)
#   +=        when .RECIPEPREFIX is empty (the default), GNU Make takes the first character
#             Handling it would need the state of the parser, but by design, the observations
#             depend only on the line.
function parser_new_prefix(operator, value) {
  if (operator == "+=" || operator == "?=" || operator == "!=" ||
      (operator ~ /^:+=$/ && index(value, "$") > 0)) {
    return ""
  }
  if (index(value, "\\#") == 1) {
    return "#"
  }
  return value == "" ? "\t" : substr(value, 1, 1)
}

# Return k_i, the kind of the line, from the state x_{i-1} (after the reset) and the
# observations O_i:
#   k_i = recipe           if r_bar_{i-1} = 1 and O_i[first_char] = p_{i-1}
#         O_i[line_kind]   otherwise
function parser_kind(state, obs) {
  return (state["r"] && obs["first_char"] == state["p"]) ? "recipe" : obs["line_kind"]
}

# Return e_i, whether the line is an anchor that gets documented, from the state x_{i-1}
# (after the reset), the observations O_i and the kind k_i:
#   e_i = 1   if k_i in {rule, assignment} and (d_bar_{i-1} = 1 or O_i[inline] = 1)
#         0   otherwise
function parser_documented(state, obs, k) {
  return (k == "rule" || k == "assignment") && (state["d"] || obs["inline"])
}

# The state transition, from the observations obs, the kind of the line k and e_i (see
# parser_documented).
#
# Update:
#   state: x_{i-1} (after the reset) becomes x_i
function parser_step(obs, k, e,
                     state) { #update
  if (k == "recipe" || k == "rule" || k == "special rule") {
    state["r"] = 1                   # r_i = 1             if k_i in {recipe, rule, special rule}
  } else if (k == "assignment" || k == "other") {
    state["r"] = 0                   #       0             if k_i in {assignment, other}
  }                                  #       r_bar_{i-1}   if k_i in {neutral, doc, section,
                                     #                       banner}
  if (k == "doc") {
    state["d"] = 1                   # d_i = 1             if k_i = doc
  } else if (k == "recipe" || k == "banner" || k == "rule" || k == "assignment" ||
             k == "other") {
    state["d"] = 0                   #       0             if k_i in {recipe, banner, rule,
  }                                  #                       assignment, other}
                                     #       d_bar_{i-1}   if k_i in {neutral, section,
                                     #                       special rule}
  if (k == "section") {
    state["s"] = 1                   # s_i = 1             if k_i = section
  } else if (e) {
    state["s"] = 0                   #       0             if e_i = 1
  }                                  #       s_{i-1}       otherwise
  if (k != "recipe" && obs["prefix"] != "") {
    state["p"] = obs["prefix"]       # p_i = O_i[prefix]   if k_i != recipe and O_i[prefix]
  }                                  #                       is not none
                                     #       p_{i-1}       otherwise
}

# The memory transition, from the kind of the line k, the observations obs and the new state x_i.
#
# Update:
#   memory: D_bar_{i-1} and S_{i-1} become D_i and S_i
function parser_carry(state, obs, k,
                      memory) { #update
  if (k == "doc") {
    if (memory["dn"] == 0) {
      memory["doc_tag"] = obs["tag"]                # the tag of D_i: O_i[tag]
    }
    memory["doc", ++memory["dn"]] = obs["text"]     # D_i = D_bar_{i-1} + O_i[text]  if k_i = doc
  } else if (!state["d"]) {
    memory["dn"] = 0                                #       empty                    if d_i = 0
  }                                                 #       D_bar_{i-1}              otherwise
  if (k == "section") {
    memory["section", ++memory["sn"]] = obs["text"] # S_i = S_{i-1} + O_i[text]  if k_i = section
  } else if (!state["s"]) {
    memory["sn"] = 0                                #       empty                if s_i = 0
  }                                                 #       S_{i-1}              otherwise
}

# Process the logical line L_i: line, which starts at the physical line line_number of its file.
#
# Update:
#   state, memory: x_{i-1} and D_bar_{i-1}, S_{i-1} become x_i and D_i, S_i
#   context:       the anchors documented so far (see parser_record_anchor)
#
# Fill:
#   obs: the observations O_i (see parser_observe)
#   derived["k"] = k_i
#   derived["e"] = e_i
function parser_process(line, line_number,
                        state, memory, context, #update
                        obs, derived, #fill
                        k, e) { #locals
  parser_observe(line, obs)                                 # O_i = obs(L_i)
  k = parser_kind(state, obs)                               # k_i
  e = parser_documented(state, obs, k)                      # e_i
  if (e) {
    parser_record_anchor(obs, state, memory, line_number, context) # A_n
  }
  parser_step(obs, k, e, state)                             # x_i
  parser_carry(state, obs, k, memory)                       # (D_i, S_i)
  derived["k"] = k
  derived["e"] = e
}

# Record a documented anchor (e_i = 1) as the next record A_n of ANCHORS. It reads obs, and
# the state and the memory before their transitions: x_{i-1} after the reset, D_bar_{i-1}
# and S_{i-1}.
#   A_n[kind]      O_i[anchor_kind]
#   A_n[name]      O_i[anchor_name] (for a target, see parser_form_target_name)
#   A_n[doc]       the texts of D_bar_{i-1} if d_bar_{i-1} = 1, O_i[inline_doc] otherwise
#   A_n[tag]       the tag of D_bar_{i-1} if d_bar_{i-1} = 1, O_i[tag] otherwise
#   A_n[section]   S_{i-1} if s_{i-1} = 1, absent otherwise
#   A_n[override]  1 if O_i[override] = 1, absent otherwise
#
# A redefined doc is reported (see parser_add_warning), with line_number.
#
# Update:
#   context: the anchors documented so far
function parser_record_anchor(obs, state, memory, line_number,
                              context, #update
                              kind, name) { #locals
  kind = obs["anchor_kind"]
  name = kind == "target" ? parser_form_target_name(obs, context) : obs["anchor_name"]
  if (("seen", kind, name) in context) {
    parser_add_warning(context["file"], line_number,
                       sprintf("redefined docs of %s '%s'", kind, name))
  }
  context["seen", kind, name] = 1
  ANCHOR_COUNT++
  ANCHORS[ANCHOR_COUNT, "kind"] = kind
  ANCHORS[ANCHOR_COUNT, "name"] = name
  if (state["d"]) {
    ANCHORS[ANCHOR_COUNT, "doc"] = parser_memory_lines(memory, "doc", memory["dn"])
    ANCHORS[ANCHOR_COUNT, "tag"] = memory["doc_tag"]
  } else {
    ANCHORS[ANCHOR_COUNT, "doc"] = obs["inline_doc"]
    ANCHORS[ANCHOR_COUNT, "tag"] = obs["tag"]
  }
  if (state["s"]) {
    ANCHORS[ANCHOR_COUNT, "section"] = parser_memory_lines(memory, "section", memory["sn"])
  }
  if (("override" in obs) && obs["override"]) { # the command line cannot change it
    ANCHORS[ANCHOR_COUNT, "override"] = 1
  }
}

# the lines memory[key, 1..n] joined with \n
function parser_memory_lines(memory, key, n,
                             k, lines) { #locals
  lines = ""
  for (k = 1; k <= n; k++) {
    lines = k == 1 ? memory[key, k] : lines "\n" memory[key, k]
  }
  return lines
}

# The name of a documented target as displayed. A run of blanks becomes one space, because
# GNU Make reads it as one separator. Grouped targets get a & after them. The Nth documented
# rule of a double-colon target gets ~N, counted across files in context.
function parser_form_target_name(obs,
                                 context, #update
                                 name) { #locals
  name = obs["anchor_name"]
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
# The input of the model: the logical lines, joined from the physical lines. joiner holds
# the line being joined:
#   joiner["joining"]  1 if the last physical line continues on the next one, 0 otherwise
#   joiner["pending"]  the text joined so far
#   joiner["start"]    the number of the first physical line of the logical line
#   joiner["line"]     the logical line, once it is complete
# ---------------------------------------------------------------------------------------

# At the first line of a file: a line continued at the end of the previous file is dropped
function parser_join_init(joiner) { #fill
  split("", joiner)
  joiner["joining"] = 0
  joiner["pending"] = ""
}

# Add a physical line (number line_number in its file) to the logical line being joined:
#   return 1  the logical line is complete: joiner["line"], which starts at the physical line
#             joiner["start"]
#   return 0  the line continues on the next one, because it ends with an odd number of
#             backslashes (recipe lines too). It is kept in joiner["pending"].
# A final \r is removed (CRLF line endings). As in GNU Make, a backslash, the newline and the
# blanks around them become one space, and a line of only blanks adds nothing. E.g., called
# with each of the four physical lines
#   SRCS := a.c   \
#           b.c \
#       \
#           c.c
# it returns 0, 0, 0, then 1 with joiner["line"] = "SRCS := a.c b.c c.c" (joiner["pending"]
# is "SRCS := a.c", then "SRCS := a.c b.c" twice).
function parser_join(physical, line_number,
                     joiner, #update
                     stripped) { #locals
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

# Set FILES_PROCESSED to the input files: the operands of awk, or - (stdin) if there are none.
# It is called in END, because an empty file has no line to run the rule FNR == 1. (An
# assignment operand never gets here: opt_process rejects it.)
function parser_list_files(k) { #locals
  FILES_PROCESSED = ""
  for (k = 1; k < ARGC; k++) {
    if (ARGV[k] != "") { # awk skips an empty operand
      FILES_PROCESSED = (FILES_PROCESSED == "" ? "" : FILES_PROCESSED " ") ARGV[k]
    }
  }
  if (FILES_PROCESSED == "") {
    FILES_PROCESSED = "-"
  }
}

# stdin is named - (POSIX leaves FILENAME unspecified for it; most awks set it to -)
FNR == 1 {
  parser_warn_about_continued_last_line()
  parser_join_init(PARSER_JOINER)
  parser_file_start(PARSER_STATE, PARSER_MEMORY) # b_i = 1
  PARSER_CONTEXT["file"] = FILENAME == "" ? "-" : FILENAME
}

{
  if (parser_join($0, FNR, PARSER_JOINER)) {
    parser_process(PARSER_JOINER["line"], PARSER_JOINER["start"], PARSER_STATE, PARSER_MEMORY,
                   PARSER_CONTEXT, PARSER_OBS, PARSER_DERIVED)
  }
}

#### Rendering
# The documentation is displayed in two stages. render_prepare decides what is displayed and
# writes the DISPLAY records. render_documentation then lays them out in the output format.
# render_print_documentation runs both and prints the result.

# Print the warnings recorded while parsing. They depend only on the Makefiles: hidden
# anchors (VARS, DEPRECATED) are reported too.
function render_print_warnings(k, location) { #locals
  for (k = 1; k <= WARNING_COUNT; k++) {
    location = WARNINGS[k, "file"]
    if (WARNINGS[k, "line"] != "") {
      location = location ":" WARNINGS[k, "line"]
    }
    render_print_warning(location, WARNINGS[k, "message"])
  }
}

# Print a warning on stderr unless WARN is 0, in the GNU format: "program:location: warning:
# message", or "program: warning: message" when location is ""
function render_print_warning(location, message) {
  if (!WARN) {
    return
  }
  if (location != "") {
    printf("%s:%s: warning: %s\n", PROGRAM, location, message) > STDERR
  } else {
    printf("%s: warning: %s\n", PROGRAM, message) > STDERR
  }
}

# Fill DISPLAY from ANCHORS (parser's output) and VARS, DEPRECATED, SUB, DSUB (the settings)
function render_prepare(k, key, n, order, last, sections, anchor_kinds, i) { #locals
  split("", order)
  split("", last)

  n = 0
  for (k = 1; k <= ANCHOR_COUNT; k++) {
    key = ANCHORS[k, "kind"] SUBSEP ANCHORS[k, "name"]
    if (!(key in last)) {
      order[++n] = key
    }
    last[key] = k
  }
  # order[1..n]  the key of each distinct anchor, in the order of its first definition
  # last[key]    the index in ANCHORS of the last definition of the anchor

  render_place_sections(last, sections)
  # Together (order, last, sections) give the following rule: the last definition of an anchor
  # decides whether it is displayed and a displayed anchor appears once:
  #   - at the position of its first definition
  #   - with the doc and tag of its last definition (if it is displayed)
  #   - with the last section given to any of its definitions

  split("target variable", anchor_kinds, " ")  # the display order: first targets then variables
  for (i = 1; i <= 2; i++) {
    for (k = 1; k <= n; k++) {
      key = order[k]
      if (ANCHORS[last[key], "kind"] == anchor_kinds[i] && render_is_displayed(last[key])) {
        render_add_display_record(last[key], key, sections)
      }
    }
  }
}

# Whether the anchor of record k is displayed:
#   variables are hidden when VARS is 0
#   deprecated anchors (tag ##%) when DEPRECATED is 0.
function render_is_displayed(k) {
  if (!VARS && ANCHORS[k, "kind"] == "variable") {
    return 0
  }

  if (!DEPRECATED && ANCHORS[k, "tag"] == "##%") {
    return 0
  }

  return 1
}

# Give each section to a displayed anchor (see Docs for the kind of a section).
# last[key] is the index in ANCHORS of the last definition of an anchor.
#   - A section goes to the first displayed anchor of its kind, before the next section.
#   - With no such anchor, the section is dropped. (Sections with no documented anchor
#     between them are already merged by the parser.)
#   - A later section of the same anchor replaces an earlier one.
#
# Fill:
#   sections[key]: the section displayed above the anchor
function render_place_sections(last,
                               sections, #fill
                               k, key, kind, has_section, section, section_kind) { #locals
  split("", sections)
  has_section = 0
  for (k = 1; k <= ANCHOR_COUNT; k++) {
    kind = ANCHORS[k, "kind"]
    if ((k, "section") in ANCHORS) {
      section = ANCHORS[k, "section"]
      section_kind = kind
      has_section = 1
    }

    key = kind SUBSEP ANCHORS[k, "name"]
    if (has_section && kind == section_kind && render_is_displayed(last[key])) {
      sections[key] = section
      has_section = 0
    }
  }
}

# Add an anchor to DISPLAY, with what will be displayed: its name, its doc and section after
# DSUB, and its SUB values. k is its last definition in ANCHORS, and key its key in sections.
function render_add_display_record(k, key, sections,
                                   name) { #locals
  name = ANCHORS[k, "name"]
  DISPLAY_COUNT++
  DISPLAY[DISPLAY_COUNT, "kind"] = ANCHORS[k, "kind"]
  DISPLAY[DISPLAY_COUNT, "name"] = render_display_name(name)
  DISPLAY[DISPLAY_COUNT, "tag"] = ANCHORS[k, "tag"]
  DISPLAY[DISPLAY_COUNT, "doc"] = render_apply_doc_substitutions(ANCHORS[k, "doc"])
  if (key in sections) {
    DISPLAY[DISPLAY_COUNT, "section"] = render_apply_doc_substitutions(sections[key])
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
function render_display_name(anchor,
                             k, name) { #locals
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
function render_apply_doc_substitutions(text,
                                        k) { #locals
  for (k = 1; k <= DSUB_COUNT; k++) {
    if (DSUB_PARAM[DSUB_NAMES[k], "D"]) {
      text = string_replace(DSUB_NAMES[k], DSUB_VALUES[DSUB_NAMES[k]], text)
    }
  }
  return text
}

function render_separator(character, len_anchors) {
  return repeated_string(character, max(len_anchors,
                                        max(length(HEADER_TARGETS),
                                            length(HEADER_VARIABLES))))
}

# string with the text of each region in backticks colored with color_code, without the
# backticks. With color_code "", only the backticks are removed (see render_doc_width).
function render_substitute_backticks(string, color_code,
                                     before_match, inside_match, after_match) { #locals
  # (gensub with a back-reference would do this in one call, but it is only in gawk)
  while (match(string, /`([^`]+)`/)) {
    before_match = substr(string, 1, RSTART - 1)
    inside_match = substr(string, RSTART + 1, RLENGTH - 2)
    after_match = substr(string, RSTART + RLENGTH)

    string = before_match fmt_color(inside_match, color_code) after_match
  }
  return string
}

function render_backticks(doc) {
  if (COLOR_BACKTICKS_CODE != "") {
    return render_substitute_backticks(doc, COLOR_BACKTICKS_CODE)
  }
  return doc
}

# The width of the last line of doc as it is displayed: without the backticks that
# render_backticks removes
function render_doc_width(doc,
                          n, lines) { #locals
  if (COLOR_BACKTICKS_CODE != "") {
    doc = render_substitute_backticks(doc, "")
  }
  n = split(doc, lines, "\n")
  return n > 0 ? text_length(lines[n]) : 0
}

# the color code of an anchor, given by the tag of its doc
function render_anchor_color(tag) {
  if (tag == "##!") {
    return COLOR_ATTENTION_CODE
  } else if (tag == "##%") {
    return COLOR_DEPRECATED_CODE
  }
  return COLOR_DEFAULT_CODE # ## (a doc starts with one of the three tags)
}

function render_doc(doc, len_anchors,
                    n, lines) { #locals
  # colored before the lines are indented: a span in backticks that continues on the next
  # line does not color the indentation
  doc = render_backticks(fmt_escape(doc))
  n = split(doc, lines, "\n")
  return spaces(OFFSET) join(lines, n, "\n" spaces(OFFSET + len_anchors)) # aligned lines
}

# a section, with the escapes of the output format and the colors of the text in backticks
function render_section(section) {
  section = strip_trailing_blanks(section)
  return render_backticks(fmt_escape(section))
}

# Return the text after the doc of an anchor: its SUB values, then a newline. sub_values is
# space-separated, and its parameters are in the row sub_row of SUB_PARAM. Each value
# becomes an item, with P before it and S after it. The first item also starts with I, and
# the last one ends with T instead of S. The items are on one line (M=0) or one per line
# (M=1). They start after the doc (L=0) or on the next line (L=1). doc_width is the width of
# the last line of the doc (see render_doc_width).
function render_sub_values(sub_values, sub_row, len_anchors, doc_width,
                           values, n, k, item, lines, n_lines, initial, prefix, #locals
                           separator, termination, indentation, next_indentation, #locals
                           output) { #locals
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
    item = render_backticks(fmt_escape(item))
    if (SUB_PARAM[sub_row, "M"] || k == 1) {
      lines[++n_lines] = item
    } else {
      lines[n_lines] = lines[n_lines] " " item
    }
  }

  # The values line up with the text of the doc: the first one starts on the next line (L=1),
  # or after the doc and a space (L=0), where the doc starts if it is empty. indentation
  # ends where the first value starts.
  indentation = spaces(len_anchors + OFFSET)
  if (SUB_PARAM[sub_row, "L"]) {
    output = "\n" indentation lines[1]
  } else if (doc_width > 0) {
    output = " " lines[1]
    indentation = indentation spaces(doc_width + 1)
  } else {
    output = lines[1]
  }
  # the lines after the first are aligned with the first value (after I)
  next_indentation = indentation spaces(text_length(initial))
  for (k = 2; k <= n_lines; k++) {
    output = output "\n" next_indentation lines[k]
  }
  return output "\n"
}

# The text of one displayed anchor, as it appears in the help (len_anchors: the width of the
# column of names)
function render_anchor(k, len_anchors,
                       section, label, formatted_anchor, padding, color, output) { #locals
  output = ""
  if ((k, "section") in DISPLAY) { # (an empty section is a blank line)
    section = render_section(DISPLAY[k, "section"])
    output = fmt_color(section, COLOR_SECTION_CODE) "\n"
  }

  label = DISPLAY[k, "label"]
  formatted_anchor = fmt_escape(label)
  # The padding is measured on the label, because an HTML or LaTeX escape is longer than its
  # character. It is escaped too, because PADDING can be any character.
  padding = fmt_escape(repeated_string(PADDING, len_anchors - text_length(label)))
  color = render_anchor_color(DISPLAY[k, "tag"])
  if (color) {
    formatted_anchor = color formatted_anchor padding COLOR_RESET_CODE
  } else {
    formatted_anchor = formatted_anchor padding
  }

  output = output formatted_anchor render_doc(DISPLAY[k, "doc"], len_anchors) \
           render_sub_values(DISPLAY[k, "values"], DISPLAY[k, "sub_row"], len_anchors,
                             render_doc_width(DISPLAY[k, "doc"]))
  return strip_trailing_blanks(output)
}

# Return the documentation of the DISPLAY records in the output format. The targets come
# first, then the variables, each under a header. All names are padded to the longest one.
function render_documentation(k, len_anchors, separator, body) { #locals
  len_anchors = 0
  for (k = 1; k <= DISPLAY_COUNT; k++) {
    len_anchors = max(len_anchors, text_length(DISPLAY[k, "label"]))
  }
  separator = render_separator("-", len_anchors)

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
    body = body render_anchor(k, len_anchors)
  }
  if (DISPLAY_COUNT > 0) {
    body = body separator "\n"
  }
  return fmt_document(body)
}

# Print all the output: the warnings on stderr, then the documentation on stdout.
function render_print_documentation(document) { #locals
  render_prepare()
  render_print_warnings() # (on stderr, before the docs)
  document = render_documentation()
  if (DISPLAY_COUNT == 0 && FILES_PROCESSED != "") {
    if (ANCHOR_COUNT > 0) {
      render_print_warning("", "all documented targets/variables are hidden in " FILES_PROCESSED)
    } else {
      render_print_warning("", "no documented targets/variables in " FILES_PROCESSED)
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
    if (opt_process() > 0) {
      ABORT = 1
      exit 1
    }
    parser_init(RECIPEPREFIX, PARSER_STATE, PARSER_MEMORY)
  }
}

# Display the documentation (or print the help); nothing if BEGIN exited on an error
END {
  if (ABORT) {
    exit ABORT
  }
  if (!UNIT_TEST) {
    # Without a Makefile, awk reads stdin. If stdin is empty, e.g., < /dev/null or Ctrl-D in
    # a terminal, print the help.
    if (ARGC == 1 && NR == 0) {
      opt_print_help()
      exit 1
    }
    parser_warn_about_continued_last_line()
    parser_list_files()
    render_print_documentation()
  }
}

### makefile-doc.awk ends here
