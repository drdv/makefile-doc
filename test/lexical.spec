# The lexical layer of the parser (misc/docs/parser-model.tex): example lines, with what the
# model predicts for each. Every prediction is checked against GNU Make 4.3 (what its
# database, `make -p`, gets from the line).
#
# Format: blocks of `key: value` lines, separated by blank lines; a line that starts with #
# is a comment. A value in brackets keeps its spaces (the first [ and the last ] of the line
# delimit it, so brackets inside are part of the value); \t stands for a tab. Keys:
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
