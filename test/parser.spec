# The lexical layer of the parser (misc/docs/parser-model.tex): example lines, with what the
# model predicts for each. Every prediction is checked against GNU Make 4.3 (what its
# database, `make -p`, gets from the line).
#
# Format: blocks of `key: value` lines, separated by blank lines; a line that starts with #
# is a comment. A value in brackets keeps its spaces (the first [ and the last ] of the line
# delimit it, so brackets inside are part of the value); a tab is written as it is (the note
# of an example that contains one says so). Keys:
#   id       a short name for the example
#   line     the logical line
#   kind     its kind (see the model): assignment, rule, special rule, neutral, other
#   anchor   what the line documents: target or variable (assignment and rule only)
#   name     the name of the anchor, as written in the line
#   comment  the comment, from its # to the end of the line (absent: no comment)
#   note     why the example matters

id:      hash-in-reference
line:    [V := $(shell echo x#y) # c]
kind:    assignment
anchor:  variable
name:    [V]
comment: [# c]
note:    a # inside a reference is not a comment

id:      dollar-dollar
line:    [V := $$(echo #x)]
kind:    assignment
anchor:  variable
name:    [V]
comment: [#x)]
note:    $$ is a literal $, so $$( does not start a reference

id:      escaped-hash
line:    [V := a\#b # c]
kind:    assignment
anchor:  variable
name:    [V]
comment: [# c]
note:    \# is an escaped #

id:      escaped-backslash-before-hash
line:    [V := a\\# c]
kind:    assignment
anchor:  variable
name:    [V]
comment: [# c]
note:    \\ is an escaped backslash: the # after it starts a comment

id:      colon-in-value
line:    [V := a:b]
kind:    assignment
anchor:  variable
name:    [V]
note:    the operator comes before the colon

id:      conditional-with-equals
line:    [ifeq ($(A),a=b)]
kind:    neutral
note:    more than one word before the =: not an assignment (a conditional)

id:      colon-in-reference-target
line:    [$(subst :,_,a): dep]
kind:    rule
anchor:  target
name:    [$(subst :,_,a)]
note:    a colon inside a reference does not separate the targets

id:      escaped-colon-target
line:    [foo\:bar: dep]
kind:    rule
anchor:  target
name:    [foo\:bar]
note:    \: is an escaped colon

id:      target-specific-prerequisite-form
line:    [t: dep=1]
kind:    assignment
anchor:  target
name:    [t]
note:    an operator after the separating colon: a target-specific assignment

id:      semicolon-in-target-specific
line:    [t: V = a;b # c]
kind:    assignment
anchor:  target
name:    [t]
note:    after the ;, the rest is the value: # does not start a comment

id:      comment-before-semicolon
line:    [t: V = a # c;b]
kind:    assignment
anchor:  target
name:    [t]
comment: [# c;b]
note:    the # comes before the ;

id:      semicolon-in-assignment
line:    [V := a;b # c]
kind:    assignment
anchor:  variable
name:    [V]
comment: [# c]
note:    in an assignment without a separating colon, ; is not special

id:      inline-recipe
line:    [t: dep ; x # c]
kind:    rule
anchor:  target
name:    [t]
note:    after the ;, the rest is the recipe: # does not start a comment

id:      escaped-semicolon
line:    [t: dep \; x # c]
kind:    rule
anchor:  target
name:    [t]
comment: [# c]
note:    an escaped ; does not hide the comment that follows

# ---------------------------------------------------------------------------------------
# Masking: what hides a #
# ---------------------------------------------------------------------------------------

id:      hash-in-brace-reference
line:    [V := ${shell echo x#y} # c]
kind:    assignment
anchor:  variable
name:    [V]
comment: [# c]
note:    ${...} is a reference too

id:      hash-in-nested-reference
line:    [V := $(a $(b #)) # c]
kind:    assignment
anchor:  variable
name:    [V]
comment: [# c]
note:    a reference ends at its matching bracket, past the nested one

id:      hash-in-braces-inside-parentheses
line:    [V = $(a {#}) # c]
kind:    assignment
anchor:  variable
name:    [V]
comment: [# c]
note:    braces do not nest inside $(...), which still hides the #

id:      dollar-dollar-then-reference
line:    [V = $$$(x #) # c]
kind:    assignment
anchor:  variable
name:    [V]
comment: [# c]
note:    $$ then $(...): the first # is inside the reference

id:      three-backslashes-before-hash
line:    [V := a\\\# c]
kind:    assignment
anchor:  variable
name:    [V]
note:    \\ then \#: the # is escaped, so there is no comment

id:      four-backslashes-before-hash
line:    [V := a\\\\# c]
kind:    assignment
anchor:  variable
name:    [V]
comment: [# c]
note:    two \\ pairs: the # starts a comment

id:      hash-in-reference-in-prerequisites
line:    [t: $(shell echo '#') ## doc]
kind:    rule
anchor:  target
name:    [t]
comment: [## doc]
note:    the # inside the reference is hidden, the ## after it starts a comment

# ---------------------------------------------------------------------------------------
# Masking: what hides a colon or an =
# ---------------------------------------------------------------------------------------

id:      colon-in-brace-reference-target
line:    [${subst :,_,a}: dep]
kind:    rule
anchor:  target
name:    [${subst :,_,a}]
note:    a colon inside ${...} does not separate the targets

id:      equals-in-reference-target
line:    [$(subst a,b,x=y): dep]
kind:    rule
anchor:  target
name:    [$(subst a,b,x=y)]
note:    an = inside a reference is not an operator

id:      reference-with-equals-in-prerequisites
line:    [x: $(a:b=c)]
kind:    rule
anchor:  target
name:    [x]
note:    the = of a substitution reference is not an operator: a rule

id:      escaped-equals-is-not-an-escape
line:    [t: x\=y]
kind:    assignment
anchor:  target
name:    [t]
note:    \= is not an escape: the = is an operator (a target-specific assignment)

id:      escaped-space-in-target
line:    [t\ x: dep]
kind:    rule
anchor:  target
name:    [t\ x]
note:    the name is cut from the line, as written

# ---------------------------------------------------------------------------------------
# Masking: what hides a semicolon
# ---------------------------------------------------------------------------------------

id:      semicolon-in-reference
line:    [t: $(x ;) dep ; r # c]
kind:    rule
anchor:  target
name:    [t]
note:    the ; inside the reference is hidden; the second ; starts the recipe

id:      two-backslashes-before-semicolon
line:    [t: dep \\; r # c]
kind:    rule
anchor:  target
name:    [t]
note:    \\ is a pair: the ; starts the recipe, so # does not start a comment

id:      three-backslashes-before-semicolon
line:    [t: dep \\\; r # c]
kind:    rule
anchor:  target
name:    [t]
comment: [# c]
note:    \\ then \;: the ; is escaped, so the # starts a comment

# ---------------------------------------------------------------------------------------
# Operators and qualifiers
# ---------------------------------------------------------------------------------------

id:      operator-equals
line:    [V = 1]
kind:    assignment
anchor:  variable
name:    [V]

id:      operator-question
line:    [V ?= 1]
kind:    assignment
anchor:  variable
name:    [V]

id:      operator-plus
line:    [V += 1]
kind:    assignment
anchor:  variable
name:    [V]

id:      operator-bang
line:    [V != echo 1]
kind:    assignment
anchor:  variable
name:    [V]

id:      operator-double-colon
line:    [V ::= 1]
kind:    assignment
anchor:  variable
name:    [V]
note:    ::= is an operator, not a double-colon rule

id:      operator-without-spaces
line:    [V::=1]
kind:    assignment
anchor:  variable
name:    [V]

id:      qualifiers
line:    [export override V := 1]
kind:    assignment
anchor:  variable
name:    [V]
note:    the qualifiers are not part of the name

id:      qualifier-private
line:    [private V := 1]
kind:    assignment
anchor:  variable
name:    [V]

id:      export-define
line:    [export define V]
kind:    assignment
anchor:  variable
name:    [V]
note:    define after export: a define, not the export directive

id:      export-override-define
line:    [export override define V :=]
kind:    assignment
anchor:  variable
name:    [V]

id:      keyword-as-variable
line:    [include := x]
kind:    assignment
anchor:  variable
name:    [include]
note:    a single word before the operator, even a keyword

id:      conditional-keyword-as-variable
line:    [ifeq := 1]
kind:    assignment
anchor:  variable
name:    [ifeq]

id:      export-without-assignment
line:    [export V]
kind:    other
note:    a directive (no operator)

id:      two-words-before-operator
line:    [a b = 1]
kind:    other
note:    not an assignment (GNU Make rejects the line: missing separator)

# ---------------------------------------------------------------------------------------
# Rules
# ---------------------------------------------------------------------------------------

id:      rule-without-prerequisites
line:    [t:]
kind:    rule
anchor:  target
name:    [t]

id:      double-colon-rule
line:    [t:: dep]
kind:    rule
anchor:  target
name:    [t]
note:    the name does not include the second colon

id:      grouped-targets
line:    [g1 g2 &: dep ; true]
kind:    rule
anchor:  target
name:    [g1 g2]
note:    the name does not include the &

id:      order-only-prerequisites
line:    [t: | oo]
kind:    rule
anchor:  target
name:    [t]

id:      static-pattern-rule
line:    [a.o: %.o: %.c]
kind:    rule
anchor:  target
name:    [a.o]
note:    the first separating colon ends the targets

id:      special-target
line:    [.SUFFIXES: .c]
kind:    special rule
note:    special targets are not documented
