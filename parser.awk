# The new parser of makefile-doc.awk (see misc/docs/parser-model.tex), under development: it
# is loaded next to the script by its tests, and will be merged into makefile-doc.awk when it
# replaces the current parser. Its names start with lexical_ (no clash with the script).

# Observe a logical line (questions 2-8 of the model, without question 1: a recipe line
# depends on the state). Fill obs with:
#   obs["kind"]     assignment, rule, special rule, neutral, banner, section, doc, other
#   obs["anchor"]   target or variable (assignment and rule), "" otherwise
#   obs["name"]     the name of the anchor, as written in the line
#   obs["comment"]  the comment, from its # to the end of the line ("" if none)
# The examples are in test/lexical.spec (see test/unit/test_lexical.awk).
function lexical_observe(line, obs, #locals
                         first_word) {
  split("", obs)
  obs["kind"] = ""
  obs["anchor"] = ""
  obs["name"] = ""
  obs["comment"] = ""

  if (line ~ /^[ \t]*$/) {
    obs["kind"] = "neutral"
    return
  }
  if (line ~ /^[ \t]*#/) {
    obs["kind"] = line ~ /^[ \t]*###+[ \t]*$/ ? "banner" : \
                  line ~ /^[ \t]*##@/ ? "section" : \
                  line ~ /^[ \t]*##/ ? "doc" : "neutral"
    return
  }

  lexical_scan(line, obs) # kind: assignment, rule or ""
  if (obs["kind"] == "assignment") {
    return
  }

  first_word = line
  sub(/^[ \t]+/, "", first_word)
  sub(/[ \t(].*$/, "", first_word)
  if (first_word ~ /^(ifeq|ifneq|ifdef|ifndef|else|endif)$/) {
    lexical_clear(obs, "neutral")
  } else if (first_word ~ /^(include|-include|sinclude|vpath|export|unexport|undefine|endef)$/) {
    lexical_clear(obs, "other")
  } else if (lexical_define_name(line) != "") {
    lexical_clear(obs, "assignment")
    obs["anchor"] = "variable"
    obs["name"] = lexical_define_name(line)
  } else if (obs["kind"] == "rule") {
    if ((obs["name"] ":") ~ SPECIAL_TARGETS_REGEX) {
      lexical_clear(obs, "special rule")
    }
  } else {
    lexical_clear(obs, "other")
  }
}

# set the kind of obs, without anchor, name and comment
function lexical_clear(obs, kind) {
  obs["kind"] = kind
  obs["anchor"] = ""
  obs["name"] = ""
  obs["comment"] = ""
}

# the name of the variable of a define line (e.g., `override define V :=`), "" if not one
function lexical_define_name(line, #locals
                             rest) {
  rest = line
  sub(/^[ \t]*((export|override|private)[ \t]+)*/, "", rest)
  if (rest !~ /^define[ \t]+[^ \t]/) {
    return ""
  }
  sub(/^define[ \t]+/, "", rest)
  sub(/[ \t].*$/, "", rest)
  return rest
}

# Fill obs with the structure of a line (the searches of the lexical layer): obs["kind"] is
# assignment, rule or "" (neither), with obs["anchor"], obs["name"] and obs["comment"]; for
# an assignment to a variable, also obs["operator"] and obs["value"] (without its comment,
# leading blanks removed). The searches run on the masked line; the texts are cut from the
# line.
function lexical_scan(line, obs, #locals
                      masked, p, c, q, start, end, after, rest, hit, name) {
  masked = lexical_mask(line)
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
    name = lexical_variable_name(substr(line, 1, start - 1), substr(masked, 1, start - 1))
    if (name != "") {
      end = c == "=" ? p : q + 1 # the = of the operator
      obs["kind"] = "assignment"
      obs["anchor"] = "variable"
      obs["name"] = name
      obs["comment"] = lexical_rest_from(line, masked, end, "#")
      obs["operator"] = substr(line, start, end - start + 1)
      obs["value"] = substr(line, end + 1, length(line) - end - length(obs["comment"]))
      sub(/^[ \t]+/, "", obs["value"])
    }
    return
  }

  # p is the separating colon (:, :: or &:)
  name = substr(line, 1, p - 1)
  sub(/[ \t]*&$/, "", name)
  sub(/^[ \t]+/, "", name)
  sub(/[ \t]+$/, "", name)
  if (name == "") {
    return
  }
  obs["kind"] = "rule"
  obs["anchor"] = "target"
  obs["name"] = name
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
    obs["kind"] = "assignment"
    obs["comment"] = lexical_rest_from(line, masked, hit, "#;")
  }
}

# The comment of line after position p: from the first character of chars found in masked
# after p, if it is a #; "" otherwise
function lexical_rest_from(line, masked, p, chars, #locals
                           k, c) {
  for (k = p + 1; k <= length(masked); k++) {
    c = substr(masked, k, 1)
    if (index(chars, c) > 0) {
      return c == "#" ? substr(line, k) : ""
    }
  }
  return ""
}

# The variable of the left side of an assignment, with its qualifiers (export, override,
# private): the single word after them, "" if there is not exactly one word. The words are
# found in masked (a reference is part of a word), the name is cut from text.
function lexical_variable_name(text, masked, #locals
                               word_start, before, n, words, k) {
  if (!match(masked, /[^ \t]+[ \t]*$/)) {
    return ""
  }
  word_start = RSTART
  before = substr(masked, 1, word_start - 1)
  n = split(before, words, /[ \t]+/)
  for (k = 1; k <= n; k++) {
    if (words[k] != "" && words[k] !~ /^(export|override|private)$/) {
      return ""
    }
  }
  text = substr(text, word_start)
  sub(/[ \t]+$/, "", text)
  return text
}

# The line with what GNU Make does not read as syntax replaced by _, so that the searches can
# look for #, :, = and ; directly. The masked line has the same length as the line (the
# positions are the same). Masked:
#   * a reference: from $( or ${ to its matching bracket (only the same kind of bracket
#     nests), or to the end of the line if it is not closed
#   * $ and any other character that follows it: a one-character reference (e.g., $@, $#;
#     $$ is a literal $)
#   * the escape pairs \\, \#, \: and \; (read from left to right: in a run of backslashes,
#     only an odd last one escapes the character that follows)
function lexical_mask(line, #locals
                      n, k, c, next_char, opening, closing, depth, start, out) {
  n = length(line)
  out = ""
  k = 1
  while (k <= n) {
    c = substr(line, k, 1)
    next_char = substr(line, k + 1, 1)
    if (c == "$" && (next_char == "(" || next_char == "{")) {
      opening = next_char
      closing = opening == "(" ? ")" : "}"
      depth = 0
      start = k
      for (k = k + 1; k <= n; k++) {
        c = substr(line, k, 1)
        if (c == opening) {
          depth++
        } else if (c == closing) {
          depth--
          if (depth == 0) {
            break
          }
        }
      }
      if (k > n) { # not closed: masked to the end of the line
        k = n
      }
      out = out repeated_string("_", k - start + 1)
      k++
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

# ---------------------------------------------------------------------------------------
# The state machine (the model, with its state in an array): state["r"] (inside a rule),
# state["d"] (a doc is pending), state["s"] (a section is pending), state["c"] (the recipe
# prefix), and the line being joined (state["joining"], state["pending"]).
# ---------------------------------------------------------------------------------------

function lexical_init(state, prefix) {
  split("", state)
  state["r"] = 0
  state["d"] = 0
  state["s"] = 0
  state["c"] = prefix == "" ? "\t" : substr(prefix, 1, 1)
  state["joining"] = 0
  state["pending"] = ""
}

# At the first line of a file: no open rule and no pending doc (a section and the recipe
# prefix carry over). A line continued at the end of the previous file is dropped.
function lexical_file_start(state) {
  state["r"] = 0
  state["d"] = 0
  state["joining"] = 0
  state["pending"] = ""
}

# Add a physical line: return 1 when a logical line is complete (in state["line"]), 0 when the
# line continues on the next one (an odd number of final backslashes, recipe lines included).
# As in GNU Make, the backslash, the newline and the blanks around them become one space.
function lexical_join(state, physical) {
  if (state["joining"]) {
    sub(/^[ \t]+/, "", physical)
    physical = state["pending"] " " physical
    state["joining"] = 0
  }
  if (has_odd_terminal_backslashes(physical)) {
    physical = substr(physical, 1, length(physical) - 1)
    sub(/[ \t]+$/, "", physical)
    state["pending"] = physical
    state["joining"] = 1
    return 0
  }
  state["line"] = physical
  return 1
}

# Observe a logical line with the state (all the questions of the model): lexical_observe,
# plus question 1 (a recipe line: inside a rule, the line starts with the recipe prefix),
# obs["inline"] (a_i: the comment is an inline doc) and question 9 (an assignment to
# .RECIPEPREFIX changes state["c"], for the next lines).
function lexical_obs(line, state, obs) {
  if (state["r"] && substr(line, 1, 1) == state["c"]) {
    split("", obs)
    lexical_clear(obs, "recipe")
  } else {
    lexical_observe(line, obs)
  }
  obs["inline"] = obs["anchor"] != "" && obs["comment"] ~ /^##/ && obs["comment"] !~ /^##@/
  if (obs["kind"] == "assignment" && obs["anchor"] == "variable" &&
      obs["name"] == ".RECIPEPREFIX") {
    lexical_set_prefix(state, obs["operator"], obs["value"])
  }
}

# The recipe prefix after an assignment to .RECIPEPREFIX: the first character of the value (a
# tab if it is empty). With += the first character does not change; with != or an expanded
# reference (:=, ::=), the value is not known: the prefix does not change either.
function lexical_set_prefix(state, operator, value) {
  if (operator == "+=" || operator == "!=" || (operator ~ /^:+=$/ && index(value, "$") > 0)) {
    return
  }
  state["c"] = value == "" ? "\t" : substr(value, 1, 1)
}

# Update the state with an observation (the step table of the model). obs["attach"] is 1 when
# the line is an anchor that gets documented (by a pending doc or its inline doc), with the
# pending section if there is one.
function lexical_step(state, obs, #locals
                      kind, documented) {
  kind = obs["kind"]
  documented = state["d"] || obs["inline"]
  obs["attach"] = 0
  if (kind == "recipe") {
    state["r"] = 1
    state["d"] = 0
  } else if (kind == "doc") {
    state["d"] = 1
  } else if (kind == "section") {
    state["s"] = 1
  } else if (kind == "banner") {
    state["d"] = 0
  } else if (kind == "rule" || kind == "assignment") {
    state["r"] = kind == "rule"
    if (documented) {
      obs["attach"] = 1
      state["s"] = 0
    }
    state["d"] = 0
  } else if (kind == "special rule") {
    state["r"] = 1
  } else if (kind == "other") {
    state["r"] = 0
    state["d"] = 0
  } # neutral: no change
}
