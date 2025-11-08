#!/usr/bin/awk -f
# Generate docs for Makefile variables and targets
#
#    File: makefile-doc.awk
#  Author: Dimitar Dimitrov
# License: Apache-2.0
# Project: https://github.com/drdv/makefile-doc
# Version: v1.3
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
#   + DEBUG: {(0), 1} output debug info (in an org-mode format)
#   + DEBUG_FILE: debug info file
#   + TARGETS_REGEX: regex for matching targets
#   + VARIABLES_REGEX: regex for matching variables
#   * VARS: {0, (1)} show documented variables
#   * PADDING: {(" "), ".", ...} a single padding character between anchors and docs
#   * DEPRECATED: {0, (1)} show deprecated anchors
#   * OFFSET: {0, 1, (2), ...} number of spaces to offset docs from anchors
#   * CONNECTED: {0, (1)} ignore docs followed by an empty line
#   * see as well the color codes below
#
# Color codes (https://en.wikipedia.org/wiki/ANSI_escape_code):
#   * COLOR_DEFAULT: (34) blue
#   * COLOR_ATTENTION: (31) red
#   * COLOR_DEPRECATED: (33) yellow
#   * COLOR_SECTION: (32) green
#   * COLOR_WARNING: (35) magenta -- currently not used
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
#   which we might want to rename in addition to adding a list of expanded targets to
#   the documentation. The format of a single substitution is
#   [<p1:v1,...>]NAME[:LABEL]:[VALUES]
#   + NAME is the name of the variable/target to substitute in the documentation
#   + LABEL is an optional label for renaming the variable/target
#   + VALUES are optional space-separated values to include (a comma can appear as a
#     part of a value if it is escaped, i.e., \\,)
#   + <p1:v1,...> are optional, comma-separated, key-value pairs with parameters
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
#     %* patterns, some kinds of regex etc.
#   + Notes on the arrays in the code:
#     Order is important for: DESCRIPTION_DATA, SECTION_DATA, TARGETS, VARIABLES and
#     each of them has an associated *_INDEX integer variable. For all other arrays
#     order is irrelevant. The key ones are:
#     + DISPLAY_PARAMS
#     + TARGETS_DESCRIPTION_DATA, TARGETS_SECTION_DATA
#     + VARIABLES_DESCRIPTION_DATA, VARIABLES_SECTION_DATA
#     + SUB_LABEL, SUB_PARAMS, SUB_VALUES, SUB_PARAMS_DEFAULTS, SUB_PARAMS_CURRENT

function max(var1, var2) {
  if (var1 >= var2) {
    return var1
  }
  return var2
}

function min(var1, var2) {
  if (var1 <= var2) {
    return var1
  }
  return var2
}

function repeated_string(string, n, #locals
                         s) {
  s = sprintf("%" n "s", "")
  if (string) {
    gsub(/ /, string, s)
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

# updates the array sorted_keys with the sorted keys of array
function sort_keys(array, sorted_keys, #locals
                   n, i, j, key, tmp) {
  delete sorted_keys

  n = 0
  for (key in array) {
    sorted_keys[++n] = key
  }

  # bubble sort sorted_keys (it is used only for producing debug info)
  for(i=1; i<n; i++) {
    for(j=1; j<=n-i; j++) {
      if(sorted_keys[j] > sorted_keys[j+1]) {
        tmp = sorted_keys[j];
        sorted_keys[j] = sorted_keys[j+1];
        sorted_keys[j+1] = tmp
      }
    }
  }
  return n
}

function join(array, delimiter, #locals
              string, k) {
  string = ""
  for (k=1; k<=length_array_posix(array); k++) {
    if (k == 1) {
      string = array[k]
    } else {
      string = string delimiter array[k]
    }
  }
  return string
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
  DESCRIPTION_DATA[DESCRIPTION_DATA_INDEX] = string
  DESCRIPTION_DATA_INDEX++

  debug(DEBUG_INDENT_STACK " save_description_data")
  debug_indent_down()
  debug_array(DESCRIPTION_DATA, DESCRIPTION_DATA_INDEX, "DESCRIPTION_DATA", "")
  debug_indent_up()
}

function forget_descriptions_data() {
  delete DESCRIPTION_DATA
  DESCRIPTION_DATA_INDEX = 1

  debug(DEBUG_INDENT_STACK " forget_descriptions_data")
  debug_indent_down()
  debug_array(DESCRIPTION_DATA, DESCRIPTION_DATA_INDEX, "DESCRIPTION_DATA", "")
  debug_indent_up()
}

function parse_inline_descriptions(whole_line_string, #locals
                                   inline_string) {
  debug(DEBUG_INDENT_STACK " parse_inline_descriptions")
  debug_indent_down()
  if (match(whole_line_string, / *(##!|##%|##)/)) {
    inline_string = substr(whole_line_string, RSTART)
    sub(/^ */, "", inline_string)
    save_description_data(inline_string)
  }
  debug_indent_up()
}

function parse_variable_name(whole_line_string, #locals
                             array_whole_line, variable_name, k) {
  split(whole_line_string, array_whole_line, ASSIGNMENT_OPERATORS_PATTERN)
  variable_name = array_whole_line[1]

  # here we need to preserve order in order to remove unexport and not just export
  for (k=1;
       k<=length_array_posix(VARIABLE_QUALIFIERS);
       k++) {
    gsub(VARIABLE_QUALIFIERS[k], "", variable_name)
  }
  sub(/[ ]+/, "", variable_name)
  return variable_name
}

# it would be nice to make the debugging code less intrusive
function associate_data_with_anchor(anchor_name,
                                    anchors,
                                    anchors_index,
                                    anchors_description_data,
                                    anchors_section_data,
                                    anchor_type) {
  debug(sprintf("%s debug_associate_data_with_%s (INITIAL): %s",
                DEBUG_INDENT_STACK,
                anchor_type,
                anchor_name))
  debug_indent_down()
  debug_array(anchors, anchors_index, "anchors", anchor_type)
  debug_dict(anchors_description_data, "anchors_description_data", anchor_type)
  debug_dict(anchors_section_data, "anchors_section_data", anchor_type)
  debug_array(DESCRIPTION_DATA, DESCRIPTION_DATA_INDEX, "DESCRIPTION_DATA", "")
  debug_array(SECTION_DATA, SECTION_DATA_INDEX, "SECTION_DATA", "")
  debug_indent_up()

  if (anchor_name in anchors_description_data) {
    # omit variable related warnings when they are not displayed
    if (anchor_type != "variable" || VARS) {
      printf("WARNING: [%s] redefined docs of %s: %s\n",
             FILENAME,
             anchor_type,
             anchor_name) > "/dev/stderr"
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
      printf("WARNING: [%s] redefining associated section data: %s\n",
             FILENAME,
             anchor_name) > "/dev/stderr"
    }

    anchors_section_data[anchor_name] = assemble_section_data()
    forget_section_data()
  }

  debug(sprintf("%s debug_associate_data_with_%s (FINAL)",
                DEBUG_INDENT_STACK,
                anchor_type))
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
  debug_array(SECTION_DATA, SECTION_DATA_INDEX, "SECTION_DATA", "")
  debug_indent_up()
}

function forget_section_data() {
  delete SECTION_DATA
  SECTION_DATA_INDEX = 1

  debug(DEBUG_INDENT_STACK " forget_section_data")
  debug_indent_down()
  debug_array(SECTION_DATA, SECTION_DATA_INDEX, "SECTION_DATA", "")
  debug_indent_up()
}

function get_associated_section_data(anchor_name,
                                     anchor_section_data) {
  if (anchor_name in anchor_section_data) {
    return colorize_description_backticks(apply_output_specific_formatting(anchor_section_data[anchor_name]))
  }
  return 0 # means that there is no associated section data with this anchor
}

function get_max_anchor_length(anchors, #locals
                               max_len, key, anchor, n) {
  max_len = 0
  for (key in anchors) { # order is not important
    anchor = anchors[key]
    if (anchor in SUB_LABEL) {
      n = length(SUB_LABEL[anchor])
    } else {
      n = length(anchor)
    }
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
  # --------------------------------------------------------------------------
  # Since I cannot use this code in mawk and nawk, I implemented a manual hack
  # --------------------------------------------------------------------------
  # replace_with = COLOR_BACKTICKS_CODE "\\1" COLOR_RESET_CODE
  # return gensub(/`([^`]+)`/, replace_with, "g", description) # only for gawk
  # --------------------------------------------------------------------------
  while (match(string, /`([^`]+)`/)) {
    before_match = substr(string, 1, RSTART - 1)
    inside_match = substr(string, RSTART + 1, RLENGTH - 2)
    after_match = substr(string, RSTART + RLENGTH)

    string = sprintf(repeated_string("%s", 5),
                     before_match,
                     COLOR_BACKTICKS_CODE,
                     inside_match,
                     COLOR_RESET_CODE,
                     after_match)
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
                                 k, array_of_lines, line, description) {
  # the automatically-assigned indexes during the split are: 1, ..., #lines
  split(anchors_description_data[anchor_name], array_of_lines, "\n")

  # the tag for the first line is stripped below (after the parameter update)
  description = repeated_string("", OFFSET) array_of_lines[1]

  for (k=2;
       k<=length_array_posix(array_of_lines);
       k++) {
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
  return colorize_description_backticks(apply_output_specific_formatting(description))
}

function assemble_description_data(             \
    description, k) {
  description = DESCRIPTION_DATA[1]
  for (k=2; k<=length_array_posix(DESCRIPTION_DATA); k++) {
    description = description "\n" DESCRIPTION_DATA[k]
  }
  return description
}

function assemble_section_data(                 \
    section, k) {
  section = SECTION_DATA[1]
  for (k=2; k<=length_array_posix(SECTION_DATA); k++) {
    section = section "\n" SECTION_DATA[k]
  }
  return section
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
    printf("ERROR (we shouldn't be here): %s\n", description) > "/dev/stderr"
    exit 1
  }
}

function extract_substitution_params(string_with_parameters, #locals
                                     temp_placeholder, k, key_values, pair, key) {
  delete SUB_PARAMS_CURRENT
  temp_placeholder = "\034" # the “file separator” ASCII control character

  # temporarily replace escaped commas
  gsub(/\\,/, temp_placeholder, string_with_parameters)
  for (k=1;
       k<=split(string_with_parameters, key_values, ",");
       k++) {
    gsub(temp_placeholder, ",", key_values[k]) # restore commas
    split(key_values[k], pair, ":")
    gsub(SPACES_TABS_REGEX, "", pair[1])
    SUB_PARAMS_CURRENT[pair[1]] = pair[2]
  }

  for (key in SUB_PARAMS_DEFAULTS) {
    if (!(key in SUB_PARAMS_CURRENT)) {
      SUB_PARAMS_CURRENT[key] = SUB_PARAMS_DEFAULTS[key]
    }
  }
}

function form_substitutions(                                            \
    split_substitutions, k, string, substitution_params, substitution_rest,
    key_value_parts) {
  for (k=1;
       k<=split(SUB, split_substitutions, ";");
       k++) {
    string = split_substitutions[k]

    # Extract optional params in a <...> prefix
    if (match(string, /^<([^>]*)>/)) {
      substitution_params = substr(string, RSTART+1, RLENGTH-2) # strip < and >
      substitution_rest = substr(string, RSTART + RLENGTH)
    } else {
      substitution_params = ""
      substitution_rest = string
    }

    split(substitution_rest, key_value_parts, ":")
    gsub(SPACES_TABS_REGEX, "", key_value_parts[1])

    SUB_PARAMS[key_value_parts[1]] = substitution_params
    if (length_array_posix(key_value_parts) == 2) {
      SUB_VALUES[key_value_parts[1]] = key_value_parts[2]
    } else {
      SUB_VALUES[key_value_parts[1]] = key_value_parts[3]
      SUB_LABEL[key_value_parts[1]] = key_value_parts[2]
    }
  }
}

function display_substitutions(anchor, len_anchors, #locals
                               k, n, L, M, I, value_parts, offset,
                               cond_indent, indentation, text) {
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
    printf(colorize_description_backticks(apply_output_specific_formatting(text)))
  }
}

# we have to escape {...} in \begin{alltt} ... \end{alltt}
function escape_braces_for_latex_output(text) {
  if (OUTPUT_FORMAT == "LATEX") {
    gsub(/\{/, "\\{", text)
    gsub(/\}/, "\\}", text)
  }
  return text
}

function display_anchor_with_data(anchor, description, section, len_anchors, #locals
                                  renamed_anchor, formatted_anchor, padding,
                                  normalized_anchor_name) {
  extract_substitution_params(SUB_PARAMS[anchor])
  debug_dict(SUB_PARAMS_CURRENT, "SUB_PARAMS_CURRENT", anchor)

  # Display the section (if there is one) even if it is anchored to a deprecated anchor
  # that is not to be displayed.
  if (section) {
    if (COLOR_SECTION_CODE) {
      printf("%s%s%s\n", COLOR_SECTION_CODE, section, COLOR_RESET_CODE)
    } else {
      printf("%s\n", section)
    }
  }

  if (DISPLAY_PARAMS["show"]) {
    if (anchor in SUB_LABEL) {
      renamed_anchor = SUB_LABEL[anchor]
    } else {
      renamed_anchor = anchor
    }

    formatted_anchor = apply_output_specific_formatting(renamed_anchor)
    padding = repeated_string("", len_anchors - length(renamed_anchor))
    # handle padding manually because there is a difference between the actual text and
    # the visible text (for latex)
    if (DISPLAY_PARAMS["color"]) {
      formatted_anchor = sprintf("%s%s%s%s",
                                 DISPLAY_PARAMS["color"],
                                 formatted_anchor,
                                 padding,
                                 COLOR_RESET_CODE)
    } else {
      formatted_anchor = sprintf("%s%s", formatted_anchor, padding)
    }

    if (PADDING != " ") {
      gsub(/ /, PADDING, formatted_anchor)
    }

    printf("%s%s%s",
           formatted_anchor,
           description,
           SUB_PARAMS_CURRENT["L"] ? "\n" : "")
  }
  display_substitutions(anchor, len_anchors)
}

function count_numb_double_colon(new_target, #locals
                                 counter, target, wip_target_split, target_split, key) {
  split(WIP_TARGET, wip_target_split, DOUBLE_COLON_SEPARATOR)
  if (wip_target_split[1] == new_target) {
    # if we are still dealing with the WIP target, return its index
    return wip_target_split[2]
  }

  counter = 1
  for (key in TARGETS) { # order is not important
    target = TARGETS[key]
    split(target, target_split, DOUBLE_COLON_SEPARATOR)
    if (target_split[1] == new_target) {
      counter++
    }
  }
  return counter
}

# add here formatting functions to be applied before colors have been added
function apply_output_specific_formatting(text) {
  return escape_braces_for_latex_output(text)
}

function strip_start_end_spaces(string) {
  sub(/^ */, "", string)
  sub(/ *$/, "", string)
  return string
}

# the user can change separately colors in the ranges 30-37 and 40-47
function set_user_defined_color_theme(                                  \
    html_colors_split, key, ansi_html_map, ansi_param, html_color_code) {
  # format: ANSI_PARAM:HTML_COLOR_CODE[,...]
  if (EXPORT_THEME) {
    split(EXPORT_THEME, html_colors_split, ",")
    for (key in html_colors_split) {
      split(html_colors_split[key], ansi_html_map, ":")
      ansi_param = ansi_html_map[1]
      html_color_code = ansi_html_map[2]
      # values in the range 0-9 cannot be modified
      if (ansi_param > 9 && ansi_param in ANSI_TO_HTML_COLOR) {
        ANSI_TO_HTML_COLOR[ansi_param] = html_color_code
      }
    }
  }
}

# The solarized theme is used by default
# https://github.com/altercation/solarized?tab=readme-ov-file#the-values
function define_ansi_to_html_colors(            \
    k) {
  # no foreground/background by default
  ANSI_TO_HTML_COLOR["BG"] = -1 # "000000"
  ANSI_TO_HTML_COLOR["FG"] = -1 # "AAAAAA"

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
  COLOR_LABELS["WARNING"] = "color-warning"
  COLOR_LABELS["BACKTICKS"] = "color-backticks"
  COLOR_LABELS["FG"] = "makefile-doc-fg"
  COLOR_LABELS["BG"] = "makefile-doc-bg"
}

# here ansi_color_param is the normal ANSI color params, e.g., 30-37, but it could as
# well be "FG" or "BG"
function ansi_color_param_to_html_style(ansi_color_param, label, #locals
                                        template, attr) {
  if (ansi_color_param == "FG" || ansi_color_param == "BG") {
    if (ANSI_TO_HTML_COLOR[ansi_color_param] == -1) {
      return "" # indicates to not set any style
    }
    return sprintf("    .%s { %s: #%s; }\n",
                   COLOR_LABELS[label],
                   ansi_color_param == "FG" ? "color" : "background-color",
                   ANSI_TO_HTML_COLOR[ansi_color_param])
  }

  template = "    .%s %s\n"
  if (ansi_color_param && ansi_color_param in ANSI_TO_HTML_COLOR) {
    attr = ANSI_TO_HTML_ATTR[ansi_color_param]
    return sprintf(template,
                   COLOR_LABELS[label],
                   sprintf("{ %s: %s%s; }",
                           attr,
                           (attr == "color" || attr == "background-color")? "#" : "",
                           ANSI_TO_HTML_COLOR[ansi_color_param]))
  }

  return sprintf(template, COLOR_LABELS[label], "{}")
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
      return "<span class=\"" COLOR_LABELS[color_label_key] "\">"
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

function validate_ansi_param(ansi_param) {
  if (ansi_param in ANSI_TO_HTML_COLOR) {
    # The explicit cast to int here is needed only because of a busybox awk bug
    # see misc/busybox_awk_bug_20251107.awk
    return int(ansi_param)
  }
  return 0
}

function initialize_colors() {
  define_ansi_to_html_colors()
  define_ansi_to_html_attributes()
  define_ansi_to_latex_function()
  define_color_labels()

  COLOR_DEFAULT = validate_ansi_param(COLOR_DEFAULT == "" ? 34 : COLOR_DEFAULT)
  COLOR_ATTENTION = validate_ansi_param(COLOR_ATTENTION == "" ? 31 : COLOR_ATTENTION)
  COLOR_DEPRECATED = validate_ansi_param(COLOR_DEPRECATED == "" ? 33 : COLOR_DEPRECATED)
  COLOR_WARNING = validate_ansi_param(COLOR_WARNING == "" ? 35 : COLOR_WARNING)
  COLOR_SECTION = validate_ansi_param(COLOR_SECTION == "" ? 32 : COLOR_SECTION)
  COLOR_BACKTICKS = validate_ansi_param(COLOR_BACKTICKS == "" ? 0 : COLOR_BACKTICKS)

  COLOR_DEFAULT_CODE = define_color(COLOR_DEFAULT, "DEFAULT")
  COLOR_ATTENTION_CODE = define_color(COLOR_ATTENTION, "ATTENTION")
  COLOR_DEPRECATED_CODE = define_color(COLOR_DEPRECATED, "DEPRECATED")
  COLOR_WARNING_CODE = define_color(COLOR_WARNING, "WARNING")
  COLOR_SECTION_CODE = define_color(COLOR_SECTION, "SECTION")
  COLOR_BACKTICKS_CODE = define_color(COLOR_BACKTICKS, "BACKTICKS")
  COLOR_RESET_CODE = define_color(-1)

  if (OUTPUT_FORMAT == "HTML") {
    HTML_FOOTER = "</pre>\n</div>"
    HTML_HEADER = sprintf("<head>\n  <style type=\"text/css\">\n%s%s%s%s%s%s%s%s  </style>\n</head>\n<div class=\"makefile-doc-fg makefile-doc-bg\">\n<pre>",
                          ansi_color_param_to_html_style(COLOR_ATTENTION, "ATTENTION"),
                          ansi_color_param_to_html_style(COLOR_SECTION, "SECTION"),
                          ansi_color_param_to_html_style(COLOR_DEPRECATED, "DEPRECATED"),
                          ansi_color_param_to_html_style(COLOR_DEFAULT, "DEFAULT"),
                          ansi_color_param_to_html_style(COLOR_WARNING, "WARNING"),
                          ansi_color_param_to_html_style(COLOR_BACKTICKS, "BACKTICKS"),
                          ansi_color_param_to_html_style("FG", "FG"),
                          ansi_color_param_to_html_style("BG", "BG"))
  } else if (OUTPUT_FORMAT == "LATEX") {
    LATEX_FOOTER = "\\end{alltt}\n\\end{varwidth}\n\\end{document}"
    # Is there a better way to store this?
    LATEX_HEADER = sprintf("\\documentclass{article}\n\\usepackage[utf8]{inputenc}\n\\usepackage{xcolor}\n\\usepackage{alltt}\n\\usepackage[top=0cm, bottom=0cm, left=0cm, right=0cm]{geometry}\n\\usepackage{varwidth}\n\\usepackage[active,tightpage]{preview}\n\\usepackage[normalem]{ulem}\n\n\\setlength{\\fboxsep}{0pt}\n\n\\newcommand{\\bgcolor}[2]{\\colorbox{#1}{\\vphantom{Ay}#2}}\n\n\\PreviewEnvironment{varwidth}\n\n%s%s\\definecolor{color-attention}{HTML}{%s}\n\\definecolor{color-section}{HTML}{%s}\n\\definecolor{color-deprecated}{HTML}{%s}\n\\definecolor{color-default}{HTML}{%s}\n\\definecolor{color-warning}{HTML}{%s}\n\\definecolor{color-backticks}{HTML}{%s}\n\n\\pagestyle{empty}\n\\begin{document}\n\n\\begin{varwidth}{\\linewidth}\n%s%s\n\\begin{alltt}",
                           ansi_color_param_to_latex_color("FG", 1),
                           ansi_color_param_to_latex_color("BG", 1),
                           ansi_color_param_to_latex_color(COLOR_ATTENTION),
                           ansi_color_param_to_latex_color(COLOR_SECTION),
                           ansi_color_param_to_latex_color(COLOR_DEPRECATED),
                           ansi_color_param_to_latex_color(COLOR_DEFAULT),
                           ansi_color_param_to_latex_color(COLOR_WARNING),
                           ansi_color_param_to_latex_color(COLOR_BACKTICKS),
                           ansi_color_param_to_latex_color("FG"),
                           ansi_color_param_to_latex_color("BG"))
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
    print "Options:"
    printf "  OUTPUT_FORMAT: %s\n", OUTPUT_FORMAT
    printf "  EXPORT_THEME (theme for HTML/LATEX output): %s\n", EXPORT_THEME
    printf "  SUB (substitutions): %s\n", SUB
    printf "  DEBUG ([bool] output debug info): %s\n", DEBUG
    printf "  DEBUG_FILE (debug info file): %s\n", DEBUG_FILE
    printf "  TARGETS_REGEX (regex for matching targets): %s\n", TARGETS_REGEX
    printf "  VARIABLES_REGEX (regex for matching variables): %s\n", VARIABLES_REGEX
    printf "  VARS ([bool] show documented variables): %s\n", VARS
    printf "  PADDING (a padding character between anchors and docs): \"%s\"\n", PADDING
    printf "  DEPRECATED ([bool] show deprecated anchors): %s\n", DEPRECATED
    printf "  OFFSET (offset of docs from anchors): %s\n", OFFSET
    printf "  CONNECTED (ignore docs followed by an empty line): %s\n", CONNECTED
    printf "  COLOR_: "
    printf "%sDEFAULT%s, ", COLOR_DEFAULT_CODE, COLOR_RESET_CODE
    printf "%sATTENTION%s, ", COLOR_ATTENTION_CODE, COLOR_RESET_CODE
    printf "%sDEPRECATED%s, ", COLOR_DEPRECATED_CODE, COLOR_RESET_CODE
    printf "%sSECTION%s, ", COLOR_SECTION_CODE, COLOR_RESET_CODE
    printf "%sWARNING%s, ", COLOR_WARNING_CODE, COLOR_RESET_CODE
    printf "%sBACKTICKS%s\n", COLOR_BACKTICKS_CODE, COLOR_RESET_CODE
}

# =============================================================================
# DEBUG STUFF
#
# While debug(message) outputs messages only when the DEBUG option is defined, the
# message itself gets formed always (same for functions calling debug(...)). I don't
# know how to solve this in a nice way and I don't want to use everywhere if (DEBUG) ...
# =============================================================================
function debug(message) {
  if (DEBUG) {
    printf "%s\n", message >> DEBUG_FILE
  }
}

function debug_indent_up() {
  if (DEBUG) {
    if (DEBUG_INDENT_STACK == "*") {
      printf("WARNING: already at top level\n") > "/dev/stderr"
    } else {
      DEBUG_INDENT_STACK = substr(DEBUG_INDENT_STACK, 1, length(DEBUG_INDENT_STACK)-1)
    }
  }
}

function debug_indent_down() {
  if (DEBUG) {
    DEBUG_INDENT_STACK = DEBUG_INDENT_STACK "*"
  }
}

function debug_pattern_rule(title) {
  debug(DEBUG_INDENT_STACK " line: " FNR " (" title ")")
  debug_indent_down()
}

function debug_array(array, array_next_index, array_name, array_note, #locals
                     k) {
  debug(sprintf("%s [A] %s (length: %s, next index: %s%s)",
                DEBUG_INDENT_STACK,
                array_name,
                length_array_posix(array),
                array_next_index,
                array_note ? ", note: " array_note : array_note))
  for (k=1; k<=length_array_posix(array); k++) {
    debug("+ " k ": " array[k])
  }
}

function debug_dict(array, array_name, array_note, #locals
                    k, sorted_keys) {
  debug(sprintf("%s [D] %s (length: %s%s)",
                DEBUG_INDENT_STACK,
                array_name,
                length_array_posix(array),
                array_note ? ", note: " array_note : array_note))

  # print in sorted order for testing purposes
  for (k=1; k<=sort_keys(array, sorted_keys); k++) {
    debug("+ " sorted_keys[k] ": " array[sorted_keys[k]])
  }
}

function debug_init() {
  debug(DEBUG_INDENT_STACK " debug_init")
  debug("+ ~FS~: " FS)
  debug("+ ~DEBUG_FILE~: " DEBUG_FILE)
  debug("+ ~SUB~: " SUB)
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
  debug("+ ~NUMBER_OF_FILES_PROCESSED~: " NUMBER_OF_FILES_PROCESSED)
  debug("+ ~FILES_PROCESSED~: " FILES_PROCESSED)
}

function debug_description_not_section() {
  debug(DEBUG_INDENT_STACK " debug_description_not_section")
  debug("+ ~$0~: " $0)
  debug("+ ~g_description_string~: " g_description_string)
}

function debug_empty_line() {
  debug(DEBUG_INDENT_STACK " debug_empty_line")
  debug("+ [before reset] ~WIP_TARGET~:" WIP_TARGET)
}

function debug_new_section() {
  debug(DEBUG_INDENT_STACK " debug_new_section")
  debug("+ ~$0~: " $0)
  debug("+ ~g_section_string~: " g_section_string)
}

function debug_target_matched() {
  debug(DEBUG_INDENT_STACK " debug_target_matched")
  debug("+ ~$0~: " $0)
  debug("+ ~$1~: " $1)
  debug("+ ~g_target_name~: " g_target_name)
  debug("+ ~WIP_TARGET~: " WIP_TARGET)
  debug_indent_down()
  debug_array(DESCRIPTION_DATA, DESCRIPTION_DATA_INDEX, "DESCRIPTION_DATA", "")
  debug_indent_up()
}

function debug_variable_matched() {
  debug(DEBUG_INDENT_STACK " debug_variable_matched")
  debug("+ ~g_variable_name~: " g_variable_name)
  debug_indent_down()
  debug_array(DESCRIPTION_DATA, DESCRIPTION_DATA_INDEX, "DESCRIPTION_DATA", "")
  debug_indent_up()
}

function debug_END() {
  debug(DEBUG_INDENT_STACK " debug_END")
  debug("+ ~g_max_target_length~: " g_max_target_length)
  debug("+ ~g_max_variable_length~: " g_max_variable_length)
  debug("+ ~g_max_anchor_length~: " g_max_anchor_length)
  debug("+ ~g_separator~: " g_separator)
  debug_indent_down()
  debug_array(DESCRIPTION_DATA, DESCRIPTION_DATA_INDEX, "DESCRIPTION_DATA", "")
  debug_array(SECTION_DATA, SECTION_DATA_INDEX, "SECTION_DATA", "")

  debug_array(TARGETS, TARGETS_INDEX, "TARGETS", "")
  debug_dict(TARGETS_DESCRIPTION_DATA, "TARGETS_DESCRIPTION_DATA", "")
  debug_dict(TARGETS_SECTION_DATA, "TARGETS_SECTION_DATA", "")

  debug_array(VARIABLES, VARIABLES_INDEX, "VARIABLES", "")
  debug_dict(VARIABLES_DESCRIPTION_DATA, "VARIABLES_DESCRIPTION_DATA", "")
  debug_dict(VARIABLES_SECTION_DATA, "VARIABLES_SECTION_DATA", "")

  debug_dict(SUB_VALUES, "SUB_VALUES", "")
  debug_dict(SUB_LABEL, "SUB_LABEL", "")
  debug_dict(SUB_PARAMS, "SUB_PARAMS", "")
  debug_dict(SUB_PARAMS_DEFAULTS, "SUB_PARAMS_DEFAULTS", "")
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

  OUTPUT_FORMAT = OUTPUT_FORMAT == "" ? "ANSI" : toupper(OUTPUT_FORMAT)
  if (OUTPUT_FORMAT != "ANSI" && OUTPUT_FORMAT != "HTML" && OUTPUT_FORMAT != "LATEX") {
    printf("WARNING: ignorring invalid OUTPUT_FORMAT %s (using ANSI instead).\n",
           OUTPUT_FORMAT) > "/dev/stderr"
    OUTPUT_FORMAT = "ANSI"
  }

  FS = ":" # set the field separator

  ASSIGNMENT_OPERATORS_PATTERN = "(=|:=|::=|:::=|!=|\\?=|\\+=)"
  split("override unexport export private", VARIABLE_QUALIFIERS, " ")
  VARIABLES_REGEX_DEFAULT = sprintf("^ *( *(%s) *)* *[^.#][a-zA-Z0-9_-]* *%s",
                                    join(VARIABLE_QUALIFIERS, "|"),
                                    ASSIGNMENT_OPERATORS_PATTERN)
  initialize_colors()

  VARIABLES_REGEX = VARIABLES_REGEX == "" ? VARIABLES_REGEX_DEFAULT : VARIABLES_REGEX
  TARGETS_REGEX = TARGETS_REGEX == "" ? "^ *[^.#][ ,a-zA-Z0-9$_/%.(){}-]* *&?(:|::)( |$|.*;)" : TARGETS_REGEX
  VARS = VARS == "" ? 1 : VARS
  PADDING = PADDING == "" ? " " : PADDING
  DEPRECATED = DEPRECATED == "" ? 1 : DEPRECATED
  OFFSET = OFFSET == "" ? 2 : OFFSET
  CONNECTED = CONNECTED == "" ? 1 : CONNECTED
  if (length(PADDING) != 1) {
    printf("ERROR: PADDING should have length 1\n") > "/dev/stderr"
    exit 1
  }

  # ------------------------------------------------------
  # default substitution parameters (don't change the defaults)
  # ------------------------------------------------------
  SUB_PARAMS_DEFAULTS["L"] = 1 # 0: start display on current line, 1: start display on next line
  SUB_PARAMS_DEFAULTS["M"] = 1 # 1: multi-line display, 0: single-line display
  SUB_PARAMS_DEFAULTS["N"] = -1 # max number of elements to display (-1 means no limit)
  SUB_PARAMS_DEFAULTS["S"] = "" # separator
  SUB_PARAMS_DEFAULTS["P"] = "" # prefix
  SUB_PARAMS_DEFAULTS["I"] = "" # initial string, e.g., (
  SUB_PARAMS_DEFAULTS["T"] = "" # termination string, e.g., , ...)
  # ------------------------------------------------------

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

  HEADER_TARGETS = "Available targets:"
  HEADER_VARIABLES = "Command-line arguments:"
  NUMBER_OF_FILES_PROCESSED = 0
  FILES_PROCESSED = ""
  SPACES_TABS_REGEX = "^[ \t]+|[ \t]+$"
  WIP_TARGET = ""
  # used to signify double-colon targets in the documentation
  DOUBLE_COLON_SEPARATOR = "~"

  debug_init()

  # we could exit faster but this causes the linter to not see defined variables
  SHOW_HELP = SHOW_HELP == "" ? 1 : SHOW_HELP  # to suppress during linting
  if (ARGC == 1) {
    if (SHOW_HELP) {
      print_help()
    }
    exit 1
  }
}

{
  PATTERN_RULE_MATCHED = 0
}

FNR == 1 {
  debug_indent_up()
  debug(DEBUG_INDENT_STACK " FILE: " FILENAME)
  debug_indent_down()
  debug_pattern_rule("file counter")

  NUMBER_OF_FILES_PROCESSED++
  if (FILES_PROCESSED) {
    FILES_PROCESSED = FILES_PROCESSED " " FILENAME
  } else {
    FILES_PROCESSED = FILENAME
  }
  debug_FNR1()
  debug_indent_up()
}

# Capture the line if it is a description (but not a section).
/^ *##([^@]|$)/ {
  debug_pattern_rule("description")

  g_description_string = $0
  sub(/^ */, "", g_description_string)

  debug_description_not_section()

  save_description_data(g_description_string)

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

  g_section_string = $0
  sub(/ *##@/, "", g_section_string) # strip the tags (they are not needed anymore)

  debug_new_section()

  save_section_data(g_section_string)

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
$0 ~ TARGETS_REGEX {
  debug_pattern_rule("target")

  g_target_name = $1

  # remove spaces up to & in grouped targets, e.g., `t1 t2   &` becomes `t1 t2&`
  # for the reason to use \\&, see AWK's Gory-Details!
  # https://www.gnu.org/software/gawk/manual/html_node/Gory-Details.html
  sub(/ *&/, "\\&", g_target_name)
  if ($0 ~ "::") {
    # surround double-colon targets in square brackets to make them easy to count
    g_target_name = sprintf("%s%s%s",
                            g_target_name,
                            DOUBLE_COLON_SEPARATOR,
                            count_numb_double_colon(g_target_name))
  }

  debug_target_matched()

  # look for inline descriptions only if there aren't any descriptions above the target
  if (length_array_posix(DESCRIPTION_DATA) == 0 && WIP_TARGET != g_target_name) {
    parse_inline_descriptions($0) # this might modify DESCRIPTION_DATA
  }

  if (length_array_posix(DESCRIPTION_DATA) > 0) {
    WIP_TARGET = g_target_name
    debug(DEBUG_INDENT_STACK " [assign] ~WIP_TARGET~: " WIP_TARGET)
    TARGETS_INDEX = associate_data_with_anchor(strip_start_end_spaces(g_target_name),
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
    g_variable_name = strip_start_end_spaces(parse_variable_name($0))
    debug_variable_matched()
    VARIABLES_INDEX = associate_data_with_anchor(g_variable_name,
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

# Display results (all stdout is here).
END {
  debug_indent_up()
  debug(DEBUG_INDENT_STACK " END")
  debug_indent_down()

  # Form SUB_LABEL before calling get_max_anchor_length
  form_substitutions()

  g_max_target_length = get_max_anchor_length(TARGETS)
  g_max_variable_length = get_max_anchor_length(VARIABLES)
  g_max_anchor_length = max(g_max_target_length, g_max_variable_length)
  g_separator = get_separator("-", g_max_anchor_length)

  debug_END()
  debug(DEBUG_INDENT_STACK " extracted_sub_params")
  debug_indent_down()

  if (OUTPUT_FORMAT == "HTML") {
    print(HTML_HEADER)
  } else if (OUTPUT_FORMAT == "LATEX") {
    print(LATEX_HEADER)
  }

  # process targets
  if (g_max_target_length > 0) {
    printf("%s\n%s\n%s\n", g_separator, HEADER_TARGETS, g_separator)

    for (g_indx = 1; g_indx <= length_array_posix(TARGETS); g_indx++) { # enforce order
      g_target = TARGETS[g_indx]
      g_description = format_description_data(g_target,
                                              TARGETS_DESCRIPTION_DATA,
                                              g_max_anchor_length)
      g_section = get_associated_section_data(g_target, TARGETS_SECTION_DATA)
      display_anchor_with_data(g_target, g_description, g_section, g_max_anchor_length)
    }
  }

  # process variables
  # When all variables are deprecated and DEPRECATED = 0, just a header is displayed.
  if (g_max_variable_length > 0 && VARS) {
    g_variables_display_pattern = g_max_target_length > 0 ? "\n%s\n%s\n%s\n": "%s\n%s\n%s\n"

    printf(g_variables_display_pattern, g_separator, HEADER_VARIABLES, g_separator)
    for (g_indx = 1; g_indx <= length_array_posix(VARIABLES); g_indx++) {
      g_variable = VARIABLES[g_indx]
      g_description = format_description_data(g_variable,
                                              VARIABLES_DESCRIPTION_DATA,
                                              g_max_anchor_length)
      g_section = get_associated_section_data(g_variable, VARIABLES_SECTION_DATA)
      display_anchor_with_data(g_variable, g_description, g_section, g_max_anchor_length)
    }
  }
  debug_indent_down()

  if (g_max_target_length > 0 || (g_max_variable_length > 0 && VARS)) {
    printf("%s\n", g_separator)
  } else {
    if (NUMBER_OF_FILES_PROCESSED > 0) {
      printf("WARNING: no documented targets/variables in %s\n",
             FILES_PROCESSED) > "/dev/stderr"
    }
  }

  if (OUTPUT_FORMAT == "HTML") {
    print(HTML_FOOTER)
  } else if (OUTPUT_FORMAT == "LATEX") {
    print(LATEX_FOOTER)
  }

  if (DEBUG) {
    close(DEBUG_FILE)
    print "Debug info written in " DEBUG_FILE
  }
}
