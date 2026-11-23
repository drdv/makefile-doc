# The new parser of makefile-doc.awk (see misc/docs/parser-model.tex), under development: it
# is loaded next to the script by its tests, and will be merged into makefile-doc.awk when it
# replaces the current parser. Its names start with lexical_ (no clash with the script).

# The kind of a logical line: assignment, rule, special rule, neutral, other. A placeholder:
# its examples are in test/lexical.spec (see test/unit/lexical.awk).
function lexical_kind(line) {
  return ""
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
