# Check the functions of the parser (the parser_* functions of the script), stage by stage:
# the observation (against the examples of test/parser.spec), the step, the data and the
# record (against the equations of misc/docs/parser-model.tex), then the whole parser.

# ---------------------------------------------------------------------------------------
# line -> obs: the questions of the observation, the lexical layer
# ---------------------------------------------------------------------------------------

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

function test_parser_observe(    spec, n, k, obs, id) {
  n = read_spec("test/parser.spec", spec)
  check_true("read_spec: test/parser.spec has blocks", n > 0)
  for (k = 1; k <= n; k++) {
    id = spec[k, "id"]
    parser_observe(spec[k, "line"], obs)
    check("kind: " id, obs["kind"], array_get(spec, k SUBSEP "kind"))
    check("anchor: " id, obs["anchor"], array_get(spec, k SUBSEP "anchor"))
    check("name: " id, obs["name"], array_get(spec, k SUBSEP "name"))
    check("comment: " id, obs["comment"], array_get(spec, k SUBSEP "comment"))
  }
}

function test_parser_mask() {
  check("parser_mask: a line without references or escapes is unchanged",
        parser_mask("t: dep ; x # c"), "t: dep ; x # c")
  check("parser_mask: a reference", parser_mask("V := $(shell echo x#y) # c"),
        "V := _________________ # c")
  check("parser_mask: a reference with braces", parser_mask("V := ${x#y} # c"),
        "V := ______ # c")
  check("parser_mask: a nested reference", parser_mask("V := $(a $(b #)) # c"),
        "V := ___________ # c")
  check("parser_mask: parentheses nest in $(...)", parser_mask("V = $(a (b) #) # c"),
        "V = __________ # c")
  check("parser_mask: braces do not nest in $(...)", parser_mask("V = $(a {b) #} # c"),
        "V = _______ #} # c")
  check("parser_mask: a reference that is not closed", parser_mask("V := $(foo # c"),
        "V := _________")
  check("parser_mask: $$", parser_mask("V := $$(echo #x)"), "V := __(echo #x)")
  check("parser_mask: $$ then a reference", parser_mask("V = $$$(x #) # c"),
        "V = ________ # c")
  check("parser_mask: a one-character reference", parser_mask("V := a$#b # c"),
        "V := a__b # c")
  check("parser_mask: $; and $:", parser_mask("t: a$;b X$:Y"), "t: a__b X__Y")
  check("parser_mask: \\#", parser_mask("V := a\\#b # c"), "V := a__b # c")
  check("parser_mask: \\\\ then #", parser_mask("V := a\\\\# c"), "V := a__# c")
  check("parser_mask: \\\\ then \\#", parser_mask("V := a\\\\\\# c"), "V := a____ c")
  check("parser_mask: \\:", parser_mask("foo\\:bar: dep"), "foo__bar: dep")
  check("parser_mask: \\;", parser_mask("t: dep \\; x"), "t: dep __ x")
  check("parser_mask: \\= is not an escape", parser_mask("t: x\\=y"), "t: x\\=y")
  check("parser_mask: a $ at the end", parser_mask("V := a$"), "V := a$")
  check("parser_mask: a \\ at the end", parser_mask("V := a\\"), "V := a\\")
  check("parser_mask: a$b", parser_mask("a$b"), "a__")
  check("parser_mask: a$$b", parser_mask("a$$b"), "a__b")
  check("parser_mask: a$$$b", parser_mask("a$$$b"), "a____")
}

function test_parser_reference_end() {
  check("parser_reference_end: $(...)", parser_reference_end("a $(b) c", 3), 6)
  check("parser_reference_end: ${...}", parser_reference_end("a ${b} c", 3), 6)
  check("parser_reference_end: nested", parser_reference_end("$(a $(b)) c", 1), 9)
  check("parser_reference_end: parentheses nest in $(...)",
        parser_reference_end("$(a (b)) c", 1), 8)
  check("parser_reference_end: braces do not nest in $(...)",
        parser_reference_end("$(a {b) c}", 1), 7)
  check("parser_reference_end: not closed", parser_reference_end("x $(a (b) c", 3), 11)
}

# a field of the observation of a line without state (parser_observe), "" if not set
function observed(line, field, #locals
                  obs) {
  parser_observe(line, obs)
  return array_get(obs, field)
}

function test_parser_special_rules() {
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

function test_parser_variable_names() {
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
  check("override: a qualifier", observed("override PREFIX := /usr", "override"), 1)
  check("override: among other qualifiers", observed("export override V = 1", "override"), 1)
  check("override: not a qualifier when it is the name", observed("override := 1", "override"), 0)
  check("override: none", observed("V := 1", "override"), 0)
  check("override: on a define", observed("override define V", "override"), 1)
  check("variable name: unexport is a directive, not a qualifier",
        observed("override unexport V := 1", "kind"), "other")
}

# the inline doc of a line outside a rule (parser_obs), or "<none>"
function inline_doc(line, #locals
                    state, data, obs) {
  parser_init(state, data, "")
  parser_obs(line, state, obs)
  return obs["inline"] ? obs["comment"] : "<none>"
}

function test_parser_inline_docs() {
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

function test_parser_double_colon() {
  check("double colon: ::", observed("t::", "double"), 1)
  check("double colon: :", observed("t:", "double"), 0)
  check("double colon: :: with a target variable", observed("t:: A:=1", "double"), 1)
  check("double colon: grouped", observed("a b &::", "double"), 1)
  check("double colon: :: in the recipe of a : rule",
        observed("t: ; @echo \"a::b\"", "double"), 0)
}

function test_get_doc_tag() {
  check("get_doc_tag: ##", get_doc_tag("##   doc"), "##")
  check("get_doc_tag: ##!", get_doc_tag("##!   doc"), "##!")
  check("get_doc_tag: ##%", get_doc_tag("##%   doc"), "##%")
  check("get_doc_tag: ##Z is ##", get_doc_tag("##Z   doc"), "##")
  check("get_doc_tag: no tag", get_doc_tag("!#   doc"), "")
}

# ---------------------------------------------------------------------------------------
# (state, obs) -> state, data and record: the equations of the note (section Model)
# ---------------------------------------------------------------------------------------

# The step table of the note (section Step): r_i, d_i and s_i for each kind, where r, d and s
# are the values before the line (r_bar_{i-1}, d_bar_{i-1}, s_{i-1}) and s!e is s_{i-1} and
# not e_i
function step_table(table) {
  table["recipe"] = "1 0 s"
  table["neutral"] = "r d s"
  table["doc"] = "r 1 s"
  table["section"] = "r d 1"
  table["banner"] = "r 0 s"
  table["rule"] = "1 0 s!e"
  table["special rule"] = "1 d s"
  table["assignment"] = "0 0 s!e"
  table["other"] = "0 0 s"
}

# the value of an entry of step_table, from the state before the line and e_i
function step_entry(entry, r, d, s, e) {
  if (entry == "r") {
    return r
  } else if (entry == "d") {
    return d
  } else if (entry == "s") {
    return s
  } else if (entry == "s!e") {
    return (s && !e) ? 1 : 0
  }
  return entry + 0
}

# parser_step against the step table, for every kind and every state before the line (and
# with and without an inline doc for an anchor), with e_i as in the note
function test_parser_step(    table, kinds, n_kinds, j, kind, cols, r, d, s, a, e, state, obs,
                              got, want, failures) {
  step_table(table)
  n_kinds = split("recipe|neutral|doc|section|banner|rule|special rule|assignment|other",
                  kinds, "|")
  for (j = 1; j <= n_kinds; j++) {
    kind = kinds[j]
    split(table[kind], cols, " ")
    failures = ""
    for (r = 0; r <= 1; r++) {
      for (d = 0; d <= 1; d++) {
        for (s = 0; s <= 1; s++) {
          for (a = 0; a <= 1; a++) {
            if (a && kind != "rule" && kind != "assignment") {
              continue # only an anchor has an inline doc
            }
            split("", state)
            state["r"] = r
            state["d"] = d
            state["s"] = s
            state["c"] = "\t"
            split("", obs)
            obs["kind"] = kind
            obs["inline"] = a
            obs["prefix"] = ">"
            e = ((kind == "rule" || kind == "assignment") && (d || a)) ? 1 : 0
            want = step_entry(cols[1], r, d, s, e) step_entry(cols[2], r, d, s, e) \
                   step_entry(cols[3], r, d, s, e) " e=" e " c=>"
            got = parser_step(state, obs)
            got = state["r"] state["d"] state["s"] " e=" (got ? 1 : 0) " c=" state["c"]
            if (got != want) {
              failures = failures sprintf(" [rds=%d%d%d a=%d: got %s, want %s]", r, d, s, a,
                                          got, want)
            }
          }
        }
      }
    }
    check("parser_step: " kind " (every state before the line)", failures, "")
  }
}

# the pending text, as D/S (the lines of each joined by +) and the tag of D
function data_text(data, #locals
                   text) {
  text = data_lines(data, "doc", data["dn"]) "/" data_lines(data, "section", data["sn"]) \
         "/" (data["dn"] ? data["doc_tag"] : "")
  gsub(/\n/, "+", text)
  return text
}

# the data of one doc line (a) and one section line (s), and a state with d_i and s_i
function carry_setup(data, state, d, s) {
  split("", data)
  data["dn"] = 1
  data["doc", 1] = "a"
  data["doc_tag"] = "##"
  data["sn"] = 1
  data["section", 1] = "s"
  split("", state)
  state["d"] = d
  state["s"] = s
}

# parser_carry against the equations of the data (D_i and S_i)
function test_parser_carry(    data, state, obs) {
  carry_setup(data, state, 1, 1)
  obs["kind"] = "doc"
  obs["text"] = "b"
  obs["tag"] = "##!"
  parser_carry(data, state, obs)
  check("parser_carry: a doc line adds its text (the tag stays that of the first line)",
        data_text(data), "a+b/s/##")

  data["dn"] = 0
  parser_carry(data, state, obs)
  check("parser_carry: the first line of a doc gives its tag", data_text(data), "b/s/##!")

  carry_setup(data, state, 1, 1)
  obs["kind"] = "section"
  obs["text"] = "t"
  parser_carry(data, state, obs)
  check("parser_carry: a section line adds its text", data_text(data), "a/s+t/##")

  carry_setup(data, state, 0, 1)
  obs["kind"] = "rule"
  parser_carry(data, state, obs)
  check("parser_carry: d_i = 0 drops the doc text", data_text(data), "/s/")

  carry_setup(data, state, 1, 0)
  parser_carry(data, state, obs)
  check("parser_carry: s_i = 0 drops the section text", data_text(data), "a//##")

  carry_setup(data, state, 1, 1)
  obs["kind"] = "neutral"
  parser_carry(data, state, obs)
  check("parser_carry: otherwise the text is kept", data_text(data), "a/s/##")
}

# the doc, tag and section (or <none>) of the last record
function last_record() {
  return ANCHORS[ANCHOR_COUNT, "doc"] "|" ANCHORS[ANCHOR_COUNT, "tag"] "|" \
         (((ANCHOR_COUNT, "section") in ANCHORS) ? ANCHORS[ANCHOR_COUNT, "section"] : "<none>")
}

# record_anchor against the equations of the record, and the warning about a redefined doc
function test_record_anchor(    context, obs, before, data) {
  init_globals()
  carry_setup(data, before, 1, 1)
  data["dn"] = 2
  data["doc", 2] = "b"
  obs["anchor"] = "variable"
  obs["name"] = "V"
  obs["inline_doc"] = "i"
  obs["tag"] = "##%"
  context["file"] = "f"
  record_anchor(context, obs, before, data, 7)
  check("record_anchor: d_bar = 1: the pending doc and its tag; s = 1: the section",
        last_record(), "a\nb|##|s")

  before["d"] = 0
  before["s"] = 0
  record_anchor(context, obs, before, data, 9)
  check("record_anchor: d_bar = 0: the inline doc and its tag; s = 0: no section",
        last_record(), "i|##%|<none>")
  check("record_anchor: a redefined doc is reported with its file and line",
        WARNINGS[WARNING_COUNT], "[f:9] redefined docs of variable: V")
  init_globals()
}

function test_form_target_name(    context, obs) {
  init_globals()
  obs["name"] = "a \t b"
  obs["grouped"] = 0
  obs["double"] = 0
  check("form_target_name: blanks collapsed", form_target_name(context, obs), "a b")
  obs["grouped"] = 1
  check("form_target_name: grouped", form_target_name(context, obs), "a b&")

  obs["name"] = "t"
  obs["grouped"] = 0
  obs["double"] = 1
  check("form_target_name: first double-colon rule", form_target_name(context, obs), "t~1")
  check("form_target_name: second double-colon rule", form_target_name(context, obs), "t~2")
}

# ---------------------------------------------------------------------------------------
# lines -> state, data and records: the whole parser, from lines of text
# ---------------------------------------------------------------------------------------

# The states after each physical line of text (lines separated by |), as "rds" (1/0 for
# r, d, s), or "+" for a line that continues on the next one
function trace_lines(text, prefix, #locals
                     state, data, joiner, context, lines, n, k, obs, out) {
  parser_init(state, data, prefix)
  parser_join_init(joiner)
  n = split(text, lines, "|")
  out = ""
  for (k = 1; k <= n; k++) {
    if (parser_join(joiner, lines[k], k)) {
      parser_process(state, data, context, obs, joiner["line"], joiner["start"])
      out = out " " state["r"] state["d"] state["s"]
    } else {
      out = out " +"
    }
  }
  return substr(out, 2)
}

function test_parser_states(    state, data, joiner, context, obs) {
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

  parser_observe("define NO_SPACE+=", obs)
  check("define: an operator without a blank is not part of the name", obs["name"], "NO_SPACE")

  parser_init(state, data, "")
  parser_obs(".RECIPEPREFIX = $(P)", state, obs)
  check("prefix: = keeps the text of a reference", obs["prefix"], "$")
  check("prefix: the observation does not change the state", state["c"], "\t")
  state["c"] = ">"
  parser_obs(".RECIPEPREFIX := $(P)", state, obs)
  check("prefix: an expanded reference is not known", obs["prefix"], ">")
  parser_obs(".RECIPEPREFIX :=", state, obs)
  check("prefix: an empty value is a tab", obs["prefix"], "\t")
  parser_obs("define .RECIPEPREFIX", state, obs)
  check("prefix: a define is not known (its value is on the next lines)", obs["prefix"], ">")
  parser_obs("V := 1", state, obs)
  check("prefix: another line keeps it", obs["prefix"], ">")

  parser_init(state, data, "")
  parser_join_init(joiner)
  parser_join(joiner, "##@ s", 1)
  parser_process(state, data, context, obs, joiner["line"], joiner["start"])
  parser_join(joiner, "## d", 2)
  parser_process(state, data, context, obs, joiner["line"], joiner["start"])
  parser_join(joiner, "t: \\", 3)
  parser_join_init(joiner)
  parser_file_start(state, data)
  check("file start: the doc is dropped, with its text, the section carries over",
        state["d"] " " data["dn"] " " state["s"] " " data["sn"], "0 0 1 1")
  check("file start: a line continued at the end of a file is dropped", joiner["joining"], 0)
}

# the pending text (D and S) after each physical line of text (lines separated by |), as
# D/S with the lines of each joined by +
function trace_data(text, #locals
                    state, data, joiner, context, lines, n, k, obs, out) {
  parser_init(state, data, "")
  parser_join_init(joiner)
  n = split(text, lines, "|")
  out = ""
  for (k = 1; k <= n; k++) {
    if (parser_join(joiner, lines[k], k)) {
      parser_process(state, data, context, obs, joiner["line"], joiner["start"])
      out = out " " data_lines(data, "doc", data["dn"]) "/" \
            data_lines(data, "section", data["sn"])
    }
  }
  gsub(/\n/, "+", out)
  return substr(out, 2)
}

function test_parser_data() {
  check("data: doc and section lines are added without their tokens",
        trace_data("##@ s1|## d1|##! d2|##@ s2"), "/ s1  d1/ s1  d1+ d2/ s1  d1+ d2/ s1+ s2")
  check("data: a directive drops the doc, an undocumented anchor keeps the section",
        trace_data("##@ s|## d|include x|t:"), "/ s  d/ s / s / s")
  check("data: a special rule keeps the doc",
        trace_data("## d|.PHONY: t"), " d/  d/")
  check("data: a documented anchor takes the doc and the section",
        trace_data("##@ s|## d|t:"), "/ s  d/ s /")
  check("data: an inline doc takes the section, not the text of the doc",
        trace_data("##@ s|t: ## i"), "/ s /")
  init_globals()
}

# the doc, tag and section (or <none>) of the last anchor recorded from the lines of text
# (separated by |)
function recorded(text, #locals
                  state, data, joiner, context, lines, n, k, obs) {
  init_globals()
  parser_init(state, data, "")
  parser_join_init(joiner)
  n = split(text, lines, "|")
  for (k = 1; k <= n; k++) {
    if (parser_join(joiner, lines[k], k)) {
      parser_process(state, data, context, obs, joiner["line"], joiner["start"])
    }
  }
  return last_record()
}

function test_parser_records() {
  check("record: the pending doc, with the tag of its first line, and the section",
        recorded("##@ s|##! d1|## d2|t:"), " d1\n d2|##!| s")
  check("record: the pending doc wins over the inline doc", recorded("## d|t: ##% i"),
        " d|##|<none>")
  check("record: the inline doc, without a pending doc", recorded("t: ##% i"), " i|##%|<none>")
  check("record: an empty section is a section", recorded("##@|t: ## i"), " i|##|")
  init_globals()
}

BEGIN {
  # line -> obs: the questions of the observation, the lexical layer
  test_parser_observe()
  test_parser_mask()
  test_parser_reference_end()
  test_parser_special_rules()
  test_parser_variable_names()
  test_parser_inline_docs()
  test_parser_double_colon()
  test_get_doc_tag()

  # (state, obs) -> state, data and record: the equations of the note (section Model)
  test_parser_step()
  test_parser_carry()
  test_record_anchor()
  test_form_target_name()

  # lines -> state, data and records: the whole parser, from lines of text
  test_parser_states()
  test_parser_data()
  test_parser_records()
  done()
}
