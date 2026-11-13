#!/usr/bin/awk -f
# Generate docs for Makefile variables and targets
#
#    File: makefile-doc.awk
#  Author: Dimitar Dimitrov
# License: Apache-2.0
# Project: https://github.com/drdv/makefile-doc
#
# Usage (see project README.md for more details):
#   awk [-v option=value] -f makefile-doc.awk [Makefile ...]
#
# Notes:
#   * In the code, the term anchor is used to refer to Makefile targets / variables.
#   * Docs can be placed above an anchor or inline (the latter is discarded if the
#     former is present).
#   * Anchor docs can start with the following tokens:
#      * ##  default anchors (displayed in COLOR_DEFAULT)
#      * ##! special anchors (displayed in COLOR_ATTENTION)
#      * ##% deprecated anchor (displayed in COLOR_DEPRECATED)
#   * The token ##@ can be used to create sections (displayed in COLOR_SECTION)
#
# Options (possible values are given in {...}, (.) denotes the default):
#   + OUTPUT_FORMAT: {(ANSI), HTML, LATEX}
#   + EXPORT_THEME: see below
#   + SUB: see below
#   + DSUB: see below
#   + TARGETS_REGEX: regex for matching targets
#   + VARIABLES_REGEX: regex for matching variables
#   * VARS: {0, (1)} show documented variables
#   * PADDING: {(" "), ".", ...} a single padding character between anchors and docs
#   * DEPRECATED: {0, (1)} show deprecated anchors
#   * OFFSET: {0, 1, (2), ...} number of spaces to offset docs from anchors
#   * COLOR: {0, (1)} 0 turns off all colors (the default is 0 if the environment variable
#     NO_COLOR is set to a non-empty value, see https://no-color.org)
#   + RECIPEPREFIX: should have the same value as the .RECIPEPREFIX from your Makefile
#   * see as well the color codes below
#
#   An invalid value is an error: all the invalid options are reported (on stderr), nothing
#   else is printed and the exit status is 1.
#
# Color codes (https://en.wikipedia.org/wiki/ANSI_escape_code):
#   * COLOR_DEFAULT: (34) blue
#   * COLOR_ATTENTION: (31) red
#   * COLOR_DEPRECATED: (33) yellow
#   * COLOR_SECTION: (32) green
#   * COLOR_BACKTICKS: (0) disabled -- used for text in backticks in docs
#
#   Colors are specified using the parameter in ANSI escape codes, e.g., the parameter
#   for blue is the 34 in `\033[34m`. The supported parameters are: 0, 1, 3, 4, 9,
#   30-37, 40-47, 90-97, 100-107 (see array ANSI_TO_HTML_COLOR).
#
#   + EXPORT_THEME: user-defined mapping between ANSI color parameters and HEX color
#     codes (without the hash tag). For example -v EXPORT_THEME=32:d33682,35:859900
#     would change the way the ANSI colors corresponding to the parameters 32 and 35 are
#     exported to HTML and LATEX (in effect, exchanging their default values in this
#     example). This can be used to define a custom theme for HTML and LATEX output (it
#     has no effect on ANSI output).
#
# SUB:
#   Contains substitutions for targets and variables. For example, consider a variable
#   named AWK whose possible values are contained in a variable SUPPORTED_AWK_VARIANTS,
#   then passing -v SUB='AWK:$(SUPPORTED_AWK_VARIANTS)' would add the values of
#   SUPPORTED_AWK_VARIANTS to the documentation of the variable AWK. This mechanism is
#   also useful when documenting targets defined in terms of variables/expressions,
#   which we might want to rename. The format of a single substitution is
#   [<p1:v1,...>]NAME[:LABEL]:[VALUES]
#   + NAME is the name of the variable/target to substitute in the documentation
#   + LABEL is an optional label for renaming the variable/target
#   + VALUES are optional space-separated values to include
#   + <p1:v1,...> are optional, comma-separated, key-value pairs with parameters (a comma
#     can appear as a part of a parameter value if it is escaped, i.e., \\,)
#   + multiple ;-separated substitutions can be passed
#
# SUB parameters:
#   Each substitution can include parameters <p1:v1,...>:
#   + L:0/L:1 values are displayed starting from the current/next line
#   + M:0/M:1 single/multi-line display
#   + N       max number of values to display (-1, the default, means no limit)
#   + S       value-separator
#   + P       prefix (added to each value)
#   + I       initial string, e.g., {
#   + T       termination string, e.g., }
#
# DSUB:
#  Similar to SUB but performs substitutions in the original descriptions. The expected
#  format is NAME:VALUES. For example, using -v DSUB='$$(DEPS):$(DEPS)', the target
#
#  DEPS := x y
#  ## Prerequisites: $(DEPS)
#  t: $(DEPS)
#
#  would be documented as: t   Prerequisites: x y
#
#  Values containing newline characters are not supported.
#
#  The substitutions are applied in the order given. If a name appears more than once,
#  the last value is used.
#
# Code conventions:
#   * All local variables in functions should be defined in the function signature (awk
#     is a bit special in that respect).
#   + The naming convention for global variables is:
#     + long-standing/important global variables are written in all upper case
#     + temporary variables that end-up being global (simply because of where they are
#       defined, e.g., in the END stanza) have a prefix g_.
#   * The code is meant to run with most major awk implementations, and as a result we
#     need to stick to basic syntax. For example, we cannot use a match function with
#     a third argument (an array that stores the groups) and have to fall-back to using
#     RSTART and RLENGTH. We cannot use arrays of arrays (as in gnu awk). We cannot use
#     %* patterns, some regex features etc.
#   + Notes on the arrays in the code:
#     Order is important only to the arrays DESCRIPTION_DATA, SECTION_DATA, TARGETS,
#     VARIABLES and each of them has an associated *_INDEX integer variable.
#
# Terminology and definitions:
#   + A Makefile rule (without patterns) can take one of the following forms:
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
#   + Recipe: a sequence of commands executed in the shell. A recipe (and thus a rule)
#     ends at the next target line, variable assignment, define ... endef
#   + Target: an abstraction representing a task/goal to achieve which is defined in
#     terms of, potentially, many rules.
#     + Normal (single-colon) targets can have only one recipe and to mirror this we
#       allow for them to have only one description.
#     + double-colon targets (i.e., targets defined by double-colon rules) can have
#       multiple descriptions (as they can have multiple recipes).
#   + Target line: the top-line (the header) of a Makefile rule
#   + Target name: a (string) label for a target
#   + Description of a rule: comments starting with ##, ##! or ##% placed above the
#     target line of a rule or inline. Inline descriptions placed after an inline recipe
#     are ignored.
#   + The last rule with a description defines the description of a normal target, while
#     every double-colon rule with a description defines a new description.

function max(x, y) {
  return (x >= y) ? x : y
}

function min(x, y) {
  return (x <= y) ? x : y
}

# 1. An empty string means a space.
# 2. I used to have a gsub-based version, but it needs tricks to handle
#    special characters like &, \ (and 0, because of `if (string)`).
# 3. For the strings we manipulate here, the drop in speed is negligible.
# 4. n must be a non-negative integer (a non-numeric n loops forever);
#    OFFSET is validated in BEGIN.
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

# in POSIX-compliant AWK the length function works on strings but not on arrays
function length_array_posix(array, #locals
                            key, n) {
  n = 0
  for (key in array) {
    n++
  }
  return n
}

function is_double_colon_rule(line, #locals
                              pos) {
  pos = index(line, ":")
  return pos && substr(line, pos + 1, 1) == ":"
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

function form_dc_target_name(target_name_nominal) {
  if (!(target_name_nominal in TARGETS_DC_COUNTER)) {
    TARGETS_DC_COUNTER[target_name_nominal] = 1
  }

  return sprintf("%s%s%s",
                 target_name_nominal,
                 DOUBLE_COLON_SEPARATOR,
                 TARGETS_DC_COUNTER[target_name_nominal])
}

# join the elements of an array produced by split()
function join(array, delimiter, #locals
                       string, k, n_elements) {
  string = ""
  n_elements = length_array_posix(array)
  for (k=1; k<=n_elements; k++) {
    if (k == 1) {
      string = array[k]
    } else {
      string = string delimiter array[k]
    }
  }
  return string
}

# string replacement without regex
function string_replace(string, replacement, text, #locals
                        k, pre) {
  k = index(text, string)
  if (string && k > 0) {
    pre = substr(text, 1, k-1)
    return pre replacement string_replace(string,
                                          replacement,
                                          substr(text, k+length(string)))
  }
  return text
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
  last = substr(text, length(text), 1)
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

function get_tag_from_description(string, #locals
                                  tag) {
  if (match(string, /^ *(##!|##%|##)/)) {
    tag = substr(string, RSTART, RLENGTH)
    sub(/ */, "", tag)
    return tag
  }

  return 0 # if we end-up here it probably means that we are using a wrong regex
}

function save_description_data(string) {
  DESCRIPTION_DATA[DESCRIPTION_DATA_INDEX++] = string
}

function forget_descriptions_data() {
  delete DESCRIPTION_DATA
  DESCRIPTION_DATA_INDEX = 1
}

# Save the inline doc of a target or variable line. On a target line, a ## after a ; is part
# of an inline recipe (not a doc); in a variable assignment, a ; is part of the value. An
# inline ##@ is not a doc either (a section is written on its own lines).
function parse_inline_descriptions(whole_line, is_variable, #locals
                                   inline_description) {
  if ((is_variable || !match(whole_line, /^[^#]*;/)) &&
      match(whole_line, / *(##!|##%|##)/)) {
    inline_description = substr(whole_line, RSTART)
    sub(/^ */, "", inline_description)
    if (inline_description !~ /^##@/) {
      save_description_data(inline_description)
    }
  }
}

# True for a line of a special target, e.g., `.PHONY: t` or `.ONESHELL:` (a dot followed by
# upper-case letters). These lines are skipped and the docs above them are kept.
function detect_ignored_targets(target_line) {
  return target_line ~ /^[ \t]*\.[A-Z_]+[ \t]*:/
}

# Return 1 if text has an unclosed variable reference or function call, e.g., `$(info a`
# (the part before the first colon of `$(info a: b)`)
function has_unclosed_reference(text, #locals
                                opened, closed) {
  opened = gsub(/[(]/, "(", text)
  closed = gsub(/[)]/, ")", text)
  if (opened > closed) {
    return 1
  }
  opened = gsub(/[{]/, "{", text)
  closed = gsub(/[}]/, "}", text)
  return opened > closed
}

function initialize_variables_regex() {
  ASSIGNMENT_OPERATORS_PATTERN = "(=|:=|::=|:::=|!=|\\?=|\\+=)"
  split("override unexport export private", VARIABLE_QUALIFIERS, " ")

  # Variable matching is heuristic; this is not a complete GNU Make parser.
  #
  # Known limitations:
  #  - Variable/function references in variable names are captured literally
  #    rather than expanded, e.g., `$(PREFIX)_FLAGS := ...`.
  VARIABLES_REGEX_DEFAULT = sprintf("^[ \t]*([ \t]*(%s)[ \t]+)*[^ \t#:=]+[ \t]*%s",
                                    join(VARIABLE_QUALIFIERS, "|"),
                                    ASSIGNMENT_OPERATORS_PATTERN)
}

# return `FOO`, given `override private export FOO := 1`
# return `export`, given `override private export := 1` even though `export` is a qualifier
function parse_variable_name(whole_line, #locals
                             whole_line_split, variable_name, qualifiers_pattern) {
  split(whole_line, whole_line_split, ASSIGNMENT_OPERATORS_PATTERN)
  variable_name = strip_start_end_spaces_tabs(whole_line_split[1])

  qualifiers_pattern = "(" join(VARIABLE_QUALIFIERS, "|") ")"

  while (match(variable_name, "^" qualifiers_pattern "[ \t]+[^ \t]")) {
    sub("^" qualifiers_pattern "[ \t]+", "", variable_name)
  }

  return strip_start_end_spaces_tabs(variable_name)
}

function associate_data_with_anchor(anchor_name,
                                    anchors,
                                    anchors_index,
                                    anchors_description_data,
                                    anchors_section_data,
                                    anchor_type) {
  if (anchor_name in anchors_description_data) {
    if (!(anchor_type == "variable" && !VARS)) {
      printf("WARNING: [%s:%s] redefined docs of %s: %s\n",
             FILENAME,
             FNR,
             anchor_type,
             anchor_name) > STDERR
    }
  } else {
    anchors[anchors_index] = anchor_name
    anchors_index++
  }

  anchors_description_data[anchor_name] = assemble_description_section_data(DESCRIPTION_DATA)
  forget_descriptions_data()

  # note that section data is associated only with documented anchors
  if (length_array_posix(SECTION_DATA) > 0) {
    if (anchor_name in anchors_section_data) {
      printf("WARNING: [%s:%s] redefined associated section data: %s\n",
             FILENAME,
             FNR,
             anchor_name) > STDERR
    }

    anchors_section_data[anchor_name] = assemble_description_section_data(SECTION_DATA)
    forget_section_data()
  }

  return anchors_index
}

function save_section_data(string) {
  SECTION_DATA[SECTION_DATA_INDEX++] = string
}

function forget_section_data() {
  delete SECTION_DATA
  SECTION_DATA_INDEX = 1
}

function get_associated_section_data(anchor_name,
                                     anchor_section_data) {
  if (anchor_name in anchor_section_data) {
    return colorize_description_backticks(\
        apply_output_specific_formatting(anchor_section_data[anchor_name]))
  }
  return 0 # means that there is no section data associated with this anchor
}

# true for an anchor documented with ##% when deprecated anchors are not displayed
function is_hidden_anchor(anchor, anchors_description_data) {
  return !DEPRECATED && get_tag_from_description(anchors_description_data[anchor]) == "##%"
}

# the length of the longest displayed anchor (0 if no anchor is displayed)
function get_max_anchor_length(anchors, anchors_description_data, #locals
                               max_len, key, anchor, n) {
  max_len = 0
  for (key in anchors) { # order is not important
    anchor = anchors[key]
    if (is_hidden_anchor(anchor, anchors_description_data)) {
      continue
    }
    n = (anchor in SUB_LABELS) ? length(SUB_LABELS[anchor]) : length(anchor)
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

function substitute_backticks_patterns(string, #locals
                                       before_match, inside_match, after_match) {
  # (gensub with a back-reference would do this in one call, but it is only in gawk)
  while (match(string, /`([^`]+)`/)) {
    before_match = substr(string, 1, RSTART - 1)
    inside_match = substr(string, RSTART + 1, RLENGTH - 2)
    after_match = substr(string, RSTART + RLENGTH)

    string = before_match COLOR_BACKTICKS_CODE inside_match COLOR_RESET_CODE after_match
  }
  return string
}

function colorize_description_backticks(description) {
  if (COLOR_BACKTICKS) {
    return substitute_backticks_patterns(description)
  }
  return description
}

# The input contains the (\n separated) description lines associated with one anchor.
# Each line starts with a tag (##, ##! or ##%). Here we have to strip them and to
# introduce indentation for lines below the first one.
function format_description_data(anchor_name,
                                 anchors_description_data,
                                 len_anchor_names,
                                 #locals
                                 k, array_of_lines, line, description, n_elements) {
  # the automatically-assigned indexes during the split are: 1, ..., #lines
  split(anchors_description_data[anchor_name], array_of_lines, "\n")

  # the tag for the first line is stripped below (after the parameter update)
  description = repeated_string("", OFFSET) array_of_lines[1]

  n_elements = length_array_posix(array_of_lines)
  for (k=2; k<=n_elements; k++) {
    line = array_of_lines[k]
    sub(/^(##|##!|##%)/, "", line) # strip the tag
    description = sprintf("%s\n%s%s",
                          description,
                          repeated_string("", OFFSET + len_anchor_names),
                          line)
  }

  update_display_parameters(description)
  # The order of alternatives is important when using goawk v1.29.1 and below.
  # Starting from goawk v1.30.0 this problem has been fixed.
  sub(/(##!|##%|##)/, "", description) # strip the tag (keep the leading space)

  # apply the substitutions in the order given
  for (k = 1; k <= DSUB_COUNT; k++) {
    description = string_replace(DSUB_NAMES[k], DSUB_VALUES[DSUB_NAMES[k]], description)
  }

  return colorize_description_backticks(apply_output_specific_formatting(description))
}

function assemble_description_section_data(array, #locals
                                           docs, k, n_elements) {
  docs = array[1]
  n_elements = length_array_posix(array)
  for (k=2; k<=n_elements; k++) {
    docs = docs "\n" array[k]
  }
  return docs
}

function update_display_parameters(description, #locals
                                   tag) {
  tag = get_tag_from_description(description)
  if (tag == "##!") {
    DISPLAY_PARAMS["color"] = COLOR_ATTENTION_CODE
    DISPLAY_PARAMS["show"] = 1
  } else if (tag == "##%") {
    DISPLAY_PARAMS["color"] = COLOR_DEPRECATED_CODE
    DISPLAY_PARAMS["show"] = DEPRECATED
  } else if (tag == "##") {
    DISPLAY_PARAMS["color"] = COLOR_DEFAULT_CODE
    DISPLAY_PARAMS["show"] = 1
  } else {
    fatal(sprintf("ERROR (we shouldn't be here): %s", description))
  }
}

# Split the parameters of a substitution, "k1:v1,k2:v2,...", into params[key] = value and
# keys[1..n] (the keys in the order given); return n. In a pair, only the first colon is a
# separator, and a comma in a value is written \,
function parse_substitution_params(string, params, keys, #locals
                                   temp_placeholder, k, n, n_pairs, key_values, pair, key) {
  split("", params)
  split("", keys)
  temp_placeholder = "\034" # the “file separator” ASCII control character

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
    key = pair[1]
    gsub(SPACES_TABS_REGEX, "", key)
    params[key] = substr(key_values[k], length(pair[1]) + 2) # after the first colon
    keys[++n] = key
  }
  return n
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

# Report the invalid parameters of the substitution of name (see option_error)
function validate_substitution_params(name, string_with_parameters, #locals
                                      params, keys, k, n, key, value) {
  n = parse_substitution_params(string_with_parameters, params, keys)
  for (k = 1; k <= n; k++) {
    key = keys[k]
    value = strip_start_end_spaces_tabs(params[key])
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

# SUB:  NAME:VALUES or NAME:LABEL:VALUES (the first two colons are separators)
# DSUB: NAME:VALUES (only the first colon is a separator, no_labels is set)
# Everything after the last separator is the value, so it can contain colons.
#
# Caveat: for SUB, NAME:A:B is always read as NAME:LABEL:VALUES, so A is the label.
# To give a value that contains a colon without renaming, repeat the name as the label:
# t:t:/a:b gives the value /a:b, while t:/a:b gives the label /a and the value b.
#
# Empty items (e.g., after a trailing ;) are skipped. Invalid items are reported (see
# option_error) and skipped: no colon, an empty name, an empty label, invalid parameters.
function form_substitutions(sub_array, sub_params_array, sub_labels_array,
                            sub_values_array, sub_names_array, no_labels, #locals
                            split_substitutions, k, n, string, substitution_params,
                            substitution_rest, name, label, values, colon,
                            has_label, n_substitutions, option) {
  delete sub_params_array
  delete sub_labels_array
  delete sub_values_array
  delete sub_names_array # names in the order they are given

  option = no_labels ? "DSUB" : "SUB"
  n = 0
  n_substitutions = split(sub_array, split_substitutions, ";")
  for (k=1; k<=n_substitutions; k++) {
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
                           no_labels ? "NAME:VALUES" : "NAME[:LABEL]:[VALUES]"))
      continue
    }
    name = substr(substitution_rest, 1, colon - 1)
    values = substr(substitution_rest, colon + 1)
    has_label = 0
    colon = no_labels ? 0 : index(values, ":")
    if (colon > 0) {
      label = substr(values, 1, colon - 1)
      values = substr(values, colon + 1)
      has_label = 1
    }
    gsub(SPACES_TABS_REGEX, "", name)

    if (name == "") {
      option_error(sprintf("%s: '%s' has an empty NAME", option, string))
      continue
    }
    if (has_label && label == "") {
      option_error(sprintf("%s: '%s' has an empty LABEL", option, string))
      continue
    }
    if (!no_labels) {
      validate_substitution_params(name, substitution_params)
    }

    sub_names_array[++n] = name
    sub_params_array[name] = substitution_params
    sub_values_array[name] = values
    if (has_label) {
      sub_labels_array[name] = label
    }
  }
}

function initialize_substitution_parameter_defaults() {
  # don't change the defaults
  SUB_PARAMS_DEFAULTS["L"] = 1 # 0: start display on current line, 1: start display on next line
  SUB_PARAMS_DEFAULTS["M"] = 1 # 1: multi-line display, 0: single-line display
  SUB_PARAMS_DEFAULTS["N"] = -1 # max number of elements to display (-1 means no limit)
  SUB_PARAMS_DEFAULTS["S"] = "" # separator
  SUB_PARAMS_DEFAULTS["P"] = "" # prefix
  SUB_PARAMS_DEFAULTS["I"] = "" # initial string, e.g., (
  SUB_PARAMS_DEFAULTS["T"] = "" # termination string, e.g., , ...)
}

# return the text that displays the values of a substitution
function display_substitutions(anchor, len_anchors, #locals
                               k, n, L, M, I, value_parts,
                               cond_indent, indentation, text, output) {
  output = ""
  split(SUB_VALUES[anchor], value_parts, " ")

  if (SUB_PARAMS_CURRENT["N"] < 0) {
    n = length_array_posix(value_parts)
  } else {
    n = min(SUB_PARAMS_CURRENT["N"], length_array_posix(value_parts))
  }

  for (k=1; k<=n; k++) {
    L = SUB_PARAMS_CURRENT["L"]
    M = SUB_PARAMS_CURRENT["M"]
    I = SUB_PARAMS_CURRENT["I"]

    # -----------------------------
    # NO INDENT: !M && !L
    #    INDENT: !M &&  L && k == 1
    # NO INDENT: !M &&  L && k  > 1
    # NO INDENT:  M && !L && k == 1
    #    INDENT:  M && !L && k  > 1
    #    INDENT:  M &&  L
    # -----------------------------
    # the + 1 is because of the usual one space we add between the token ## and the docs
    indentation = len_anchors + OFFSET + 1  + (M && k > 1 ? length(I) : 0)
    cond_indent = (!M && L && k == 1) || (M && !L && k > 1) || (M && L)
    text = sprintf(repeated_string("%s", 7),
                   repeated_string("", cond_indent ? indentation : 1),
                   k == 1 ? I : "",
                   SUB_PARAMS_CURRENT["P"],
                   value_parts[k],
                   k == n ? "" : SUB_PARAMS_CURRENT["S"],
                   k == n ? SUB_PARAMS_CURRENT["T"] : "",
                   M || (!M && k == n) ? "\n" : "")
    output = output colorize_description_backticks(apply_output_specific_formatting(text))
  }

  if (!SUB_PARAMS_CURRENT["L"] && n == 0) {
    output = output "\n"
  }
  return output
}

function display_anchor_with_data(anchor, description, section, len_anchors, #locals
                                  renamed_anchor, formatted_anchor, padding, output) {
  extract_substitution_params(SUB_PARAMS[anchor])

  # Display the section (if there is one) even if it is anchored to a deprecated anchor
  # that is not to be displayed (unless no anchor of its kind is displayed: then this
  # function is not called for it).
  if (section) {
    if (COLOR_SECTION_CODE) {
      # In ANSI output a reset (e.g., after a backtick region) turns off all colors, so
      # the section color has to be restored after each reset.
      if (OUTPUT_FORMAT == "ANSI") {
        section = string_replace(COLOR_RESET_CODE,
                                 COLOR_RESET_CODE COLOR_SECTION_CODE,
                                 section)
      }
      printf("%s%s%s\n", COLOR_SECTION_CODE, section, COLOR_RESET_CODE)
    } else {
      printf("%s\n", section)
    }
  }

  if (DISPLAY_PARAMS["show"]) {
    renamed_anchor = (anchor in SUB_LABELS) ? SUB_LABELS[anchor] : anchor
    formatted_anchor = apply_output_specific_formatting(renamed_anchor)

    # handle padding manually because there is a difference between the actual text and
    # the visible text (for latex)
    padding = repeated_string("", len_anchors - length(renamed_anchor))
    if (PADDING != " ") {
      padding = string_replace(" ", PADDING, padding)
    }
    if (DISPLAY_PARAMS["color"]) {
      formatted_anchor = sprintf("%s%s%s%s",
                                 DISPLAY_PARAMS["color"],
                                 formatted_anchor,
                                 padding,
                                 COLOR_RESET_CODE)
    } else {
      formatted_anchor = sprintf("%s%s", formatted_anchor, padding)
    }

    output = sprintf("%s%s%s%s",
                     formatted_anchor,
                     description,
                     SUB_PARAMS_CURRENT["L"] ? "\n" : "",
                     display_substitutions(anchor, len_anchors))
    printf("%s", strip_trailing_blanks(output))
  }
}

# formatting functions to be applied just before colors have been added
function apply_output_specific_formatting(text) {
  return escape_for_latex_output(escape_for_html_output(text))
}

# The user can change the colors of the parameters 30-37, 40-47, 90-97 and 100-107 and set
# FG and BG. Format: ANSI_PARAM:HEX_COLOR[,...] (invalid entries are reported, see
# option_error).
function set_user_defined_color_theme(                                  \
    html_colors_split, k, n, ansi_html_map, ansi_param, html_color_code) {
  n = split(EXPORT_THEME, html_colors_split, ",")
  for (k = 1; k <= n; k++) {
    if (html_colors_split[k] ~ /^[ \t]*$/) {
      continue # an empty entry, e.g., after a trailing comma
    }
    split(html_colors_split[k], ansi_html_map, ":")
    ansi_param = ansi_html_map[1]
    html_color_code = ansi_html_map[2]
    # the parameters in the range 0-9 are attributes (e.g., bold): they have no color
    if (ansi_param != "FG" && ansi_param != "BG" &&
        !(ansi_param ~ /^[0-9]+$/ && ansi_param > 9 && ansi_param in ANSI_TO_HTML_COLOR)) {
      option_error(sprintf("EXPORT_THEME: '%s' should start with FG, BG or one of %s",
                           html_colors_split[k], "30-37, 40-47, 90-97, 100-107"))
    } else if (!is_hex_color(html_color_code)) {
      option_error(sprintf("EXPORT_THEME: '%s' should end with a color of 6 hex digits",
                           html_colors_split[k]))
    } else {
      ANSI_TO_HTML_COLOR[ansi_param] = html_color_code
    }
  }
}

# The solarized theme is used by default
# https://github.com/altercation/solarized?tab=readme-ov-file#the-values
function define_ansi_to_html_colors(            \
    k) {
  # no foreground/background by default
  ANSI_TO_HTML_COLOR["BG"] = -1
  ANSI_TO_HTML_COLOR["FG"] = -1

  ANSI_TO_HTML_COLOR[0] = ""
  ANSI_TO_HTML_COLOR[1] = "bold"
  ANSI_TO_HTML_COLOR[3] = "italic"
  ANSI_TO_HTML_COLOR[4] = "underline"
  ANSI_TO_HTML_COLOR[9] = "line-through"

  ANSI_TO_HTML_COLOR[30] = "073642" # black
  ANSI_TO_HTML_COLOR[31] = "dc322f" # red
  ANSI_TO_HTML_COLOR[32] = "859900" # green
  ANSI_TO_HTML_COLOR[33] = "b58900" # yellow
  ANSI_TO_HTML_COLOR[34] = "268bd2" # blue
  ANSI_TO_HTML_COLOR[35] = "d33682" # magenta
  ANSI_TO_HTML_COLOR[36] = "2aa198" # cyan
  ANSI_TO_HTML_COLOR[37] = "eee8d5" # white

  ANSI_TO_HTML_COLOR[90] = "002b36" # brblack
  ANSI_TO_HTML_COLOR[91] = "cb4b16" # brred
  ANSI_TO_HTML_COLOR[92] = "586e75" # brgreen
  ANSI_TO_HTML_COLOR[93] = "657b83" # bryellow
  ANSI_TO_HTML_COLOR[94] = "839496" # brblue
  ANSI_TO_HTML_COLOR[95] = "6c71c4" # brmagenta
  ANSI_TO_HTML_COLOR[96] = "93a1a1" # brcyan
  ANSI_TO_HTML_COLOR[97] = "fdf6e3" # brwhite

  for (k=30; k<=37; k++) { ANSI_TO_HTML_COLOR[k+10] = ANSI_TO_HTML_COLOR[k] }
  for (k=90; k<=97; k++) { ANSI_TO_HTML_COLOR[k+10] = ANSI_TO_HTML_COLOR[k] }

  set_user_defined_color_theme()
}

function define_ansi_to_html_attributes(        \
    k) {
  ANSI_TO_HTML_ATTR[0] = ""
  ANSI_TO_HTML_ATTR[1] = "font-weight"
  ANSI_TO_HTML_ATTR[3] = "font-style"
  ANSI_TO_HTML_ATTR[4] = "text-decoration"
  ANSI_TO_HTML_ATTR[9] = "text-decoration"

  for (k=30; k<=37; k++) { ANSI_TO_HTML_ATTR[k] = "color" }
  for (k=40; k<=47; k++) { ANSI_TO_HTML_ATTR[k] = "background-color" }
  for (k=90; k<=97; k++) { ANSI_TO_HTML_ATTR[k] = "color" }
  for (k=100; k<=107; k++) { ANSI_TO_HTML_ATTR[k] = "background-color" }
}

function define_ansi_to_latex_function(         \
    k) {
  ANSI_TO_LATEX_FUN[0] = ""
  ANSI_TO_LATEX_FUN[1] = "\\textbf"
  ANSI_TO_LATEX_FUN[3] = "\\emph"
  ANSI_TO_LATEX_FUN[4] = "\\uline"
  ANSI_TO_LATEX_FUN[9] = "\\sout"

  for (k=30; k<=37; k++) { ANSI_TO_LATEX_FUN[k] = "\\textcolor" }
  for (k=40; k<=47; k++) { ANSI_TO_LATEX_FUN[k] = "\\bgcolor" }
  for (k=90; k<=97; k++) { ANSI_TO_LATEX_FUN[k] = "\\textcolor" }
  for (k=100; k<=107; k++) { ANSI_TO_LATEX_FUN[k] = "\\bgcolor" }
}

function define_color_labels() {
  COLOR_LABELS["DEFAULT"] = "color-default"
  COLOR_LABELS["ATTENTION"] = "color-attention"
  COLOR_LABELS["DEPRECATED"] = "color-deprecated"
  COLOR_LABELS["SECTION"] = "color-section"
  COLOR_LABELS["BACKTICKS"] = "color-backticks"
  COLOR_LABELS["FG"] = "makefile-doc-fg"
  COLOR_LABELS["BG"] = "makefile-doc-bg"
}

# the class of the HTML elements with the color of label (e.g., makefile-doc-default)
function html_class(label) {
  return "makefile-doc-" tolower(label)
}

# Return the CSS rule (one line) for a color option, or "" if there is nothing to style.
# Here ansi_color_param is a normal ANSI color param, e.g., 30-37, but it could as well be
# "FG" or "BG": these style the whole output (the element with the class makefile-doc).
function ansi_color_param_to_html_style(ansi_color_param, label, #locals
                                        attr) {
  if (ansi_color_param == "FG" || ansi_color_param == "BG") {
    if (ANSI_TO_HTML_COLOR[ansi_color_param] == -1) {
      return ""
    }
    return sprintf("  .makefile-doc { %s: #%s; }\n",
                   ansi_color_param == "FG" ? "color" : "background-color",
                   ANSI_TO_HTML_COLOR[ansi_color_param])
  }

  if (ansi_color_param && ansi_color_param in ANSI_TO_HTML_COLOR) {
    attr = ANSI_TO_HTML_ATTR[ansi_color_param]
    return sprintf("  .%s { %s: %s%s; }\n",
                   html_class(label),
                   attr,
                   (attr == "color" || attr == "background-color")? "#" : "",
                   ANSI_TO_HTML_COLOR[ansi_color_param])
  }

  return ""
}

function ansi_color_param_to_latex_color(ansi_color_param, is_fgbg_definition) {
  if (ansi_color_param == "FG" || ansi_color_param == "BG") {
    if (ANSI_TO_HTML_COLOR[ansi_color_param] == -1) {
      return "" # indicates to not set any style
    }
    if (is_fgbg_definition) {
      return sprintf("\\definecolor{%s}{HTML}{%s}\n",
                     COLOR_LABELS[ansi_color_param],
                     ANSI_TO_HTML_COLOR[ansi_color_param])
    } else {
      if (ansi_color_param == "FG") {
        return sprintf("\\color{%s}\n", COLOR_LABELS["FG"])
      } else if (ansi_color_param == "BG") {
        return sprintf("\\pagecolor{%s}\n", COLOR_LABELS["BG"])
      }
    }
  }

  if (ansi_color_param &&
      ansi_color_param in ANSI_TO_HTML_COLOR &&
      ansi_color_param > 9) {
    return ANSI_TO_HTML_COLOR[ansi_color_param]
  }
  return "000000"
}

function latex_definecolor(label, ansi_color_param) {
  return sprintf("\\definecolor{%s}{HTML}{%s}\n",
                 COLOR_LABELS[label],
                 ansi_color_param_to_latex_color(ansi_color_param))
}

# the preamble of the LaTeX output, up to the start of the documentation
function latex_header(                          \
    header) {
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
  header = header ansi_color_param_to_latex_color("FG", 1)
  header = header ansi_color_param_to_latex_color("BG", 1)
  header = header latex_definecolor("ATTENTION", COLOR_ATTENTION)
  header = header latex_definecolor("SECTION", COLOR_SECTION)
  header = header latex_definecolor("DEPRECATED", COLOR_DEPRECATED)
  header = header latex_definecolor("DEFAULT", COLOR_DEFAULT)
  header = header latex_definecolor("BACKTICKS", COLOR_BACKTICKS)
  header = header "\n"
  header = header "\\pagestyle{empty}\n"
  header = header "\\begin{document}\n"
  header = header "\n"
  header = header "\\begin{varwidth}{\\linewidth}\n"
  header = header ansi_color_param_to_latex_color("FG")
  header = header ansi_color_param_to_latex_color("BG")
  header = header "\n"
  header = header "\\begin{alltt}"
  return header
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
      return "<span class=\"" html_class(color_label_key) "\">"
    }
  } else if (OUTPUT_FORMAT == "LATEX") {
    if (ansi_color_param == -1) {
      return "}"
    } else {
      if (ansi_color_param > 9) {
        return ANSI_TO_LATEX_FUN[ansi_color_param] "{" COLOR_LABELS[color_label_key] "}{"
      } else {
        return ANSI_TO_LATEX_FUN[ansi_color_param] "{"
      }
    }
  }
}

# Return the ANSI color parameter given for a COLOR_* option (0 means no color). An
# unsupported value is reported (see option_error).
function validate_ansi_param(option, ansi_param) {
  if (ansi_param ~ /^[0-9]+$/ && ansi_param in ANSI_TO_HTML_COLOR) {
    # The explicit cast to int here is needed only because of a busybox awk bug
    # see misc/busybox_awk_bug_20251107.awk
    return int(ansi_param)
  }
  option_error(sprintf("%s should be one of 0, 1, 3, 4, 9, 30-37, 40-47, 90-97, 100-107",
                       option))
  return 0
}

# the default of the COLOR option: 0 if NO_COLOR is set to a non-empty value (no-color.org)
function default_color_option() {
  return ("NO_COLOR" in ENVIRON && ENVIRON["NO_COLOR"] != "") ? 0 : 1
}

function initialize_colors() {
  COLOR = COLOR == "" ? default_color_option() : COLOR
  if (!is_bool(COLOR)) {
    option_error("COLOR should be 0 or 1")
    COLOR = 1
  }

  define_ansi_to_html_colors()
  define_ansi_to_html_attributes()
  define_ansi_to_latex_function()
  define_color_labels()

  COLOR_DEFAULT = validate_ansi_param("COLOR_DEFAULT",
                                      COLOR_DEFAULT == "" ? 34 : COLOR_DEFAULT)
  COLOR_ATTENTION = validate_ansi_param("COLOR_ATTENTION",
                                        COLOR_ATTENTION == "" ? 31 : COLOR_ATTENTION)
  COLOR_DEPRECATED = validate_ansi_param("COLOR_DEPRECATED",
                                         COLOR_DEPRECATED == "" ? 33 : COLOR_DEPRECATED)
  COLOR_SECTION = validate_ansi_param("COLOR_SECTION",
                                      COLOR_SECTION == "" ? 32 : COLOR_SECTION)
  COLOR_BACKTICKS = validate_ansi_param("COLOR_BACKTICKS",
                                        COLOR_BACKTICKS == "" ? 0 : COLOR_BACKTICKS)
  if (!COLOR) {
    COLOR_DEFAULT = COLOR_ATTENTION = COLOR_DEPRECATED = COLOR_SECTION = COLOR_BACKTICKS = 0
  }

  COLOR_DEFAULT_CODE = define_color(COLOR_DEFAULT, "DEFAULT")
  COLOR_ATTENTION_CODE = define_color(COLOR_ATTENTION, "ATTENTION")
  COLOR_DEPRECATED_CODE = define_color(COLOR_DEPRECATED, "DEPRECATED")
  COLOR_SECTION_CODE = define_color(COLOR_SECTION, "SECTION")
  COLOR_BACKTICKS_CODE = define_color(COLOR_BACKTICKS, "BACKTICKS")
  COLOR_RESET_CODE = define_color(-1)

  if (OUTPUT_FORMAT == "HTML") {
    HTML_FOOTER = "</pre>\n</div>"
    # an HTML fragment (to paste into a page): the styles, then the documentation
    HTML_HEADER = "<style>\n" \
        ansi_color_param_to_html_style(COLOR_ATTENTION, "ATTENTION") \
        ansi_color_param_to_html_style(COLOR_SECTION, "SECTION") \
        ansi_color_param_to_html_style(COLOR_DEPRECATED, "DEPRECATED") \
        ansi_color_param_to_html_style(COLOR_DEFAULT, "DEFAULT") \
        ansi_color_param_to_html_style(COLOR_BACKTICKS, "BACKTICKS") \
        ansi_color_param_to_html_style("FG", "FG") \
        ansi_color_param_to_html_style("BG", "BG") \
        "</style>\n<div class=\"makefile-doc\">\n<pre>"
  } else if (OUTPUT_FORMAT == "LATEX") {
    LATEX_FOOTER = "\\end{alltt}\n\\end{varwidth}\n\\end{document}"
    LATEX_HEADER = latex_header()
  }
}

# It would be nice to extract the options from the docstring of this script (there could
# be some sort of prefix before each option). Unfortunately, I can get the script passed
# with the -f flag only using gawk (so, names of options are hard-coded in print_help):
# for (key in PROCINFO["argv"]) {
#   if (PROCINFO["argv"][key] == "-f") {
#     printf PROCINFO["argv"][key + 1]
#   }
# }
function print_help() {
  print "Usage: awk [-v option=value] -f makefile-doc.awk [Makefile ...]"
  print "Description: Generate docs for Makefile variables and targets"
  print "Version: " VERSION
  print "Options:"
  printf "  OUTPUT_FORMAT: %s\n", OUTPUT_FORMAT
  printf "  EXPORT_THEME (theme for HTML/LATEX output):%s\n",
         (EXPORT_THEME == "" ? "" : " " EXPORT_THEME)
  printf "  SUB (substitutions):%s\n", (SUB == "" ? "" : " " SUB)
  printf "  DSUB (substitutions in docs):%s\n", (DSUB == "" ? "" : " " DSUB)
  printf "  TARGETS_REGEX (regex for matching targets): %s\n", TARGETS_REGEX
  printf "  VARIABLES_REGEX (regex for matching variables): %s\n", VARIABLES_REGEX
  printf "  VARS ([bool] show documented variables): %s\n", VARS
  printf "  PADDING (a padding character between anchors and docs): \"%s\"\n", PADDING
  printf "  DEPRECATED ([bool] show deprecated anchors): %s\n", DEPRECATED
  printf "  OFFSET (offset of docs from anchors): %s\n", OFFSET
  printf "  COLOR ([bool] use colors): %s\n", COLOR
  printf "  RECIPEPREFIX: |%s|\n", RECIPEPREFIX
  printf "  COLOR_: "
  printf "%sDEFAULT%s, ", COLOR_DEFAULT_CODE, COLOR_RESET_CODE
  printf "%sATTENTION%s, ", COLOR_ATTENTION_CODE, COLOR_RESET_CODE
  printf "%sDEPRECATED%s, ", COLOR_DEPRECATED_CODE, COLOR_RESET_CODE
  printf "%sSECTION%s, ", COLOR_SECTION_CODE, COLOR_RESET_CODE
  printf "%sBACKTICKS%s\n", COLOR_BACKTICKS_CODE, COLOR_RESET_CODE
}

# Set the global state that does not depend on user options. It is called from BEGIN and
# can be called from unit tests (also to reset the state between tests).
function init_globals() {
  VERSION = "v1.8" # the only place where the version is defined

  # can be overridden with -v STDERR=file (used by the unit tests)
  STDERR = STDERR == "" ? "/dev/stderr" : STDERR
  ABORT = 0 # set to the exit status when BEGIN fails (END must not print anything)
  FATAL_MSG = "" # in unit-test mode, the message of the last call to fatal()
  OPTION_ERRORS = 0 # number of invalid options (see option_error)

  initialize_variables_regex()
  initialize_substitution_parameter_defaults()

  # initialize global arrays (i.e., hash tables) for clarity
  # index variables start from 1 because this is the standard in awk

  # map target name to description
  split("", TARGETS_DESCRIPTION_DATA)

  # map target name to section data
  # a section uses a target / variable as an anchor
  split("", TARGETS_SECTION_DATA)

  # the index for the next double-colon rule with description (the key doesn't include ~k)
  split("", TARGETS_DC_COUNTER)

  # map index to target name (order is important)
  split("", TARGETS)
  TARGETS_INDEX = 1

  # map index to line in description data (to be associated with the next anchor)
  split("", DESCRIPTION_DATA)
  DESCRIPTION_DATA_INDEX = 1

  # map index to line in section data (to be associated with the next anchor)
  split("", SECTION_DATA)
  SECTION_DATA_INDEX = 1

  # map variable name to description
  split("", VARIABLES_DESCRIPTION_DATA)

  # map variable name to section
  split("", VARIABLES_SECTION_DATA)

  # map index to variable name
  split("", VARIABLES)
  VARIABLES_INDEX = 1

  split("", DISPLAY_PARAMS)

  HEADER_TARGETS = "Available targets:"
  HEADER_VARIABLES = "Command-line arguments:"
  NUMBER_OF_FILES_PROCESSED = 0
  CURRENT_FILE = "" # the FILENAME of the file being read (see warn_about_continued_last_line)
  FILES_PROCESSED = ""
  SPACES_TABS_REGEX = "^[ \t]+|[ \t]+$"

  # used to decorate double-colon targets in the documentation
  DOUBLE_COLON_SEPARATOR = "~"

  reset_file_state()
}

# The parser state that must not be carried over from one Makefile to the next: a doc, a
# rule, a continued line, recipe or comment at the end of a file ends with that file.
# Pending section data is kept on purpose (a section is anchored to the next documented
# anchor, which can be in the next file).
function reset_file_state() {
  forget_descriptions_data()
  IN_MULTILINE_BACKSLASH_COMMENT = 0
  IN_MULTILINE_BACKSLASH_RECIPE = 0
  IN_CONTINUED_LINE = 0 # the previous line ended with a backslash (see CONTINUED_LINE)
  CONTINUED_LINE = ""
  IN_RULE = ""
}

function is_bool(value) {
  return value ~ /^[01]$/
}

# a color of 6 hex digits (without a leading #)
function is_hex_color(value) {
  return length(value) == 6 && value ~ /^[0-9A-Fa-f]+$/
}

# Report an invalid value of an option. The script goes on, so that all the invalid options
# are reported, and stops at the end of process_options().
function option_error(message) {
  printf("ERROR: %s\n", message) > STDERR
  OPTION_ERRORS++
}

# A file whose last line ends with a backslash: the line cannot be joined with a next one,
# so it is not parsed (awk has no hook at the end of a file, hence the check at the start of
# the next file and in END).
function warn_about_continued_last_line() {
  if (IN_CONTINUED_LINE) {
    printf("WARNING: [%s] the last line ends with a backslash\n", CURRENT_FILE) > STDERR
  }
}

# Report an error and stop. In unit-test mode, record the message and return instead, so
# that a test can check it and the remaining tests still run.
function fatal(message) {
  printf("%s\n", message) > STDERR
  if (UNIT_TEST) {
    FATAL_MSG = message
    return
  }
  ABORT = 1
  exit 1
}

# Process the user options (called from BEGIN, but not in unit-test mode). Every invalid
# option is reported, then the script exits with status 1 without any other output.
function process_options() {
  OUTPUT_FORMAT = OUTPUT_FORMAT == "" ? "ANSI" : toupper(OUTPUT_FORMAT)
  if (OUTPUT_FORMAT != "ANSI" && OUTPUT_FORMAT != "HTML" && OUTPUT_FORMAT != "LATEX") {
    option_error("OUTPUT_FORMAT should be ANSI, HTML or LATEX")
    OUTPUT_FORMAT = "ANSI"
  }

  FS = ":" # set the field separator

  initialize_colors()

  RECIPEPREFIX = RECIPEPREFIX == "" ? "\t" : substr(RECIPEPREFIX, 1, 1)

  VARIABLES_REGEX = VARIABLES_REGEX == "" ? VARIABLES_REGEX_DEFAULT : VARIABLES_REGEX

  # Target matching is heuristic; this is not a complete GNU Make parser.
  #
  # Since we cannot use negative lookahead, `(:|::)([^=:]|$)` ensures that
  # the rule separator is not followed by `:` or `=`, preventing assignment
  # operators such as `:=` and `::=` from being mistaken for target separators.
  #
  # Known limitations:
  #   - Colons inside variable references or function calls can cause false positives,
  #     e.g., `$(info a: b)`.
  #   - Escaped `#` in target names is not handled, e.g., `foo\#bar:`.
  #   - Escaped `:` in target names is mistaken for the rule separator, e.g., `foo\:bar:`.
  #   - Escaped spaces remain escaped in captured target names, e.g., `foo\ bar:` is
  #     captured as `foo\ bar`.
  if (TARGETS_REGEX == "") {
    TARGETS_REGEX = "^[ \t]*[^# \t=][^#:=]*[ \t]*&?(:|::)([^=:]|$)"
  }

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

  form_substitutions(SUB, SUB_PARAMS, SUB_LABELS, SUB_VALUES, g_sub_names, 0)
  form_substitutions(DSUB, g_dummy_array_params, g_dummy_array_labels, DSUB_VALUES,
                     DSUB_NAMES, 1)
  DSUB_COUNT = length_array_posix(DSUB_NAMES)

  if (OPTION_ERRORS > 0) {
    ABORT = 1
    exit 1
  }

  # we could exit faster but this causes the linter to not see defined variables
  SHOW_HELP = SHOW_HELP == "" ? 1 : SHOW_HELP  # to suppress during linting
  if (ARGC == 1) {
    if (SHOW_HELP) {
      print_help()
    }
    ABORT = 1
    exit 1
  }
}

# Initialize global variables.
BEGIN {
  init_globals()
  if (!UNIT_TEST) {
    process_options()
  }
}

# Each input line goes through the rules below, in this order, until a rule that fully
# handles it ends with `next`. The cheap tests come first (a comparison of one character
# before a regex or a function call). "Pending docs" are the doc lines seen since the last
# anchor: they are waiting for the target or variable they document.
#
#   Kind of line                                Pending docs       The line is
#   ------------------------------------------  -----------------  -------------------------
#   continuation of a line ending in \          -                  joined to it, then parsed
#   comment continued with \ (all its lines)    kept               skipped
#   line ending in \ (not a recipe, comment)    -                  stored for the next line
#   recipe line                                 discarded (1)      skipped
#   comment banner (###...)                     discarded          skipped
#   doc (##, ##!, ##%)                          extended           added to the pending docs
#   blank line                                  kept               skipped
#   section (##@)                               kept               saved (pending section)
#   conditional (ifeq, ..., endif)              kept               skipped
#   other directive (include, vpath, ...)       discarded          skipped
#   special target (.PHONY: ...)                kept               skipped
#   target line                                 given to it (2)    recorded if documented
#   variable assignment                         given to it (2)    recorded if documented
#   other comment                               kept               skipped
#   anything else                               discarded          skipped
#
#   (1) kept if the recipe line is blank
#   (2) without pending docs, the inline doc of the line is used
#
# Before these rules, a final \r is dropped from every line, and the per-file state is reset
# at the first line of each file.

# Makefiles with CRLF line endings: drop the \r
substr($0, length($0)) == "\r" { sub(/\r$/, "") }

FNR == 1 {
  warn_about_continued_last_line()
  reset_file_state()
  CURRENT_FILE = FILENAME
  NUMBER_OF_FILES_PROCESSED++
  if (FILES_PROCESSED) {
    FILES_PROCESSED = FILES_PROCESSED " " FILENAME
  } else {
    FILES_PROCESSED = FILENAME
  }
}

# A line continued with a backslash (outside recipes and comments) is joined with the next
# one, as in GNU Make: the backslash, the newline and the whitespace around them become one
# space. The rules below then see the whole logical line.
IN_CONTINUED_LINE {
  g_continuation = $0
  sub(/^[ \t]+/, "", g_continuation)
  $0 = CONTINUED_LINE " " g_continuation
  IN_CONTINUED_LINE = 0
}

# Skip backslash multiline comments
IN_MULTILINE_BACKSLASH_COMMENT ||
    (substr($0, length($0)) == "\\" && /^ *#/ && has_odd_terminal_backslashes($0)) {
  if (!IN_MULTILINE_BACKSLASH_COMMENT) {
    IN_MULTILINE_BACKSLASH_COMMENT = 1
  } else if (!has_odd_terminal_backslashes($0)) {
    IN_MULTILINE_BACKSLASH_COMMENT = 0
  }

  next
}

# (RECIPEPREFIX is a single character)
substr($0, length($0)) == "\\" && !(IN_RULE && substr($0, 1, 1) == RECIPEPREFIX) &&
    !IN_MULTILINE_BACKSLASH_RECIPE && has_odd_terminal_backslashes($0) {
  CONTINUED_LINE = substr($0, 1, length($0) - 1)
  sub(/[ \t]+$/, "", CONTINUED_LINE)
  IN_CONTINUED_LINE = 1
  next
}

(IN_RULE && substr($0, 1, 1) == RECIPEPREFIX) || IN_MULTILINE_BACKSLASH_RECIPE {
  # an empty recipe line is a blank line: it keeps the docs
  if (DESCRIPTION_DATA_INDEX > 1 && $0 !~ /^[ \t]*$/) {
    forget_descriptions_data()
  }

  IN_MULTILINE_BACKSLASH_RECIPE = 0
  if (substr($0, length($0)) == "\\") {
    g_recipe_text = substr($0, 1, 1) == RECIPEPREFIX ? substr($0, 2) : $0
    IN_MULTILINE_BACKSLASH_RECIPE = has_odd_terminal_backslashes(g_recipe_text)
  }

  next
}

{
  PATTERN_RULE_MATCHED = 0
}

# A line of three or more # is a comment banner: it is not a doc, and it discards the docs
# above it (they belong to another part of the Makefile)
/^[ \t]*###+[ \t]*$/ {
  forget_descriptions_data()
  next
}

# Capture the line if it is a description (but not a section).
/^ *##([^@]|$)/ {
  g_description_string = $0
  sub(/^ */, "", g_description_string)

  save_description_data(g_description_string)
  next
}

# Blank lines (empty or with only spaces and tabs) between docs are allowed (they do not
# discard the docs)
/^[ \t]*$/ {
  next
}

# New section (all lines in a multi-line sections should start with ##@)
/^ *##@/ {
  g_section_string = $0
  sub(/ *##@/, "", g_section_string) # strip the tags (they are not needed anymore)

  save_section_data(g_section_string)
  next
}

# A directive is not a rule, even with a colon (e.g., `ifeq "$(OS)" "a:b"`, `vpath %.c a:b`),
# unless it is an assignment to a variable named as a directive (e.g., `include := x`).
# Docs are kept above conditionals and discarded by the other directives.
/^[ \t]*(ifeq|ifneq|ifdef|ifndef|else|endif)([ \t(]|$)/ && $0 !~ VARIABLES_REGEX {
  next
}

/^[ \t]*(vpath|include|-include|sinclude|export|unexport|undefine)([ \t]|$)/ &&
    $0 !~ VARIABLES_REGEX {
  forget_descriptions_data()
  next
}

# (a colon inside a reference, as in `$(info a: b)`, is not a rule separator)
$0 ~ TARGETS_REGEX && !(index($1, "$") && has_unclosed_reference($1)) {
  if (detect_ignored_targets($0)) {
    next
  }

  if (DESCRIPTION_DATA_INDEX == 1) {
    parse_inline_descriptions($0)
  }

  # remove spaces up to & in grouped targets, e.g., `t1 t2   &` becomes `t1 t2&`
  # for the reason to use \\&, see:
  # https://www.gnu.org/software/gawk/manual/html_node/Gory-Details.html
  # GNU Make treats any run of spaces and tabs between target names as one separator
  g_target_name_nominal = $1
  gsub(/[ \t]+/, " ", g_target_name_nominal)
  sub(/[ \t]*&/, "\\&", g_target_name_nominal)
  g_target_name_nominal = strip_start_end_spaces_tabs(g_target_name_nominal)

  if (DESCRIPTION_DATA_INDEX > 1) {
    g_target_name = g_target_name_nominal
    if (is_double_colon_rule($0)) {
      g_target_name = form_dc_target_name(g_target_name_nominal)
    }

    TARGETS_INDEX = associate_data_with_anchor(strip_start_end_spaces_tabs(g_target_name),
                                               TARGETS,
                                               TARGETS_INDEX,
                                               TARGETS_DESCRIPTION_DATA,
                                               TARGETS_SECTION_DATA,
                                               "target")
    TARGETS_DC_COUNTER[g_target_name_nominal]++
  }

  IN_RULE = g_target_name_nominal
  PATTERN_RULE_MATCHED = 1
}

$0 ~ VARIABLES_REGEX {
  if (DESCRIPTION_DATA_INDEX == 1) {
    parse_inline_descriptions($0, 1)
  }

  if (DESCRIPTION_DATA_INDEX > 1) {
    g_variable_name = strip_start_end_spaces_tabs(parse_variable_name($0))
    VARIABLES_INDEX = associate_data_with_anchor(g_variable_name,
                                                 VARIABLES,
                                                 VARIABLES_INDEX,
                                                 VARIABLES_DESCRIPTION_DATA,
                                                 VARIABLES_SECTION_DATA,
                                                 "variable")
  }

  IN_RULE = ""
  PATTERN_RULE_MATCHED = 1
}

# Docs are discarded when they are followed by an unrelated line (e.g., a function call,
# define), so that they do not end up on the next anchor. Comments are not unrelated: the
# docs above them are kept. (Blank lines, sections, directives, anchors and ignored
# special targets have been handled above.)
!PATTERN_RULE_MATCHED && $0 !~ /^[ \t]*#/ {
  forget_descriptions_data()
}

# Display results (all stdout is here).
function print_documentation() {
  g_max_target_length = get_max_anchor_length(TARGETS, TARGETS_DESCRIPTION_DATA)
  g_max_variable_length = VARS ? get_max_anchor_length(VARIABLES, VARIABLES_DESCRIPTION_DATA) : 0
  g_max_anchor_length = max(g_max_target_length, g_max_variable_length)
  g_separator = get_separator("-", g_max_anchor_length)

  if (OUTPUT_FORMAT == "HTML") {
    print(HTML_HEADER)
  } else if (OUTPUT_FORMAT == "LATEX") {
    print(LATEX_HEADER)
  }

  # process targets
  if (g_max_target_length > 0) {
    printf("%s\n%s\n%s\n", g_separator, HEADER_TARGETS, g_separator)

    g_n_elements = length_array_posix(TARGETS)
    for (g_indx = 1; g_indx <= g_n_elements; g_indx++) {
      g_target = TARGETS[g_indx]
      g_description = format_description_data(g_target,
                                              TARGETS_DESCRIPTION_DATA,
                                              g_max_anchor_length)
      g_section = get_associated_section_data(g_target, TARGETS_SECTION_DATA)
      display_anchor_with_data(g_target, g_description, g_section, g_max_anchor_length)
    }
  }

  # process variables
  if (g_max_variable_length > 0 && VARS) {
    g_variables_display_pattern = g_max_target_length > 0 ? "\n%s\n%s\n%s\n": "%s\n%s\n%s\n"

    printf(g_variables_display_pattern, g_separator, HEADER_VARIABLES, g_separator)
    g_n_elements = length_array_posix(VARIABLES)
    for (g_indx = 1; g_indx <= g_n_elements; g_indx++) {
      g_variable = VARIABLES[g_indx]
      g_description = format_description_data(g_variable,
                                              VARIABLES_DESCRIPTION_DATA,
                                              g_max_anchor_length)
      g_section = get_associated_section_data(g_variable, VARIABLES_SECTION_DATA)
      display_anchor_with_data(g_variable, g_description, g_section, g_max_anchor_length)
    }
  }

  if (g_max_target_length > 0 || (g_max_variable_length > 0 && VARS)) {
    printf("%s\n", g_separator)
  } else {
    if (NUMBER_OF_FILES_PROCESSED > 0) {
      printf("WARNING: no documented targets/variables in %s\n",
             FILES_PROCESSED) > STDERR
    }
  }

  if (OUTPUT_FORMAT == "HTML") {
    print(HTML_FOOTER)
  } else if (OUTPUT_FORMAT == "LATEX") {
    print(LATEX_FOOTER)
  }
}

END {
  if (ABORT) {
    exit ABORT
  }
  if (!UNIT_TEST) {
    warn_about_continued_last_line()
    print_documentation()
  }
}
