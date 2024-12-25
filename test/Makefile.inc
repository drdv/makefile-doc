CONNECTED =
PADDING =
HEADER =
DEPRECATED =
COLOR_BACKTICKS =

AWK := awk
AWK_FLAGS :=

## ignored when CONNECTED = 1 (the default)

## associate this with the help target (and not `.PHONY`)
.PHONY: help
## second line in the description of the target help
help:
	@bin/$(AWK) $(AWK_FLAGS) -v PADDING=$(PADDING) \
		-v CONNECTED=$(CONNECTED) \
		-v DEPRECATED=$(DEPRECATED) \
		-v COLOR_BACKTICKS=$(COLOR_BACKTICKS) \
		-f ../makefile-doc.awk $(MAKEFILE_LIST)

test-10: ##% some target

##@
##@ ----- Double-column targets -----
##@

## This is the first double-colon target from group A
## It has two lines of description
double-colon-A::

double-colon-B:: ##! group B first documented

double-colon-B:: # not documented

double-colon-B:: ## group B second documented

double-colon-A:: ## This is the second double-colon target from group A

double-colon-B:: ##% group B third documented (deprecated)
