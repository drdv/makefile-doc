# --------------------------------------------------------------------------------------
# AWK script used to generate Makefile target descriptions.
#
# ========================================================
# How to use (see the tests for more examples):
# ========================================================
# ## show this help
# ## can have multi-line description above a target
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
# Target inline description is ignored if there are descriptions above it.
#
# Target is displayed in:
#   COLOR_DEFAULT    if its description starts with ##
#   COLOR_ATTENTION  if its description starts with ##!
#   COLOR_DEPRECATED if its description starts with ##%
#
# ========================================================
# Command-line arguments (set using the -v flag)
# ========================================================
# COLOR_DEFAULT: 34 by default, i.e., blue - only the parameter portion of the ANSI
#                escape code should be passed, e.g., the parameter for blue is the 34 in
#                \033[34m
#
# COLOR_ATTENTION: 31 by default, i.e., red
#
# COLOR_DEPRECATED: 33 by default, i.e., yellow
#
# COLOR_WARNING: 35 by default, i.e., magenta (used for warnings)
#
# COLOR_SECTION: 32 by default, i.e., green (used for sections)
#
# HEADER: if 1, display header and footer
#
# DEPRECATED: if 0, hide deprecated targets, show them otherwise (the default)
#
# CONNECTED: if 1 (the default) ignore descriptions followed by an empty line
#
# PADDING: the value should be a single character, the default is space,
#          (to use e.g., a dot instead, pass -v PADDING=".")
# --------------------------------------------------------------------------------------

# ========================================================
# Utility functions
# ========================================================
function save_description_data(whole_line_string) {
  sub(/^ +/, "", whole_line_string) # strip leading spaces
  DESCRIPTION_DATA[DESCRIPTION_DATA_INDEX] = whole_line_string
  DESCRIPTION_DATA_INDEX++
}

function forget_descriptions_data() {
  for (key in DESCRIPTION_DATA) {
    delete DESCRIPTION_DATA[key]
  }
  DESCRIPTION_DATA_INDEX = 0
}

# Forget descriptions that have already been associated with a target when it is
# redefined (i.e., overridden). For a target to be overriden, another *documented*
# target with the same name should exist. Because if the redefining target has no docs
# then we would simply skip it. So while `make` itself would issue a warning that a
# target has been redefined, there is nothing to do from the point of view of our
# documentation system.
function forget_associated_description_data(target_string) {
  for (key in TARGET_DESCRIPTION_DATA[target_string]) {
    delete TARGET_DESCRIPTION_DATA[target_string][key]
  }
}

function forget_associated_section_data(target_string) {
  for (key in TARGET_SECTION_DATA[target_string]) {
    delete TARGET_SECTION_DATA[target_string][key]
  }
}

function parse_inline_descriptions(whole_line_string) {
  # I use these nested ifs because in AWK, 5 || 0 returns 1 instead of 5
  inline_description_index = index(whole_line_string, " ## ")
  if (!inline_description_index) {
    inline_description_index = index(whole_line_string, " ##! ")
    if (!inline_description_index) {
      inline_description_index = index(whole_line_string, " ##% ")
    }
  }

  if (inline_description_index) {
    save_description_data(substr(whole_line_string, inline_description_index + 1))
  }
}

function associate_data_with_target(target_string) {
  if (target_string in TARGET_DESCRIPTION_DATA) {
    printf("%sRedefined docs of target: %s%s\n",
           COLOR_WARNING_CODE,
           target_string,
           COLOR_RESET_CODE)
  } else {
    TARGETS_ORDER[TARGETS_ORDER_INDEX] = target_string
    TARGETS_ORDER_INDEX++
  }

  forget_associated_description_data(target_string)
  for (key in DESCRIPTION_DATA) {
    TARGET_DESCRIPTION_DATA[target_string][key] = DESCRIPTION_DATA[key]
  }

  forget_descriptions_data() # forget descriptions that were associated with the target

  # note that section data can be associated only with a documented target
  if (length(SECTION_DATA) > 0) {

    if (length(TARGET_SECTION_DATA[target_string]) > 0) {
      printf("%sRedefining associated section data: %s%s\n",
             COLOR_WARNING_CODE,
             target_string,
             COLOR_RESET_CODE)
    }

    forget_associated_section_data(target_string)
    for (key in SECTION_DATA) {
      TARGET_SECTION_DATA[target_string][key] = SECTION_DATA[key]
    }
    forget_section_data()
  }
}

function save_section_data(whole_line_string) {
  SECTION_DATA[SECTION_DATA_INDEX] = whole_line_string
  SECTION_DATA_INDEX++
}

function forget_section_data() {
  for (key in SECTION_DATA) {
    delete SECTION_DATA[key]
  }
  SECTION_DATA_INDEX = 0
}

function get_max_target_length() {
  max_target_length = 0
  for (ind in TARGETS_ORDER) {
    target = TARGETS_ORDER[ind]
    n = length(target)
    if (n > max_target_length) {
      max_target_length = n
    }
  }
  return max_target_length
}

function print_header(max_target_length) {
  header = "Available targets:"
  lh = length(header)
  separator = sprintf("%*s", max_target_length < lh ? lh : max_target_length, "")
  gsub(/ /, "-", separator) # gsub works inplace

  printf("%s\n%s\n%s\n", separator, header, separator)
  return separator
}

function print_footer(separator) {
  printf("%s\n", separator)
}

function assemble_target_description_data(target) {
  description = ""
  for (key in TARGET_DESCRIPTION_DATA[target]) {
    next_line = TARGET_DESCRIPTION_DATA[target][key]
    if (description) {
      with_offset = sprintf("%" max_target_length + 3 "s", "") substr(next_line, 4)
      description = description "\n" with_offset
    } else {
      description = description TARGET_DESCRIPTION_DATA[target][key]
    }
  }
  return description
}

function assemble_target_section_data(target) {
  section = ""
  for (key in TARGET_SECTION_DATA[target]) {
    next_line = TARGET_SECTION_DATA[target][key]
    section = section next_line "\n"
  }
  return substr(section, 1, length(section) - 1) # remove last \n
}

function update_display_parameters(description) {
  if (substr(description, 3, 1) == "!") {
    DISPLAY_PARAMS["color"] = COLOR_ATTENTION_CODE
    DISPLAY_PARAMS["offset"] = 4
    DISPLAY_PARAMS["show"] = 1
  } else if (substr(description, 3, 1) == "%") {
    DISPLAY_PARAMS["color"] = COLOR_DEPRECATED_CODE
    DISPLAY_PARAMS["offset"] = 4
    DISPLAY_PARAMS["show"] = DEPRECATED
  }
  else {
    DISPLAY_PARAMS["color"] = COLOR_DEFAULT_CODE
    DISPLAY_PARAMS["offset"] = 3
    DISPLAY_PARAMS["show"] = 1
  }
}

function display_target_with_data(target, description, section, max_target_length) {

  # Display the section (if there is one) even if it is anchored to a deprecated target
  # that is not to be displayed.
  if (section) {
    printf("%s%s%s\n", COLOR_SECTION_CODE, section, COLOR_RESET_CODE)
  }

  if (DISPLAY_PARAMS["show"]) {
    DISPLAY_PATTERN = "%s%-" max_target_length "s  %s"
    t = sprintf(DISPLAY_PATTERN, DISPLAY_PARAMS["color"], target, COLOR_RESET_CODE)
    if (PADDING != " ") {
      gsub(/ /, PADDING, t)
    }
    printf("%s%s\n", t, substr(description, DISPLAY_PARAMS["offset"]))
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
  COLOR_RESET_CODE = ansi_color(0)
}

# ========================================================

# Initialize global variables.
BEGIN {
  FS = ":" # set the field separator

  initialize_colors()

  HEADER = HEADER == "" ? 1 : HEADER
  DEPRECATED = DEPRECATED == "" ? 1 : DEPRECATED
  CONNECTED = CONNECTED == "" ? 1 : CONNECTED
  PADDING = PADDING == "" ? " " : PADDING
  if (length(PADDING) != 1) {
    printf("%sPADDING should have length 1%s\n", COLOR_WARNING_CODE, COLOR_RESET_CODE)
    exit 1
  }

  # initialize global arrays (i.e., hash tables) for clarity
  split("", TARGET_DESCRIPTION_DATA) # map target name to description (no order)
  split("", TARGET_SECTION_DATA)     # map target name to section data (use as anchor)
  split("", TARGETS_ORDER)           # map index to target name (to keep track of order)
  TARGETS_ORDER_INDEX = 0

  split("", DESCRIPTION_DATA) # map index to line in description data for targets
  DESCRIPTION_DATA_INDEX = 0

  split("", SECTION_DATA) # map index to line in section data
  SECTION_DATA_INDEX = 0

  split("", DISPLAY_PARAMS)
}

# Capture the line if it is a description.
/^ *##/ {
  save_description_data($0)
}

# Flush accumulated descriptions if followed by an empty line.
/^$/ {
  if (CONNECTED) {
    forget_descriptions_data()
  }
}

# New section
# Section description should start at the beginning of the line. All lines in a
# multi-line description should start with ##@.
/^##@/ {
  save_section_data(substr($0, 4))
}

# Process target.
# The name of a target may start with a space, but not with a dot (in order to jump over
# e.g., .PHONY) and can have spaces before the final colon. There can be multiple space
# separated targets on one line (they are captured together). The regex detects targets
# of the form $(TARGET-NAME) and ${TARGET-NAME} even though they are of limited value as
# we don't have access to the value of the TARGET-NAME variable. "double-colon" targets
# are not handled. The regex requires to use FS = ":".
/^\s*\$*[^.][ a-zA-Z0-9_/%.(){}-]+\s*:/ {
  # look for inline descriptions only if there aren't any descriptions above the target
  if (length(DESCRIPTION_DATA) == 0) {
    parse_inline_descriptions($0)
  }

  if (length(DESCRIPTION_DATA) > 0) {
    associate_data_with_target($1)
  }
}

# Display results.
END {
  max_target_length = get_max_target_length()
  if (max_target_length > 0) {
    if (HEADER) {
      separator = print_header()
    }

    for (ind in TARGETS_ORDER) {
      target = TARGETS_ORDER[ind]
      description = assemble_target_description_data(target)
      section = assemble_target_section_data(target)

      update_display_parameters(description)
      display_target_with_data(target, description, section, max_target_length)
    }

    if (HEADER) {
      print_footer(separator)
    }
  }
}
