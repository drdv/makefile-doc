# Check the functions of the parser (the lexical_* functions of the script): against the
# examples of test/lexical.spec, and line by line.

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

function test_lexical_observe(    spec, n, k, obs, id) {
  n = read_spec("test/lexical.spec", spec)
  check_true("read_spec: test/lexical.spec has blocks", n > 0)
  for (k = 1; k <= n; k++) {
    id = spec[k, "id"]
    lexical_observe(spec[k, "line"], obs)
    check("kind: " id, obs["kind"], array_get(spec, k SUBSEP "kind"))
    check("anchor: " id, obs["anchor"], array_get(spec, k SUBSEP "anchor"))
    check("name: " id, obs["name"], array_get(spec, k SUBSEP "name"))
    check("comment: " id, obs["comment"], array_get(spec, k SUBSEP "comment"))
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

# The states after each physical line of text (lines separated by |), as "rds" (1/0 for
# r, d, s), or "+" for a line that continues on the next one
function trace_lines(text, prefix, #locals
                     state, lines, n, k, obs, out) {
  lexical_init(state, prefix)
  n = split(text, lines, "|")
  out = ""
  for (k = 1; k <= n; k++) {
    if (lexical_join(state, lines[k])) {
      lexical_obs(state["line"], state, obs)
      lexical_step(state, obs)
      out = out " " state["r"] state["d"] state["s"]
    } else {
      out = out " +"
    }
  }
  return substr(out, 2)
}

function test_lexical_states(    state, obs) {
  check("states: the example of the model",
        trace_lines("##@ Build|## Compile the app|build: main.c|\tcc -o app main.c||" \
                    "## The version|V := 1", ""), "001 011 100 100 100 110 000")
  check("states: an inline doc consumes the section", trace_lines("##@ s|t: ## doc", ""), "001 100")
  check("states: an undocumented target leaves the section", trace_lines("##@ s|t:", ""), "001 101")
  check("states: a special target opens a rule (#181)",
        trace_lines("A := 1|.DEFAULT:|\t## not a doc|next:", ""), "000 100 100 100")
  check("states: a directive closes the rule (#182)",
        trace_lines("t:|\techo|include x|\t## a doc|u:", ""), "100 100 000 010 100")
  check("states: a line with only the prefix is a recipe line (drops the doc)",
        trace_lines("t:|## doc|\t|u:", ""), "100 110 100 100")
  check("states: continued lines, recipe lines included",
        trace_lines("## doc|t1 \\|  t2:|\techo \\|still the recipe|V := 1", ""),
        "010 + 100 + 100 000")
  check("states: a recipe line of only its prefix, continued",
        trace_lines("t:|\t\\|BOGUS := 1 ## x|u:", ""), "100 + 100 100")
  check("states: an assignment to .RECIPEPREFIX changes the prefix",
        trace_lines(".RECIPEPREFIX := >|t:|> echo|\t## not a recipe line|u:", ""),
        "000 100 100 110 100")
  check("states: the RECIPEPREFIX option", trace_lines("t:|> echo|\t## doc|u:", ">"),
        "100 100 110 100")

  lexical_observe("define NO_SPACE+=", obs)
  check("define: an operator without a blank is not part of the name", obs["name"], "NO_SPACE")

  lexical_init(state, "")
  lexical_obs(".RECIPEPREFIX = $(P)", state, obs)
  check("prefix: = keeps the text of a reference", state["c"], "$")
  lexical_obs(".RECIPEPREFIX := $(P)", state, obs)
  check("prefix: an expanded reference is not known", state["c"], "$")
  lexical_obs(".RECIPEPREFIX :=", state, obs)
  check("prefix: an empty value is a tab", state["c"], "\t")

  lexical_init(state, "")
  lexical_join(state, "##@ s")
  lexical_obs(state["line"], state, obs)
  lexical_step(state, obs)
  lexical_join(state, "## d")
  lexical_obs(state["line"], state, obs)
  lexical_step(state, obs)
  lexical_join(state, "t: \\")
  lexical_file_start(state)
  check("file start: the doc is dropped, the section carries over",
        state["d"] " " state["s"] " " state["joining"], "0 1 0")
}

# a field of the observation of a line without state (lexical_observe), "" if not set
function observed(line, field, #locals
                  obs) {
  lexical_observe(line, obs)
  return array_get(obs, field)
}

# the inline doc of a line outside a rule (lexical_obs), or "<none>"
function inline_doc(line, #locals
                    state, obs) {
  lexical_init(state, "")
  lexical_obs(line, state, obs)
  return obs["inline"] ? obs["comment"] : "<none>"
}

function test_lexical_special_rules() {
  check("special rule: .PHONY", observed(".PHONY: t", "kind"), "special rule")
  check("special rule: .SILENT", observed(".SILENT: t", "kind"), "special rule")
  check("special rule: .IGNORE", observed(".IGNORE: t", "kind"), "special rule")
  check("special rule: .SECONDARY", observed(".SECONDARY: t", "kind"), "special rule")
  check("special rule: .INTERMEDIATE", observed(".INTERMEDIATE: t", "kind"), "special rule")
  check("special rule: .PRECIOUS", observed(".PRECIOUS: t", "kind"), "special rule")
  check("special rule: leading whitespace and spaces before :",
        observed(" \t.PHONY  : t", "kind"), "special rule")
  check("special rule: tab before :", observed(".PHONY\t: t", "kind"), "special rule")
  check("special rule: .SECONDEXPANSION without prerequisites",
        observed(".SECONDEXPANSION:", "kind"), "special rule")
  check("special rule: .DELETE_ON_ERROR", observed(".DELETE_ON_ERROR:", "kind"), "special rule")
  check("special rule: .SUFFIXES", observed(".SUFFIXES:", "kind"), "special rule")
  check("special rule: .DEFAULT", observed(".DEFAULT:", "kind"), "special rule")
  check("special rule: .NOTINTERMEDIATE", observed(".NOTINTERMEDIATE: t", "kind"),
        "special rule")
  check("special rule: .LOW_RESOLUTION_TIME", observed(".LOW_RESOLUTION_TIME: t", "kind"),
        "special rule")
  check("special rule: .EXPORT_ALL_VARIABLES", observed(".EXPORT_ALL_VARIABLES:", "kind"),
        "special rule")
  check("special rule: .NOTPARALLEL", observed(".NOTPARALLEL:", "kind"), "special rule")
  check("special rule: .ONESHELL", observed(".ONESHELL:", "kind"), "special rule")
  check("special rule: .POSIX", observed(".POSIX:", "kind"), "special rule")
  check("special rule: a suffix rule is a rule", observed(".c.o:", "kind"), "rule")
  check("special rule: a hidden file is a rule", observed(".venv/.sentinel:", "kind"), "rule")
  check("special rule: a name with lower-case letters is a rule",
        observed(".PHONYx: t", "kind"), "rule")
  check("special rule: an upper-case name that is not special is a rule",
        observed(".ENV:", "kind"), "rule")
  check("special rule: a special name with a suffix is a rule",
        observed(".PHONY_ALL:", "kind"), "rule")
  check("special rule: .PHONY as a prerequisite is a rule", observed("t: .PHONY", "kind"), "rule")
}

function test_lexical_variable_names() {
  check("variable name: := without spaces", observed("VAR2_1:=1##comment", "name"), "VAR2_1")
  check("variable name: ?= with spaces", observed("var2_1   ?=  1##comment", "name"), "var2_1")
  check("variable name: :::=", observed("x   :::=fsws", "name"), "x")
  check("variable name: += without value", observed("__a__   +=", "name"), "__a__")
  check("variable name: = with inline doc", observed("X = ## doc", "name"), "X")
  check("variable name: ::= with value and inline doc",
        observed("this_is_A_VARIABLE ::= this is a value ## doc", "name"), "this_is_A_VARIABLE")
  check("variable name: ?= with inline doc and no value", observed("x4?=## doc", "name"), "x4")
  check("variable name: repeated qualifiers",
        observed("override private  override     private  export _w::=", "name"), "_w")
  check("variable name: name starting with a qualifier",
        observed("private  override  export override1     ::=     1", "name"), "override1")
  check("variable name: name made of qualifiers",
        observed("private  override  export export_override::=1", "name"), "export_override")
  check("variable name: unexport is a directive, not a qualifier",
        observed("override unexport V := 1", "kind"), "other")
}

function test_lexical_inline_docs() {
  check("inline doc: ## (a ; in the doc is kept)",
        inline_doc("target: ## some ;description"), "## some ;description")
  check("inline doc: ##! (a ; in the doc is kept)",
        inline_doc("target: ##! some description;"), "##! some description;")
  check("inline doc: ##%", inline_doc("target: ##% some description"), "##% some description")
  check("inline doc: after deps without a space",
        inline_doc("target: deps1 deps2 | deps3## some description"), "## some description")
  check("inline doc: none after an empty inline recipe",
        inline_doc("target:; ## some description"), "<none>")
  check("inline doc: none after an inline recipe",
        inline_doc("target:; @echo 1 ##! some description"), "<none>")
  check("inline doc: none after an inline recipe with two commands",
        inline_doc("target: ; @echo 1 ; echo 2 ##% some description"), "<none>")
  check("inline doc: none after deps and an inline recipe",
        inline_doc("target: deps1 deps2 | deps3 ; echo 1 ## some description"), "<none>")
  check("inline doc: none without a doc", inline_doc("target: "), "<none>")
  check("inline doc: none after deps without a doc",
        inline_doc("target: deps1 deps2 | deps3"), "<none>")
  check("inline doc: none for an inline ##@ (a section is not inline)",
        inline_doc("target: ##@ some text"), "<none>")
  check("inline doc: none for an inline ##@ on a variable",
        inline_doc("X := 1 ##@ some text"), "<none>")
  check("inline doc: variable with a ; in its value", inline_doc("X := a;b ## doc"), "## doc")
  check("inline doc: none in an ordinary comment",
        inline_doc("target: deps # a comment ## text"), "<none>")
  check("inline doc: none in an ordinary comment on a variable",
        inline_doc("X := 1 # a comment ## text"), "<none>")
  check("inline doc: after an escaped # in a value", inline_doc("X := a\\#b ## doc"), "## doc")
  check("inline doc: none after an escaped backslash (\\\\ then a comment)",
        inline_doc("X := a\\\\# note ## text"), "<none>")
  check("inline doc: after an escaped backslash and an escaped #",
        inline_doc("X := a\\\\\\#b ## doc"), "## doc")
  check("inline doc: a ## in the doc is kept", inline_doc("target: ## a ## b"), "## a ## b")
}

function test_lexical_double_colon() {
  check("double colon: ::", observed("t::", "double"), 1)
  check("double colon: :", observed("t:", "double"), 0)
  check("double colon: :: with a target variable", observed("t:: A:=1", "double"), 1)
  check("double colon: grouped", observed("a b &::", "double"), 1)
  check("double colon: :: in the recipe of a : rule",
        observed("t: ; @echo \"a::b\"", "double"), 0)
}

BEGIN {
  test_lexical_special_rules()
  test_lexical_variable_names()
  test_lexical_inline_docs()
  test_lexical_double_colon()
  test_lexical_mask()
  test_lexical_observe()
  test_lexical_states()
  done()
}
