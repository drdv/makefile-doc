# Generate docs for Makefile variables and targets
#
#    File: makefile-doc.awk
#  Author: Dimitar Dimitrov
# License: Apache-2.0
# Project: https://github.com/drdv/makefile-doc
# Version: v0.5
#
# Usage (see project README.md for more details):
#   awk [-v option=value] -f makefile-doc.awk [Makefile ...]
#
# Options (set using -v option=value, possible values given in {...}, (.) is default):
#   * VARS: {0, (1)} 1 show documented variables; 0 don't show
#   * PADDING: {(" "), ".", ...} a single padding character between anchors and docs
#   * DEPRECATED: {0, (1)} 1 show deprecated anchors; 0 don't show
#   * OFFSET: {0, 1, (2), ...} number of spaces to offset docs from anchors
#   * CONNECTED: {0, (1)} 1 ignore docs followed by an empty line; 0 join them
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
}

function forget_descriptions_data() {
  delete DESCRIPTION_DATA
  DESCRIPTION_DATA_INDEX = 1
}

function parse_inline_descriptions(whole_line_string) {
  if (match(whole_line_string, / *(##!|##%|##)/)) {
    inline_string_local = substr(whole_line_string, RSTART)
    sub(/^ */, "", inline_string_local)
    save_description_data(inline_string_local)
  }
}

function parse_variable_name(whole_line_string) {
  split(whole_line_string, array_whole_line, "(=|:=|::=|:::=)")
  variable_name_local = array_whole_line[1]
  sub(/[ ]+/, "", variable_name_local)
  return variable_name_local
}

function associate_data_with_anchor(anchor_name,
                                    anchors,
                                    anchors_index,
                                    anchors_description_data,
                                    anchors_section_data,
                                    anchor_type) {
  if (anchor_name in anchors_description_data) {
    # omit variable related warnings when they are not displayed
    if (anchor_type != "variable" || VARS) {
      printf("%sRedefined docs of %s: %s%s\n",
             COLOR_WARNING_CODE,
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
      printf("%sRedefining associated section data: %s%s\n",
             COLOR_WARNING_CODE,
             anchor_name,
             COLOR_RESET_CODE)
    }

    anchors_section_data[anchor_name] = assemble_section_data()
    forget_section_data()
  }
  return anchors_index
}

function save_section_data(string) {
  SECTION_DATA[SECTION_DATA_INDEX] = string
  SECTION_DATA_INDEX++
}

function forget_section_data() {
  delete SECTION_DATA
  SECTION_DATA_INDEX = 1
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
    len_local = length(anchor_local)
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
  sub(/(##|##!|##%)/, "", description_local) # strip the tag (keep the leading space)
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
    printf("Something went wrong! %s", description)
    exit 1
  }
}

function display_anchor_with_data(anchor, description, section, len_anchors) {
  # Display the section (if there is one) even if it is anchored to a deprecated anchor
  # that is not to be displayed.
  if (section) {
    printf("%s%s%s\n", COLOR_SECTION_CODE, section, COLOR_RESET_CODE)
  }

  if (DISPLAY_PARAMS["show"]) {
    DISPLAY_PATTERN = "%s%-" len_anchors "s%s"
    formatted_anchor = sprintf(DISPLAY_PATTERN,
                               DISPLAY_PARAMS["color"],
                               format_anchor_name(anchor),
                               COLOR_RESET_CODE)
    if (PADDING != " ") {
      gsub(/ /, PADDING, formatted_anchor)
    }
    printf("%s%s\n", formatted_anchor, description)
  }
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
    printf "  VARS: %s\n", VARS
    printf "  PADDING: \"%s\"\n", PADDING
    printf "  DEPRECATED: %s\n", DEPRECATED
    printf "  OFFSET: %s\n", OFFSET
    printf "  CONNECTED: %s\n", CONNECTED
    printf "  COLORS: "
    printf "%sDEFAULT%s, ", COLOR_DEFAULT_CODE, COLOR_RESET_CODE
    printf "%sATTENTION%s, ", COLOR_ATTENTION_CODE, COLOR_RESET_CODE
    printf "%sDEPRECATED%s, ", COLOR_DEPRECATED_CODE, COLOR_RESET_CODE
    printf "%sSECTION%s, ", COLOR_SECTION_CODE, COLOR_RESET_CODE
    printf "%sWARNING%s, ", COLOR_WARNING_CODE, COLOR_RESET_CODE
    printf "%sBACKTICKS%s\n", COLOR_BACKTICKS_CODE, COLOR_RESET_CODE
}

# Initialize global variables.
BEGIN {
  FS = ":" # set the field separator

  initialize_colors()

  VARS = VARS == "" ? 1 : VARS
  PADDING = PADDING == "" ? " " : PADDING
  DEPRECATED = DEPRECATED == "" ? 1 : DEPRECATED
  OFFSET = OFFSET == "" ? 2 : OFFSET
  CONNECTED = CONNECTED == "" ? 1 : CONNECTED
  if (length(PADDING) != 1) {
    printf("%sPADDING should have length 1%s\n", COLOR_WARNING_CODE, COLOR_RESET_CODE)
    exit 1
  }

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
}

FNR == 1 {
  number_of_files_processed++
}

# Capture the line if it is a description (but not section).
/^ *##[^@]/ {
  description_string = $0
  sub(/^ */, "", description_string)
  save_description_data(description_string)
}

# Flush accumulated descriptions if followed by an empty line.
/^$/ {
  if (CONNECTED) {
    forget_descriptions_data()
  }
}

# New section (all lines in a multi-line sections should start with ##@)
/^ *##@/ {
  section_string = $0
  sub(/ *##@/, "", section_string) # strip the tags (they are not needed anymore)
  save_section_data(section_string)
}

# Process target, whose name
#  1. may start with spaces
#  2. but not with a # or with a dot (in order to jump over e.g., .PHONY)
#  3. and can have spaces before the final colon.
#  4. There can be multiple space-separated targets on one line (they are captured
#     together).
#  5. Targets of the form $(TARGET-NAME) and ${TARGET-NAME} are detected, even though
#     they are of limited value as we don't have access to the value of the TARGET-NAME
#     variable.
#  6. After the final colon we require either at least one space of end of line -- this
#     is because otherwise we would match VAR := value.
#  7. FS = ":" is assumed.
#
# Note: I have to use *(:|::) instead of *{1,2} because the latter doesn't work in mawk.
#
/^ *[^.#][ a-zA-Z0-9$_\/%.(){}-]* *&?(:|::)( |$)/ {
  # look for inline descriptions only if there aren't any descriptions above the target
  if (length_array_posix(DESCRIPTION_DATA) == 0) {
    parse_inline_descriptions($0) # this might modify DESCRIPTION_DATA
  }

  if (length_array_posix(DESCRIPTION_DATA) > 0) {
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

    TARGETS_INDEX = associate_data_with_anchor(trim_start_end_spaces(target_name),
                                               TARGETS,
                                               TARGETS_INDEX,
                                               TARGETS_DESCRIPTION_DATA,
                                               TARGETS_SECTION_DATA,
                                               "target")
  }
}

# Process variable, whose name
#  1. may start with spaces
#  2. but not with a # or with a dot (in order to jump over e.g., .DEFAULT_GOAL)
#  3. can be followed by spaces and one of four assignment operators =, :=, ::=, :::=
/^ *[^.#][a-zA-Z0-9_-]* *(=|:=|::=|:::=)/ {
  if (length_array_posix(DESCRIPTION_DATA) == 0) {
    parse_inline_descriptions($0) # this might modify DESCRIPTION_DATA
  }

  if (length_array_posix(DESCRIPTION_DATA) > 0) {
    variable_name = trim_start_end_spaces(parse_variable_name($0))
    VARIABLES_INDEX = associate_data_with_anchor(variable_name,
                                                 VARIABLES,
                                                 VARIABLES_INDEX,
                                                 VARIABLES_DESCRIPTION_DATA,
                                                 VARIABLES_SECTION_DATA,
                                                 "variable")
  }
}

# Display results (except for warnings all stdout is here).
END {
  max_target_length = get_max_anchor_length(TARGETS)
  max_variable_length = get_max_anchor_length(VARIABLES)
  max_anchor_length = max(max_target_length, max_variable_length)
  separator = get_separator(max_anchor_length)

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
    printf("\n%s\n%s\n%s\n", separator, HEADER_VARIABLES, separator)
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
      print("There are no documented targets/variables.")
    }
  }
}
