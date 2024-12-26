include Makefile.inc

TARGET-NAME := target-from-var

test-1: ## test inline docs without top docs

## test inline docs with top docs
test-2: ## this inline doc will not be displayed because of the top doc

## test multi-line top docs
## this will not be displayed because target test-3 is redefined below
## and the new test-3 has its own docs
## add one more line that shouldn't appear
test-3:

## target test-3 is defined twice
## this one will override the one above (and discard its docs)
##   indentation can be used for emphasis
test-3:

# overrides the previous target test-2 but not its docs
# unless the single-# comments are turned into double-# comments
test-2:

##! use exclamation mark for targets that are signifficant in some way
## shouldn't have an exclamation mark for subsequent notes
test-4:

##@
##@ ----- Section 1 -----
##@

## this is not shown due to the blank like (see IGNORE_EMPTY)

test-5: ##! but this will be shown instead

##% this target is kept just in case
## even though it is obsolete
   ## some note (space befor ## is stripped)
#
# INVISIBLE COMMENTS LINKING THE 4 LINES
#
## note that the above three lines are not dropped
test-6:

test-7: ##% deprecated target with inline doc

## target test-8 depends on target test-6
test-8: test-6 ## not displayed

test-9: test-6 ## target test-9 depends on target test-6 as well

##% this is overridden in Makefile.inc as it is processed second
test-10:

%.c: ## here is a pattern rule

## and here is another one
%.o: %.c

bin/%.o: %.c ## and yet another one

## this description will not be shown due to the blank line

## three targets on one line with spaces between them
first second third:

%.tab.c %.tab.h: %.y ## target with dots in the names

##@
##@ ----- Section 2 -----
##@

$(TARGET-NAME): ## target stored in a variable

##! target stored in a variable
## make with issue a warning that this target
## overrides the one above (if they are not empty)
## but the awk script doesn't detect this becuase it
## doesn't have access to the value of TARGET-NAME.
${TARGET-NAME}:

## target with spaces before and after
  target-with-spaces  :

target-without-docs:

t: ## A one letter target
