# --------------------------------------------------------------------------------------
# Awk script for Makefile docs (https://github.com/drdv/makefile-doc)
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
  delete DESCRIPTION_DATA
  DESCRIPTION_DATA_INDEX = 0
}

function parse_inline_descriptions(whole_line_string) {
  # I use these nested ifs because in awk, 5 || 0 returns 1 instead of 5
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

  # Here we might overwrite a description associatd with a redefined target -- this is
  # intended.
  TARGET_DESCRIPTION_DATA[target_string] = assemble_description_data()
  forget_descriptions_data()

  # note that section data is associated with a documented target
  if (length(SECTION_DATA) > 0) {
    if (target_string in TARGET_SECTION_DATA) {
      printf("%sRedefining associated section data: %s%s\n",
             COLOR_WARNING_CODE,
             target_string,
             COLOR_RESET_CODE)
    }

    TARGET_SECTION_DATA[target_string] = assemble_section_data()
    forget_section_data()
  }
}

function save_section_data(whole_line_string) {
  SECTION_DATA[SECTION_DATA_INDEX] = whole_line_string
  SECTION_DATA_INDEX++
}

function forget_section_data() {
  delete SECTION_DATA
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

# The input contains the collected description lines (new-line separated). Here we have
# to indent all lines after the first.
function indent_description_data(multiline_description, max_target_length) {
  split(multiline_description, array_of_lines, "\n")

  description = ""
  for (key in array_of_lines) {
    next_line = array_of_lines[key]
    if (description) {
      # FIXME: magic constants
      offset = sprintf("%" max_target_length + 3 "s", "")
      description = description "\n" offset substr(next_line, 4)
    } else {
      description = description next_line
    }
  }
  return description
}

function assemble_description_data() {
  description = ""
  for (key in DESCRIPTION_DATA) {
    description = description DESCRIPTION_DATA[key] "\n"
  }
  return substr(description, 1, length(description) - 1) # remove last \n
}

function assemble_section_data() {
  section = ""
  for (key in SECTION_DATA) {
    section = section SECTION_DATA[key] "\n"
  }
  return substr(section, 1, length(section) - 1)
}

# FIXME: magic constants
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
/^\s*\${0,1}[^.][ a-zA-Z0-9_/%.(){}-]+\s*:/ {
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
      description = indent_description_data(TARGET_DESCRIPTION_DATA[target],
                                            max_target_length)
      section = TARGET_SECTION_DATA[target]

      update_display_parameters(description)
      display_target_with_data(target, description, section, max_target_length)
    }

    if (HEADER) {
      print_footer(separator)
    }
  }
}
