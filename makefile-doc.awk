# Generate docs for Makefile variables and targets
#
#    File: makefile-doc.awk
#  Author: Dimitar Dimitrov
# License: Apache-2.0
# Project: https://github.com/drdv/makefile-doc
# Version: v0.9
#
# Usage (see project README.md for more details):
#   awk [-v option=value] -f makefile-doc.awk [Makefile ...]
#
# Options (set using -v option=value, possible values given in {...}, (.) is the default):
#   + DEBUG: {(0), 1} output debug info (in an org-mode format)
#   + DEBUG_FILE: debug info file
#   + EXPANDED_TARGETS: NAME[:LABEL]:[VALUE][;...], see below
#   + TARGETS_REGEX: regex for matching targets
#   + VARIABLES_REGEX: regex for matching variables
#   * VARS: {0, (1)} show documented variables
#   * PADDING: {(" "), ".", ...} a single padding character between anchors and docs
#   * DEPRECATED: {0, (1)} show deprecated anchors
#   * OFFSET: {0, 1, (2), ...} number of spaces to offset docs from anchors
#   * CONNECTED: {0, (1)} ignore docs followed by an empty line
#   * see as well the color codes below
#
# Notes:
#   * In the code, the term anchor is used to refer to Makefile targets / variables.
#   * Docs can be placed above an anchor or inline (the latter is discarded if the
#     former is present).
#   * Anchor docs can start with the following tokens:
#      * ##  default anchors (displayed in COLOR_DEFAULT)
#      * ##! special anchors (displayed in COLOR_ATTENTION)
#      * ##% deprecated anchor (displayed in COLOR_DEPRECATED)
#      * ##@ section (displayed in COLOR_SECTION)
#
# Color codes (https://en.wikipedia.org/wiki/ANSI_escape_code):
#   * COLOR_DEFAULT: (34) blue
#   * COLOR_ATTENTION: (31) red
#   * COLOR_DEPRECATED: (33) yellow
#   * COLOR_SECTION: (32) green
#   * COLOR_WARNING: (35) magenta -- used for warnings
#   * COLOR_BACKTICKS: (0) disabled -- used for text in backticks in docs
#
#   Colors are specified using the parameter in ANSI escape codes, e.g., the parameter
#   for blue is the 34 in `\033[34m`.
#
# Expanded_targets:
#   FIXME: to document
#
# Code conventions:
#   * Variables in a function, to which an assignment is made, should have names ending
#     in _local (because AWK is a bit special in that respect).
#   * Compatibility: the code is meant to run with all major awk implementations.

function max(var1, var2) {
  if (var1 >= var2) {
    return var1
  }
  return var2
}

# in POSIX-compliant AWK the length function works on strings but not on arrays
function length_array_posix(array) {
  array_numb_elements_local = 0
  for (counter_local in array) {
    array_numb_elements_local++
  }
  return array_numb_elements_local
}

function join(array, delimiter) {
  string_local = ""
  for (indx_local=1; indx_local<=length_array_posix(array); indx_local++) {
    if (indx_local == 1) {
      string_local = array[indx_local]
    } else {
      string_local = string_local delimiter array[indx_local]
    }
  }
  return string_local
}

function get_tag_from_description(string) {
  if (match(string, /^ *(##!|##%|##)/)) {
    tag_local = substr(string, RSTART, RLENGTH)
    sub(/ */, "", tag_local)
    return tag_local
  }
  return 0
}

function save_description_data(string) {
  DESCRIPTION_DATA[DESCRIPTION_DATA_INDEX] = string
  DESCRIPTION_DATA_INDEX++

  debug(DEBUG_INDENT_STACK " save_description_data")
  debug_indent_down()
  debug_array(DESCRIPTION_DATA, DESCRIPTION_DATA_INDEX, "DESCRIPTION_DATA")
  debug_indent_up()
}

function forget_descriptions_data() {
  delete DESCRIPTION_DATA
  DESCRIPTION_DATA_INDEX = 1

  debug(DEBUG_INDENT_STACK " forget_descriptions_data")
  debug_indent_down()
  debug_array(DESCRIPTION_DATA, DESCRIPTION_DATA_INDEX, "DESCRIPTION_DATA")
  debug_indent_up()
}

function parse_inline_descriptions(whole_line_string) {
  debug(DEBUG_INDENT_STACK " parse_inline_descriptions")
  debug_indent_down()
  if (match(whole_line_string, / *(##!|##%|##)/)) {
    inline_string_local = substr(whole_line_string, RSTART)
    sub(/^ */, "", inline_string_local)
    save_description_data(inline_string_local)
  }
  debug_indent_up()
}

function parse_variable_name(whole_line_string) {
  split(whole_line_string, array_whole_line, ASSIGNMENT_OPERATORS_PATTERN)
  variable_name_local = array_whole_line[1]

  # here we need to preserve order in order to remove unexport and not just export
  for (indx_local=1;
       indx_local<=length_array_posix(ARRAY_OF_VARIABLE_QUALIFIERS);
       indx_local++) {
    # use gsub to strip multiple occurrences of a qualifier
    gsub(ARRAY_OF_VARIABLE_QUALIFIERS[indx_local], "", variable_name_local)
  }
  sub(/[ ]+/, "", variable_name_local)
  return variable_name_local
}

function associate_data_with_anchor(anchor_name,
                                    anchors,
                                    anchors_index,
                                    anchors_description_data,
                                    anchors_section_data,
                                    anchor_type) {
  debug(DEBUG_INDENT_STACK " debug_associate_data_with_" anchor_type " (INITIAL): " anchor_name)
  debug_indent_down()
  debug_array(anchors, anchors_index, "anchors", anchor_type)
  debug_dict(anchors_description_data, "anchors_description_data", anchor_type)
  debug_dict(anchors_section_data, "anchors_section_data", anchor_type)
  debug_array(DESCRIPTION_DATA, DESCRIPTION_DATA_INDEX, "DESCRIPTION_DATA")
  debug_array(SECTION_DATA, SECTION_DATA_INDEX, "SECTION_DATA")
  debug_indent_up()

  if (anchor_name in anchors_description_data) {
    # omit variable related warnings when they are not displayed
    if (anchor_type != "variable" || VARS) {
      printf("%s[%s] redefined docs of %s: %s%s\n",
             COLOR_WARNING_CODE,
             FILENAME,
             anchor_type,
             anchor_name,
             COLOR_RESET_CODE)
    }
  } else {
    anchors[anchors_index] = anchor_name
    anchors_index++
  }

  # here we might overwrite a description associatd with a redefined anchor
  anchors_description_data[anchor_name] = assemble_description_data()
  forget_descriptions_data()

  # note that section data is associated only with documented anchors
  if (length_array_posix(SECTION_DATA) > 0) {
    if (anchor_name in anchors_section_data) {
      printf("%s[%s] redefining associated section data: %s%s\n",
             COLOR_WARNING_CODE,
             FILENAME,
             anchor_name,
             COLOR_RESET_CODE)
    }

    anchors_section_data[anchor_name] = assemble_section_data()
    forget_section_data()
  }

  debug(DEBUG_INDENT_STACK " debug_associate_data_with_" anchor_type " (FINAL)")
  debug_indent_down()
  debug_array(anchors, anchors_index, "anchors", anchor_type)
  debug_dict(anchors_description_data, "anchors_description_data", anchor_type)
  debug_dict(anchors_section_data, "anchors_section_data", anchor_type)
  debug_indent_up()

  return anchors_index
}

function save_section_data(string) {
  SECTION_DATA[SECTION_DATA_INDEX] = string
  SECTION_DATA_INDEX++

  debug(DEBUG_INDENT_STACK " save_section_data")
  debug_indent_down()
  debug_array(SECTION_DATA, SECTION_DATA_INDEX, "SECTION_DATA")
  debug_indent_up()
}

function forget_section_data() {
  delete SECTION_DATA
  SECTION_DATA_INDEX = 1

  debug(DEBUG_INDENT_STACK " forget_section_data")
  debug_indent_down()
  debug_array(SECTION_DATA, SECTION_DATA_INDEX, "SECTION_DATA")
  debug_indent_up()
}

function get_associated_section_data(anchor_name,
                                     anchor_section_data) {
  if (anchor_name in anchor_section_data) {
    return anchor_section_data[anchor_name]
  }
  return 0 # means that there is no associated section data with this anchor
}

function get_max_anchor_length(anchors) {
  max_len_local = 0
  for (key_local in anchors) { # order is not important
    anchor_local = anchors[key_local]
    if (anchor_local in EXPANDED_TARGETS_DICT_RENAMED) {
      len_local = length(EXPANDED_TARGETS_DICT_RENAMED[anchor_local])
    }
    else {
      len_local = length(anchor_local)
    }
    if (len_local > max_len_local) {
      max_len_local = len_local
    }
  }
  return max_len_local
}

function get_separator(len_anchors) {
  # busybox's awk doesn't support %* patterns (so I use a loop)
  separator_local = ""
  for (indx_local = 1;
       indx_local <= max(len_anchors,
                         max(length(HEADER_TARGETS), length(HEADER_VARIABLES)));
       indx_local++) {
    separator_local = separator_local "-"
  }
  return separator_local
}

function substitute_backticks_patterns(string) {
  # --------------------------------------------------------------------------
  # Since I cannot use this code in mawk and nawk, I implemented a manual hack
  # --------------------------------------------------------------------------
  # replace_with = COLOR_BACKTICKS_CODE "\\1" COLOR_RESET_CODE
  # return gensub(/`([^`]+)`/, replace_with, "g", description) # only for gawk
  # --------------------------------------------------------------------------

  string_local = string
  while (match(string_local, /`([^`]+)`/)) {
    before_match_local = substr(string_local, 1, RSTART - 1)
    inside_match_local = substr(string_local, RSTART + 1, RLENGTH - 2)
    after_match_local = substr(string_local, RSTART + RLENGTH)

    string_local = sprintf("%s%s%s%s%s",
                           before_match_local,
                           COLOR_BACKTICKS_CODE,
                           inside_match_local,
                           COLOR_RESET_CODE,
                           after_match_local)
  }
  return string_local
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
                                 len_anchor_names) {
  # the automatically-assigned indexes during the split are: 1, ..., #lines
  split(anchors_description_data[anchor_name], array_of_lines_local, "\n")

  # the tag for the first line is stripped below (after the parameter update)
  description_local = sprintf("%" OFFSET "s", "") array_of_lines_local[1]

  for (indx_local = 2;
       indx_local <= length_array_posix(array_of_lines_local);
       indx_local++) {
    line_local = array_of_lines_local[indx_local]
    sub(/^(##|##!|##%)/, "", line_local) # strip the tag
    description_local = sprintf("%s\n%s%s",
                                description_local,
                                sprintf("%" OFFSET + len_anchor_names "s", ""),
                                line_local)
  }

  update_display_parameters(description_local)
  # the order of alternatives is important when using goawk
  sub(/(##!|##%|##)/, "", description_local) # strip the tag (keep the leading space)
  return colorize_description_backticks(description_local)
}

function assemble_description_data() {
  description_local = DESCRIPTION_DATA[1]
  for (indx_local = 2; indx_local<=length_array_posix(DESCRIPTION_DATA); indx_local++) {
    description_local = description_local "\n" DESCRIPTION_DATA[indx_local]
  }
  return description_local
}

function assemble_section_data() {
  section_local = SECTION_DATA[1]
  for (indx_local = 2; indx_local <= length_array_posix(SECTION_DATA); indx_local++) {
    section_local = section_local "\n" SECTION_DATA[indx_local]
  }
  return section_local
}

function update_display_parameters(description) {
  tag_local = get_tag_from_description(description)
  if (tag_local == "##!") {
    DISPLAY_PARAMS["color"] = COLOR_ATTENTION_CODE
    DISPLAY_PARAMS["show"] = 1
  } else if (tag_local == "##%") {
    DISPLAY_PARAMS["color"] = COLOR_DEPRECATED_CODE
    DISPLAY_PARAMS["show"] = DEPRECATED
  }
  else if (tag_local == "##") {
    DISPLAY_PARAMS["color"] = COLOR_DEFAULT_CODE
    DISPLAY_PARAMS["show"] = 1
  } else {
    printf("%sUnknown error (we should never be here): %s%s\n",
           COLOR_WARNING_CODE,
           description,
           COLOR_RESET_CODE)
    exit 1
  }
}

function form_expanded_targets() {
  # Form the global variable EXPANDED_TARGETS_DICT
  #
  # The format is: NAME[:LABEL]:[VALUE][;...]
  #
  numb_expanded_targets_local = split(EXPANDED_TARGETS, expanded_targets_key_value_local, ";")
  for (indx_local=1;
       indx_local<=numb_expanded_targets_local;
       indx_local++) {
    split(expanded_targets_key_value_local[indx_local], key_value_parts_local, ":")
    gsub(/^ +| +$/, "", key_value_parts_local[1])
    if (length_array_posix(key_value_parts_local) == 2) {
      EXPANDED_TARGETS_DICT[key_value_parts_local[1]] = key_value_parts_local[2]
    } else {
      EXPANDED_TARGETS_DICT[key_value_parts_local[1]] = key_value_parts_local[3]
      EXPANDED_TARGETS_DICT_RENAMED[key_value_parts_local[1]] = key_value_parts_local[2]
    }

  }
}

function display_expanded_target(target, len_anchors) {
  split(EXPANDED_TARGETS_DICT[target], value_parts_local, " ")
  for (indx_local=1;
       indx_local<=length_array_posix(value_parts_local);
       indx_local++) {
    # the + 1 is because of the usual one space we add between the token ## and the docs
    printf("%s%s\n",
           sprintf("%" len_anchors + OFFSET + 1 "s", ""),
           value_parts_local[indx_local])
  }
}

function display_anchor_with_data(anchor, description, section, len_anchors) {
  # Display the section (if there is one) even if it is anchored to a deprecated anchor
  # that is not to be displayed.
  if (section) {
    printf("%s%s%s\n", COLOR_SECTION_CODE, section, COLOR_RESET_CODE)
  }

  if (DISPLAY_PARAMS["show"]) {
    if (anchor in EXPANDED_TARGETS_DICT_RENAMED)
      renamed_anchor = EXPANDED_TARGETS_DICT_RENAMED[anchor]
    else
      renamed_anchor = anchor

    DISPLAY_PATTERN = "%s%-" len_anchors "s%s"
    formatted_anchor = sprintf(DISPLAY_PATTERN,
                               DISPLAY_PARAMS["color"],
                               format_anchor_name(renamed_anchor),
                               COLOR_RESET_CODE)
    if (PADDING != " ") {
      gsub(/ /, PADDING, formatted_anchor)
    }
    printf("%s%s\n", formatted_anchor, description)
  }
  display_expanded_target(anchor, len_anchors)
}

function count_numb_double_colon(new_target) {
  counter_local = 1
  prefix_local = "[" new_target "]"
  n_prefix_local = length(prefix_local)
  for (indx_local in TARGETS) { # order is not important
    target_local = TARGETS[indx_local]
    if (length(target_local) >= n_prefix_local &&
        substr(target_local, 1, n_prefix_local) == prefix_local) {
      counter_local++
    }
  }
  return counter_local
}

# modifies only double-colon targets:
# [double_colon_target_name]:1 -> double_colon_target_name:1
function format_anchor_name(target) {
  if (match(target, /\[.+\]/)) {
    target_name_local = substr(target, RSTART+1, RLENGTH-2)
    if (match(target, /:([0-9]*)/)) {
      target_index_local = substr(target, RSTART+1, RLENGTH-1)
    }
    return target_name_local ":" target_index_local
  }
  return target
}

function trim_start_end_spaces(string_local) {
  sub(/^ */, "", string_local)
  sub(/ *$/, "", string_local)
  return string_local
}

function ansi_color(string) {
  return "\033[" string "m"
}

function initialize_colors() {
  COLOR_DEFAULT_CODE = ansi_color(COLOR_DEFAULT == "" ? 34 : COLOR_DEFAULT)
  COLOR_ATTENTION_CODE = ansi_color(COLOR_ATTENTION == "" ? 31 : COLOR_ATTENTION)
  COLOR_DEPRECATED_CODE = ansi_color(COLOR_DEPRECATED == "" ? 33 : COLOR_DEPRECATED)
  COLOR_WARNING_CODE = ansi_color(COLOR_WARNING == "" ? 35 : COLOR_WARNING)
  COLOR_SECTION_CODE = ansi_color(COLOR_SECTION == "" ? 32 : COLOR_SECTION)

  COLOR_BACKTICKS = COLOR_BACKTICKS == "" ? 0 : COLOR_BACKTICKS
  COLOR_BACKTICKS_CODE = ansi_color(COLOR_BACKTICKS)

  COLOR_RESET_CODE = ansi_color(0)
}

# It would be nice to extract the options from the docstring of this script (there could
# be some sort of prefix before each option). Unfortunately, I can get the script passed
# with the -f flag only using gawk (so, names of options are hard-coded in print_help):
# for (indx_local in PROCINFO["argv"]) {
#   if (PROCINFO["argv"][indx_local] == "-f") {
#     printf PROCINFO["argv"][indx_local + 1]
#   }
# }
function print_help() {
    print "Usage: awk [-v option=value] -f makefile-doc.awk [Makefile ...]"
    print "Description: Generate docs for Makefile variables and targets"
    print "Options:"
    printf "  DEBUG ([bool] output debug info): %s\n", DEBUG
    printf "  DEBUG_FILE (debug info file): %s\n", DEBUG_FILE
    printf "  EXPANDED_TARGETS (NAME[:LABEL]:[VALUE][;...]): %s\n", EXPANDED_TARGETS
    printf "  TARGETS_REGEX (regex for matching targets): %s\n", TARGETS_REGEX
    printf "  VARIABLES_REGEX (regex for matching variables): %s\n", VARIABLES_REGEX
    printf "  VARS ([bool] show documented variables): %s\n", VARS
    printf "  PADDING (a padding character between anchors and docs): \"%s\"\n", PADDING
    printf "  DEPRECATED ([bool] show deprecated anchors): %s\n", DEPRECATED
    printf "  OFFSET (offset of docs from anchors): %s\n", OFFSET
    printf "  CONNECTED (ignore docs followed by an empty line): %s\n", CONNECTED
    printf "  COLORS: "
    printf "%sDEFAULT%s, ", COLOR_DEFAULT_CODE, COLOR_RESET_CODE
    printf "%sATTENTION%s, ", COLOR_ATTENTION_CODE, COLOR_RESET_CODE
    printf "%sDEPRECATED%s, ", COLOR_DEPRECATED_CODE, COLOR_RESET_CODE
    printf "%sSECTION%s, ", COLOR_SECTION_CODE, COLOR_RESET_CODE
    printf "%sWARNING%s, ", COLOR_WARNING_CODE, COLOR_RESET_CODE
    printf "%sBACKTICKS%s\n", COLOR_BACKTICKS_CODE, COLOR_RESET_CODE
}

# =============================================================================
# DEBUG STUFF
# =============================================================================
function debug(message) {
  if (DEBUG) {
    printf "%s\n", message >> DEBUG_FILE
  }
}

function debug_indent_up() {
  DEBUG_INDENT_STACK = substr(DEBUG_INDENT_STACK, 1, length(DEBUG_INDENT_STACK)-1)
}

function debug_indent_down() {
  DEBUG_INDENT_STACK = DEBUG_INDENT_STACK "*"
}

function debug_pattern_rule(title) {
  debug(DEBUG_INDENT_STACK " line: " FNR " (" title ")")
  debug_indent_down()
}

function debug_array(array, array_next_index, array_name, array_note) {
  if (array_note) {
    array_note_local = ", note: " array_note
  } else {
    array_note_local = ")"
  }
  debug(DEBUG_INDENT_STACK " [A] " array_name " (length: " length_array_posix(array) ", next index: " array_next_index array_note_local)
  for (array_indx_local=1;
       array_indx_local<=length_array_posix(array);
       array_indx_local++) {
    debug("+ " array[array_indx_local])
  }
}

function debug_dict(array, array_name, array_note) {
  if (array_note) {
    array_note_local = ", note: " array_note
  } else {
    array_note_local = ")"
  }

  debug(DEBUG_INDENT_STACK " [D] " array_name " (length: " length_array_posix(array) array_note_local)
  for (array_key_local in array) {
    debug("+ " array_key_local ": " array[array_key_local])
  }
}

function debug_init() {
  debug(DEBUG_INDENT_STACK " debug_init")
  debug("+ ~FS~: " FS)
  debug("+ ~DEBUG_FILE~: " DEBUG_FILE)
  debug("+ ~EXPANDED_TARGETS~: " EXPANDED_TARGETS)
  debug("+ ~TARGETS_REGEX~: " TARGETS_REGEX)
  debug("+ ~VARIABLES_REGEX~: " VARIABLES_REGEX)
  debug("+ ~VARS~: " VARS)
  debug("+ ~PADDING~: " PADDING)
  debug("+ ~DEPRECATED~: " DEPRECATED)
  debug("+ ~OFFSET~: " OFFSET)
  debug("+ ~CONNECTED~: " CONNECTED)
  debug("+ ~WIP_TARGET~: " WIP_TARGET)
}

function debug_FNR1() {
  debug(DEBUG_INDENT_STACK " debug_FNR1")
  debug("+ ~number_of_files_processed~: " number_of_files_processed)
  debug("+ ~files_processed~: " files_processed)
}

function debug_description_not_section() {
  debug(DEBUG_INDENT_STACK " debug_description_not_section")
  debug("+ ~$0~: " $0)
  debug("+ ~description_string~: " description_string)
}

function debug_empty_line() {
  debug(DEBUG_INDENT_STACK " debug_empty_line")
  debug("+ [before reset] ~WIP_TARGET~:" WIP_TARGET)
}

function debug_new_section() {
  debug(DEBUG_INDENT_STACK " debug_new_section")
  debug("+ ~$0~: " $0)
  debug("+ ~section_string~: " section_string)
}

function debug_target_matched() {
  debug(DEBUG_INDENT_STACK " debug_target_matched")
  debug("+ ~$0~: " $0)
  debug("+ ~$1~: " $1)
  debug("+ ~target_name~: " target_name)
  debug("+ ~WIP_TARGET~: " WIP_TARGET)
  debug_indent_down()
  debug_array(DESCRIPTION_DATA, DESCRIPTION_DATA_INDEX, "DESCRIPTION_DATA")
  debug_indent_up()
}

function debug_variable_matched() {
  debug(DEBUG_INDENT_STACK " debug_variable_matched")
  debug("+ ~variable_name~: " variable_name)
  debug_indent_down()
  debug_array(DESCRIPTION_DATA, DESCRIPTION_DATA_INDEX, "DESCRIPTION_DATA")
  debug_indent_up()
}

function debug_END() {
  debug(DEBUG_INDENT_STACK " debug_END")
  debug("+ ~max_target_length~: " max_target_length)
  debug("+ ~max_variable_length~: " max_variable_length)
  debug("+ ~max_anchor_length~: " max_anchor_length)
  debug("+ ~separator~: " separator)
  debug_indent_down()
  debug_array(DESCRIPTION_DATA, DESCRIPTION_DATA_INDEX, "DESCRIPTION_DATA")
  debug_array(SECTION_DATA, SECTION_DATA_INDEX, "SECTION_DATA")

  debug_array(TARGETS, TARGETS_INDEX, "TARGETS")
  debug_dict(TARGETS_DESCRIPTION_DATA, "TARGETS_DESCRIPTION_DATA")
  debug_dict(TARGETS_SECTION_DATA, "TARGETS_SECTION_DATA")

  debug_array(VARIABLES, VARIABLES_INDEX, "VARIABLES")
  debug_dict(VARIABLES_DESCRIPTION_DATA, "VARIABLES_DESCRIPTION_DATA")
  debug_dict(VARIABLES_SECTION_DATA, "VARIABLES_SECTION_DATA")

  debug_dict(EXPANDED_TARGETS_DICT, "EXPANDED_TARGETS_DICT")
  debug_dict(EXPANDED_TARGETS_DICT_RENAMED, "EXPANDED_TARGETS_DICT_RENAMED")
  debug_indent_up()
}

# =============================================================================

# Initialize global variables.
BEGIN {
  DEBUG_FILE = DEBUG_FILE == "" ? ".debug-makefile-doc.org" : DEBUG_FILE
  if (DEBUG) {
    DEBUG_INDENT_STACK = "*"
    printf "" > DEBUG_FILE
  }
  debug(DEBUG_INDENT_STACK " BEGIN")
  debug_indent_down()

  FS = ":" # set the field separator

  ASSIGNMENT_OPERATORS_PATTERN = "(=|:=|::=|:::=|!=|\\?=|\\+=)"
  split("override unexport export private", ARRAY_OF_VARIABLE_QUALIFIERS, " ")
  VARIABLES_REGEX_DEFAULT = sprintf("^ *( *(%s) *)* *[^.#][a-zA-Z0-9_-]* *%s",
                                    join(ARRAY_OF_VARIABLE_QUALIFIERS, "|"),
                                    ASSIGNMENT_OPERATORS_PATTERN)
  initialize_colors()

  VARIABLES_REGEX = VARIABLES_REGEX == "" ? VARIABLES_REGEX_DEFAULT : VARIABLES_REGEX
  TARGETS_REGEX = TARGETS_REGEX == "" ? "^ *[^.#][ ,a-zA-Z0-9$_/%.(){}-]* *&?(:|::)( |$)" : TARGETS_REGEX
  VARS = VARS == "" ? 1 : VARS
  PADDING = PADDING == "" ? " " : PADDING
  DEPRECATED = DEPRECATED == "" ? 1 : DEPRECATED
  OFFSET = OFFSET == "" ? 2 : OFFSET
  CONNECTED = CONNECTED == "" ? 1 : CONNECTED
  if (length(PADDING) != 1) {
    printf("%sPADDING should have length 1%s\n", COLOR_WARNING_CODE, COLOR_RESET_CODE)
    exit 1
  }

  WIP_TARGET = ""

  if (ARGC == 1) {
    print_help()
    exit 1
  }

  HEADER_TARGETS = "Available targets:"
  HEADER_VARIABLES = "Command-line arguments:"

  # initialize global arrays (i.e., hash tables) for clarity
  # index variables start from 1 because this is the standard in awk

  # map target name to description (order is not important)
  split("", TARGETS_DESCRIPTION_DATA)

  # map target name to section data (order is not important)
  # a section uses a targtet / variable as an anchor
  split("", TARGETS_SECTION_DATA)

  # map index to target name (order is important)
  split("", TARGETS)
  TARGETS_INDEX = 1

  # map index to line in description data (to be associated with the next anchor)
  split("", DESCRIPTION_DATA)
  DESCRIPTION_DATA_INDEX = 1

  # map index to line in section data (to be associated with the next anchor)
  split("", SECTION_DATA)
  SECTION_DATA_INDEX = 1

  # map variable name to description (order is not important)
  split("", VARIABLES_DESCRIPTION_DATA)

  # map variable name to section (order is not important)
  split("", VARIABLES_SECTION_DATA)

  # map index to variable name (order is important)
  split("", VARIABLES)
  VARIABLES_INDEX = 1

  split("", DISPLAY_PARAMS)

  debug_init()
}

{
  PATTERN_RULE_MATCHED = 0
}

FNR == 1 {
  debug_indent_up()
  debug(DEBUG_INDENT_STACK " FILE: " FILENAME)
  debug_indent_down()
  debug_pattern_rule("file counter")

  number_of_files_processed++
  if (files_processed) {
    files_processed = files_processed " " FILENAME
  } else {   # I don't want an extra space before or after (affects the diff)
    files_processed = FILENAME
  }
  debug_FNR1()
  debug_indent_up()
}

# Capture the line if it is a description (but not a section).
/^ *##([^@]|$)/ {
  debug_pattern_rule("description")

  description_string = $0
  sub(/^ */, "", description_string)

  debug_description_not_section()

  save_description_data(description_string)

  PATTERN_RULE_MATCHED = 1
  debug_indent_up()
}

# Flush accumulated descriptions if followed by an empty line.
/^$/ {
  debug_pattern_rule("empty line")
  debug_empty_line()

  if (CONNECTED) {
    forget_descriptions_data()
  }

  # An empty line ends the definition of a target
  WIP_TARGET = ""

  PATTERN_RULE_MATCHED = 1
  debug_indent_up()
}

# New section (all lines in a multi-line sections should start with ##@)
/^ *##@/ {
  debug_pattern_rule("new section")

  section_string = $0
  sub(/ *##@/, "", section_string) # strip the tags (they are not needed anymore)

  debug_new_section()

  save_section_data(section_string)

  PATTERN_RULE_MATCHED = 1
  debug_indent_up()
}

# Process target, whose name
#  1. may start with spaces
#  2. but not with a # or with a dot (in order to jump over e.g., .PHONY)
#  3. and can have spaces before the final colon.
#  4. There can be multiple space-separated targets on one line (they are captured
#     together).
#  5. Targets of the form $(TARGET-NAME) and ${TARGET-NAME} are detected.
#  6. After the final colon, we require either at least one space or end of line -- this
#     is because otherwise we would match VAR := value.
#  7. FS = ":" is assumed.
#
# Note: I have to use *(:|::) instead of *{1,2} because the latter doesn't work in mawk.
#
$0 ~ TARGETS_REGEX {
  debug_pattern_rule("target")

  target_name = $1

  # remove spaces up to & in grouped targets, e.g., `t1 t2   &` becomes `t1 t2&`
  # for the reason to use \\&, see AWK's Gory-Details!
  # https://www.gnu.org/software/gawk/manual/html_node/Gory-Details.html
  sub(/ *&/, "\\&", target_name)
  if ($0 ~ "::") {
    target_name = sprintf("[%s]:%s",
                          target_name,
                          count_numb_double_colon(target_name))
  }

  debug_target_matched()

  # look for inline descriptions only if there aren't any descriptions above the target
  if (length_array_posix(DESCRIPTION_DATA) == 0 && WIP_TARGET != target_name) {
    parse_inline_descriptions($0) # this might modify DESCRIPTION_DATA
  }

  if (length_array_posix(DESCRIPTION_DATA) > 0) {
    WIP_TARGET = target_name
    debug(DEBUG_INDENT_STACK " [assign] ~WIP_TARGET~: " WIP_TARGET)
    TARGETS_INDEX = associate_data_with_anchor(trim_start_end_spaces(target_name),
                                               TARGETS,
                                               TARGETS_INDEX,
                                               TARGETS_DESCRIPTION_DATA,
                                               TARGETS_SECTION_DATA,
                                               "target")
  }

  PATTERN_RULE_MATCHED = 1
  debug_indent_up()
}

# Process variable, whose name
#  1. may start with spaces
#  2. but not with a # or with a dot (in order to jump over e.g., .DEFAULT_GOAL)
#  3. can be followed by spaces and one of the assignment operators, see
#     ASSIGNMENT_OPERATORS_PATTERN

$0 ~ VARIABLES_REGEX {
  debug_pattern_rule("variable")
  debug("+ ~$0~: " $0)

  if (length_array_posix(DESCRIPTION_DATA) == 0) {
    parse_inline_descriptions($0) # this might modify DESCRIPTION_DATA
  }

  if (length_array_posix(DESCRIPTION_DATA) > 0) {
    variable_name = trim_start_end_spaces(parse_variable_name($0))
    debug_variable_matched()
    VARIABLES_INDEX = associate_data_with_anchor(variable_name,
                                                 VARIABLES,
                                                 VARIABLES_INDEX,
                                                 VARIABLES_DESCRIPTION_DATA,
                                                 VARIABLES_SECTION_DATA,
                                                 "variable")
  }

  PATTERN_RULE_MATCHED = 1
  debug_indent_up()
}

PATTERN_RULE_MATCHED == 0 {
  debug_pattern_rule("bucket")
  debug("+ ~$0~: " $0)
  debug_indent_up()
}

# Display results (except for warnings all stdout is here).
END {
  debug_indent_up()
  debug(DEBUG_INDENT_STACK " END")
  debug_indent_down()

  # EXPANDED_TARGETS_DICT_RENAMED should be formed before get_max_anchor_length
  # in order to account for renamed targets
  form_expanded_targets()

  max_target_length = get_max_anchor_length(TARGETS)
  max_variable_length = get_max_anchor_length(VARIABLES)
  max_anchor_length = max(max_target_length, max_variable_length)
  separator = get_separator(max_anchor_length)

  debug_END()

  # process targets
  if (max_target_length > 0) {
    printf("%s\n%s\n%s\n", separator, HEADER_TARGETS, separator)

    for (indx = 1; indx <= length_array_posix(TARGETS); indx++) { # enforce order
      target = TARGETS[indx]
      description = format_description_data(target,
                                            TARGETS_DESCRIPTION_DATA,
                                            max_anchor_length)
      section = get_associated_section_data(target, TARGETS_SECTION_DATA)
      display_anchor_with_data(target, description, section, max_anchor_length)
    }
  }

  # process variables
  # When all variables are deprecated and DEPRECATED = 0, just a header is displayed.
  if (max_variable_length > 0 && VARS) {
    variables_display_pattern = max_target_length > 0 ? "\n%s\n%s\n%s\n": "%s\n%s\n%s\n"

    printf(variables_display_pattern, separator, HEADER_VARIABLES, separator)
    for (indx = 1; indx <= length_array_posix(VARIABLES); indx++) {
      variable = VARIABLES[indx]
      description = format_description_data(variable,
                                            VARIABLES_DESCRIPTION_DATA,
                                            max_anchor_length)
      section = get_associated_section_data(variable, VARIABLES_SECTION_DATA)
      display_anchor_with_data(variable, description, section, max_anchor_length)
    }
  }
  if (max_target_length > 0 || (max_variable_length > 0 && VARS)) {
    printf("%s\n", separator)
  } else {
    if (number_of_files_processed > 0) {
      printf("There are no documented targets/variables in %s\n", files_processed)
    }
  }

  if (DEBUG) {
    close(DEBUG_FILE)
    print "Debug info written in " DEBUG_FILE
  }
}
