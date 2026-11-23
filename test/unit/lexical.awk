# Check the functions of the new parser (parser.awk) against the examples of
# test/lexical.spec. Not run by the test suite yet (its name does not start with test_): the
# functions are placeholders. Run it by hand:
#   awk -v UNIT_TEST=1 -f test/unit/harness.awk -f makefile-doc.awk -f parser.awk \
#       -f test/unit/lexical.awk /dev/null

# Read the blocks of a spec file into blocks[k, key] (k = 1..n) and return n. A value in
# brackets keeps its spaces (the first [ and the last ] of the line delimit it); a line that
# starts with # is a comment, a blank line ends a block.
function read_spec(path, blocks, #locals
                   line, n, in_block, colon, key, value) {
  n = 0
  in_block = 0
  while ((getline line < path) > 0) {
    if (line ~ /^[ \t]*$/) {
      in_block = 0
    } else if (substr(line, 1, 1) != "#") {
      if (!in_block) {
        n++
        in_block = 1
      }
      colon = index(line, ":")
      key = substr(line, 1, colon - 1)
      value = substr(line, colon + 1)
      sub(/^[ \t]+/, "", value)
      if (substr(value, 1, 1) == "[" && substr(value, length(value)) == "]") {
        value = substr(value, 2, length(value) - 2)
      }
      blocks[n, key] = value
    }
  }
  close(path)
  return n
}

function test_lexical_kind(    spec, n, k) {
  n = read_spec("test/lexical.spec", spec)
  check_true("read_spec: test/lexical.spec has blocks", n > 0)
  for (k = 1; k <= n; k++) {
    check("lexical_kind: " spec[k, "id"], lexical_kind(spec[k, "line"]), spec[k, "kind"])
  }
}

function test_lexical_mask() {
  check("lexical_mask: a line without references or escapes is unchanged",
        lexical_mask("t: dep ; x # c"), "t: dep ; x # c")
  check("lexical_mask: a reference", lexical_mask("V := $(shell echo x#y) # c"),
        "V := _________________ # c")
  check("lexical_mask: a reference with braces", lexical_mask("V := ${x#y} # c"),
        "V := ______ # c")
  check("lexical_mask: a nested reference", lexical_mask("V := $(a $(b #)) # c"),
        "V := ___________ # c")
  check("lexical_mask: parentheses nest in $(...)", lexical_mask("V = $(a (b) #) # c"),
        "V = __________ # c")
  check("lexical_mask: braces do not nest in $(...)", lexical_mask("V = $(a {b) #} # c"),
        "V = _______ #} # c")
  check("lexical_mask: a reference that is not closed", lexical_mask("V := $(foo # c"),
        "V := _________")
  check("lexical_mask: $$", lexical_mask("V := $$(echo #x)"), "V := __(echo #x)")
  check("lexical_mask: $$ then a reference", lexical_mask("V = $$$(x #) # c"),
        "V = ________ # c")
  check("lexical_mask: a one-character reference", lexical_mask("V := a$#b # c"),
        "V := a__b # c")
  check("lexical_mask: $; and $:", lexical_mask("t: a$;b X$:Y"), "t: a__b X__Y")
  check("lexical_mask: \\#", lexical_mask("V := a\\#b # c"), "V := a__b # c")
  check("lexical_mask: \\\\ then #", lexical_mask("V := a\\\\# c"), "V := a__# c")
  check("lexical_mask: \\\\ then \\#", lexical_mask("V := a\\\\\\# c"), "V := a____ c")
  check("lexical_mask: \\:", lexical_mask("foo\\:bar: dep"), "foo__bar: dep")
  check("lexical_mask: \\;", lexical_mask("t: dep \\; x"), "t: dep __ x")
  check("lexical_mask: \\= is not an escape", lexical_mask("t: x\\=y"), "t: x\\=y")
  check("lexical_mask: a $ at the end", lexical_mask("V := a$"), "V := a$")
  check("lexical_mask: a \\ at the end", lexical_mask("V := a\\"), "V := a\\")
  check("lexical_mask: a$b", lexical_mask("a$b"), "a__")
  check("lexical_mask: a$$b", lexical_mask("a$$b"), "a__b")
  check("lexical_mask: a$$$b", lexical_mask("a$$$b"), "a____")
}

BEGIN {
  test_lexical_mask()
  test_lexical_kind()
  done()
}
