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
# I follow the convention that the name of a variable assignet to in a function should
# end with _local (because AWK is a bit special in that respect).
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
# COLOR_BACKTICKS: 0 by default i.e., disabled (used for text in backticks in
#                  descriptions), set e.g., to 1 to display it in bold
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
# in POSIX-compliant AWK the length function works on strings but not on arrays
function length_array_posix(array) {
  array_numb_elements_local = 0
  for (counter_local in array) {
    array_numb_elements_local++
  }
  return array_numb_elements_local
}

function get_description_tag(string) {
  if (match(string, /^ *(##!|##%|##)/)) {
    tag_local = substr(string, RSTART, RLENGTH)
    sub(/ */, "", tag_local)
    return tag_local
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
    inline_string_local = substr(whole_line_string, RSTART)
    sub(/^ */, "", inline_string_local)
    save_description_data(inline_string_local)
  }
}

function associate_data_with_target(target_string) {
  if (target_string in TARGETS_DESCRIPTION_DATA) {
    printf("%sRedefined docs of target: %s%s\n",
           COLOR_WARNING_CODE,
           target_string,
           COLOR_RESET_CODE)
  } else {
    TARGETS[TARGETS_INDEX] = target_string
    TARGETS_INDEX++
  }

  # Here we might overwrite a description associatd with a redefined target -- this is
  # intended.
  TARGETS_DESCRIPTION_DATA[target_string] = assemble_description_data()
  forget_descriptions_data()

  # note that section data is associated only with documented targets
  if (length_array_posix(SECTION_DATA) > 0) {
    if (target_string in TARGETS_SECTION_DATA) {
      printf("%sRedefining associated section data: %s%s\n",
             COLOR_WARNING_CODE,
             target_string,
             COLOR_RESET_CODE)
    }

    TARGETS_SECTION_DATA[target_string] = assemble_section_data()
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

function get_associated_section_data(target) {
  if (target in TARGETS_SECTION_DATA) {
    return TARGETS_SECTION_DATA[target]
  }
  return 0 # means that there is no associated section data with this target
}

function get_max_target_length() {
  max_len_local = 0
  for (key_local in TARGETS) { # order is not important
    target_local = TARGETS[key_local]
    len_local = length(target_local)
    if (len_local > max_len_local) {
      max_len_local = len_local
    }
  }
  return max_len_local
}

function print_header(len_targets) {
  len_local = length(HEADER)
  separator_local = sprintf("%*s", len_targets<len_local ? len_local : len_targets, "")
  gsub(/ /, "-", separator_local)

  printf("%s\n%s\n%s\n", separator_local, HEADER, separator_local)
  return separator_local
}

function print_footer(separator) {
  printf("%s\n", separator)
}

function substitute_backticks_pattern(string) {
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
    return substitute_backticks_pattern(description)
  }
  return description
}

# The input contains the (\n separated) description lines associated with one target.
# Each line starts with a tag (##, ##! or ##%). Here we have to strip them and to
# introduce indentation for lines below the first one.
function format_description_data(target, len_targets) {
  # the automatically-assigned indexes during the split are: 1, ..., #lines
  split(TARGETS_DESCRIPTION_DATA[target], array_of_lines_local, "\n")

  # the tag for the first line is stripped below (after the parameter update)
  description_local = sprintf("%" OFFSET "s", "") array_of_lines_local[1]

  for (indx_local = 2;
       indx_local <= length_array_posix(array_of_lines_local);
       indx_local++) {
    line_local = array_of_lines_local[indx_local]
    sub(/^(##|##!|##%)/, "", line_local) # strip the tag
    description_local = sprintf("%s\n%s%s",
                                description_local,
                                sprintf("%" OFFSET + len_targets "s", ""),
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
  tag_local = get_description_tag(description)
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

function display_target_with_data(target, description, section, len_targets) {
  # Display the section (if there is one) even if it is anchored to a deprecated target
  # that is not to be displayed.
  if (section) {
    printf("%s%s%s\n", COLOR_SECTION_CODE, section, COLOR_RESET_CODE)
  }

  if (DISPLAY_PARAMS["show"]) {
    DISPLAY_PATTERN = "%s%-" len_targets "s%s"
    formatted_target = sprintf(DISPLAY_PATTERN,
                               DISPLAY_PARAMS["color"],
                               target,
                               COLOR_RESET_CODE)
    if (PADDING != " ") {
      gsub(/ /, PADDING, formatted_target)
    }
    printf("%s%s\n", formatted_target, description)
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

  # map target name to description (order is not important)
  split("", TARGETS_DESCRIPTION_DATA)

  # map target name to section data (order is not important)
  # a section uses a targtet as an anchor
  split("", TARGETS_SECTION_DATA)

  # map index to target name (order is important)
  split("", TARGETS)
  TARGETS_INDEX = 1

  # map index to line in description data (to be associated with the next target)
  split("", DESCRIPTION_DATA)
  DESCRIPTION_DATA_INDEX = 1

  # map index to line in section data (to be associated with the next target)
  split("", SECTION_DATA)
  SECTION_DATA_INDEX = 1

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
  if (length_array_posix(DESCRIPTION_DATA) == 0) {
    parse_inline_descriptions($0)
  }

  if (length_array_posix(DESCRIPTION_DATA) > 0) {
    associate_data_with_target($1)
  }
}

# Display results.
END {
  max_target_length = get_max_target_length()
  if (max_target_length > 0) {
    if (HEADER) {
      separator = print_header(max_target_length)
    }

    # `for (indx in TARGETS)` cannot be used because we need to enforce order.
    # While gawk seems to sort things nicely, the order e.g., in mawk is undefined:
    # https://invisible-island.net/mawk/manpage/mawk.html#h3-6_-Arrays
    for (indx = 1; indx <= length_array_posix(TARGETS); indx++) {
      target = TARGETS[indx]
      description = format_description_data(target, max_target_length)
      section = get_associated_section_data(target)
      display_target_with_data(target, description, section, max_target_length)
    }

    if (HEADER) {
      print_footer(separator)
    }
  }
}
