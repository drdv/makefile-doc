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
# Command-line arguments (set using -v var=value)
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
# COLOR_BACKTICKS: 1 by default i.e., bold (used for text in backticks in
#                  descriptions). Currenlty this feature is not used as only GNU Awk
#                  implements gensub.
#
# OFFSET: number of spaces to offset descriptions from targets (2 by default)
#
# HEADER: set header text to display, if 0 skip the header (and footer)
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
function get_description_tag(string) {
  if (match(string, /^ *(##!|##%|##)/)) {
    tag = substr(string, RSTART, RLENGTH)
    sub(/ */, "", tag)
    return tag
  } else {
    return 0
  }
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
    string = substr(whole_line_string, RSTART)
    sub(/^ */, "", string)
    save_description_data(string)
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

  # note that section data is associated only with documented targets
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

function save_section_data(string) {
  SECTION_DATA[SECTION_DATA_INDEX] = string
  SECTION_DATA_INDEX++
}

function forget_section_data() {
  delete SECTION_DATA
  SECTION_DATA_INDEX = 1
}

function get_max_target_length() {
  max_target_length = 0
  for (key in TARGETS_ORDER) { # order is not important
    target = TARGETS_ORDER[key]
    n = length(target)
    if (n > max_target_length) {
      max_target_length = n
    }
  }
  return max_target_length
}

function print_header(max_target_length) {
  len = length(HEADER)
  separator = sprintf("%*s", max_target_length < len ? len : max_target_length, "")
  gsub(/ /, "-", separator)

  printf("%s\n%s\n%s\n", separator, HEADER, separator)
  return separator
}

function print_footer(separator) {
  printf("%s\n", separator)
}

function colorize_description_backticks(description) {
  #replace_with = COLOR_BACKTICKS_CODE "\\1" COLOR_RESET_CODE
  #return gensub(/`([^`]*)`/, replace_with, "g", description) # only for gawk
  return description
}

# The input contains the (\n separated) description lines associated with one target.
# Each line starts with a tag (##, ##! or ##%). Here we have to strip them and to
# introduce indentation for lines below the first one.
function format_description_data(target, max_target_length) {
  # the automatically-assigned indexes during the split are: 1, ..., #lines
  split(TARGET_DESCRIPTION_DATA[target], array_of_lines, "\n")

  # the tag for the first line is stripped below (after the parameter update)
  description = sprintf("%" OFFSET "s", "") array_of_lines[1]

  offset = OFFSET + max_target_length
  for (indx = 2; indx <= length(array_of_lines); indx++) {
    next_line = array_of_lines[indx]
    sub(/^(##|##!|##%)/, "", next_line) # strip the tag
    description = description "\n" sprintf("%" offset "s", "") next_line
  }

  update_display_parameters(description)
  sub(/(##|##!|##%)/, "", description) # strip the tag (but keep the leading space)
  return colorize_description_backticks(description)
}

function assemble_description_data() {
  description = DESCRIPTION_DATA[1]
  for (indx = 2; indx <= length(DESCRIPTION_DATA); indx++) {
    description = description "\n" DESCRIPTION_DATA[indx]
  }
  return description
}

function assemble_section_data() {
  section = SECTION_DATA[1]
  for (indx = 2; indx <= length(SECTION_DATA); indx++) {
    section = section "\n" SECTION_DATA[indx]
  }
  return section
}

function update_display_parameters(description) {
  tag = get_description_tag(description)
  if (tag == "##!") {
    DISPLAY_PARAMS["color"] = COLOR_ATTENTION_CODE
    DISPLAY_PARAMS["show"] = 1
  } else if (tag == "##%") {
    DISPLAY_PARAMS["color"] = COLOR_DEPRECATED_CODE
    DISPLAY_PARAMS["show"] = DEPRECATED
  }
  else if (tag == "##") {
    DISPLAY_PARAMS["color"] = COLOR_DEFAULT_CODE
    DISPLAY_PARAMS["show"] = 1
  } else {
    printf("Something went wrong! %s", description)
    exit 1
  }
}

function display_target_with_data(target, description, section, max_target_length) {
  # Display the section (if there is one) even if it is anchored to a deprecated target
  # that is not to be displayed.
  if (section) {
    printf("%s%s%s\n", COLOR_SECTION_CODE, section, COLOR_RESET_CODE)
  }

  if (DISPLAY_PARAMS["show"]) {
    DISPLAY_PATTERN = "%s%-" max_target_length "s%s"
    t = sprintf(DISPLAY_PATTERN, DISPLAY_PARAMS["color"], target, COLOR_RESET_CODE)
    if (PADDING != " ") {
      gsub(/ /, PADDING, t)
    }
    printf("%s%s\n", t, description)
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
  COLOR_BACKTICKS_CODE = ansi_color(COLOR_BACKTICKS == "" ? 1 : COLOR_BACKTICKS)
  COLOR_RESET_CODE = ansi_color(0)
}

# ========================================================

# Initialize global variables.
BEGIN {
  FS = ":" # set the field separator

  initialize_colors()

  OFFSET = OFFSET == "" ? 2 : OFFSET
  HEADER = HEADER == "" ? "Available targets:" : HEADER
  DEPRECATED = DEPRECATED == "" ? 1 : DEPRECATED
  CONNECTED = CONNECTED == "" ? 1 : CONNECTED
  PADDING = PADDING == "" ? " " : PADDING
  if (length(PADDING) != 1) {
    printf("%sPADDING should have length 1%s\n", COLOR_WARNING_CODE, COLOR_RESET_CODE)
    exit 1
  }

  # initialize global arrays (i.e., hash tables) for clarity
  # index variables start from 1 because this is the standard in awk
  split("", TARGET_DESCRIPTION_DATA) # map target name to description (no order)
  split("", TARGET_SECTION_DATA)     # map target name to section data (use as anchor)
  split("", TARGETS_ORDER)           # map index to target name (to keep track of order)
  TARGETS_ORDER_INDEX = 1

  split("", DESCRIPTION_DATA) # map index to line in description data for targets
  DESCRIPTION_DATA_INDEX = 1

  split("", SECTION_DATA) # map index to line in section data
  SECTION_DATA_INDEX = 1

  split("", DISPLAY_PARAMS)
}

# Capture the line if it is a description (but not section).
/^ *##[^@]/ {
  string = $0
  sub(/^ */, "", string)
  save_description_data(string)
}

# Flush accumulated descriptions if followed by an empty line.
/^$/ {
  if (CONNECTED) {
    forget_descriptions_data()
  }
}

# New section (all lines in a multi-line sections should start with ##@)
/^ *##@/ {
  string = $0
  sub(/ *##@/, "", string) # strip the tags (they are not needed anymore)
  save_section_data(string)
}

# Process target.
# The name of a target may start with a space, but not with a dot (in order to jump over
# e.g., .PHONY) and can have spaces before the final colon. There can be multiple space
# separated targets on one line (they are captured together). The regex detects targets
# of the form $(TARGET-NAME) and ${TARGET-NAME} even though they are of limited value as
# we don't have access to the value of the TARGET-NAME variable. "double-colon" targets
# are not handled. After the final colon we require either one space of end of line --
# this is because otherwise we would match VAR := value. The regex assumes FS = ":".
/^ *\${0,1}[^.][ a-zA-Z0-9_\/%.(){}-]+ *:( |$)/ {
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

    # I cannot use `for (indx in TARGETS_ORDER)` because we need to enforce order.
    # While gawk seems to sort things nicely, the order e.g., in mawk is undefined:
    # https://invisible-island.net/mawk/manpage/mawk.html#h3-6_-Arrays
    #
    # A particuliarity of awk: here I cannot use a variable named indx to loop over the
    # integers because the loop calls format_description_data where indx is incremented
    # in a loop :) so I choose a different name here.
    for (k = 1; k <= length(TARGETS_ORDER); k++) {
      target = TARGETS_ORDER[k]
      description = format_description_data(target, max_target_length)
      section = TARGET_SECTION_DATA[target]
      display_target_with_data(target, description, section, max_target_length)
    }

    if (HEADER) {
      print_footer(separator)
    }
  }
}
