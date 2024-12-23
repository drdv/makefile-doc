# --------------------------------------------------------------------------------------
# Awk script for Makefile docs (https://github.com/drdv/makefile-doc)
#
# ========================================================
# How to use (see the tests for more examples):
# ========================================================
#
# VAR = 1 ## doc of a CLA variable the user might want to know about
#
# ## show this help
# ## can have multi-line description above a target or variable
# ## the AWKPATH env variable should be set for makefile-doc.awk to be found
# help:
# 	@awk -f makefile-doc.awk $(MAKEFILE_LIST)
#
# another-target: ## An inline description (displayed if there are no top descriptions)
# 	@...
#
# ========================================================
# Notes
# ========================================================
# I refer to targets / variables as anchors (for docs/sections).
#
# The inline description of an anchor is ignored if there are descriptions above it.
#
# An anchor is displayed in:
#   COLOR_DEFAULT    if its description starts with ##
#   COLOR_ATTENTION  if its description starts with ##!
#   COLOR_DEPRECATED if its description starts with ##%
#
# In the code, I follow the convention that the name of a variable to which an
# assignment is made in a function should end with _local (because AWK is a bit special
# in that respect).
#
# ========================================================
# Command-line arguments (set using -v var=value)
# ========================================================
# VARS: if 1 (the default) show documented variables, set to 0 to disable (in which
#       case, documented variables are still processed but not displayed)
#
# PADDING: the value should be a single character, the default is space,
#          (to use e.g., a dot instead, pass -v PADDING=".")
#
# DEPRECATED: if 0, hide deprecated anchors, show them otherwise (the default)
#
# OFFSET: number of spaces to offset descriptions from anchors (2 by default)
#
# CONNECTED: if 1 (the default) ignore descriptions followed by an empty line
#
# COLOR_DEFAULT: 34 (blue) by default
#
# COLOR_ATTENTION: 31 (red) by default
#
# COLOR_DEPRECATED: 33 (yellow) by default
#
# COLOR_WARNING: 35 (magenta) by default -- used for warnings
#
# COLOR_SECTION: 32 (green) by default -- used for sections
#
# COLOR_BACKTICKS: 0 (i.e., disabled) by default -- used for text in backticks in
#                  descriptions, set e.g., to 1 to display it in bold
#
# Colors are specified using the parameter in ANSI escape codes, e.g., the parameter for
# blue is the 34 in `\033[34m`.
# --------------------------------------------------------------------------------------

# ========================================================
# Utility functions
# ========================================================
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
    printf("%sRedefined docs of %s: %s%s\n",
           COLOR_WARNING_CODE,
           anchor_type,
           anchor_name,
           COLOR_RESET_CODE)
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
                               anchor,
                               COLOR_RESET_CODE)
    if (PADDING != " ") {
      gsub(/ /, PADDING, formatted_anchor)
    }
    printf("%s%s\n", formatted_anchor, description)
  }
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

# ========================================================

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
#  7. "double-colon" targets are not handled.
#  8. FS = ":" is assumed.
/^ *\${0,1}[^.#][ a-zA-Z0-9_\/%.(){}-]+ *:( |$)/ {
  # look for inline descriptions only if there aren't any descriptions above the target
  if (length_array_posix(DESCRIPTION_DATA) == 0) {
    parse_inline_descriptions($0) # this might modify DESCRIPTION_DATA
  }

  if (length_array_posix(DESCRIPTION_DATA) > 0) {
    TARGETS_INDEX = associate_data_with_anchor($1,
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
/^ *[^.#][a-zA-Z0-9_-]+ *(=|:=|::=|:::=)/ {
  if (length_array_posix(DESCRIPTION_DATA) == 0) {
    parse_inline_descriptions($0) # this might modify DESCRIPTION_DATA
  }

  if (length_array_posix(DESCRIPTION_DATA) > 0) {
    variable_name = parse_variable_name($0)
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
  # FIXME: in the case when all variables are deprecated and DEPRECATED = 0, then
  # max_variable_length > 0 but no variables would be displayed (just a header)
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
  printf("%s\n", separator)
}
