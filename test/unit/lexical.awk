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

BEGIN {
  test_lexical_kind()
  done()
}
