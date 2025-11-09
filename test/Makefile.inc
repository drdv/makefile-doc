DEBUG =
PADDING =
HEADER =
DEPRECATED =
COLOR_BACKTICKS =
OUTPUT_FORMAT =

AWK := awk
AWK_FLAGS :=

## associate this with the help target (and not `.PHONY`)
.PHONY: help
## second line in the description of the target help
help:
	@bin/$(AWK) $(AWK_FLAGS) -v PADDING=$(PADDING) \
		-v DEBUG=$(DEBUG) \
		-v DEPRECATED=$(DEPRECATED) \
		-v COLOR_BACKTICKS=$(COLOR_BACKTICKS) \
		-v OUTPUT_FORMAT=$(OUTPUT_FORMAT) \
		-f ../makefile-doc.awk $(MAKEFILE_LIST)

test-10: ##% some target
