# The new parser of makefile-doc.awk (see misc/docs/parser-model.tex), under development: it
# is loaded next to the script by its tests, and will be merged into makefile-doc.awk when it
# replaces the current parser. Its names start with lexical_ (no clash with the script).

# The kind of a logical line: assignment, rule, special rule, neutral, other. A placeholder:
# its examples are in test/lexical.spec (see test/unit/lexical.awk).
function lexical_kind(line) {
  return ""
}
