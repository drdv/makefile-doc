CONNECTED =
PADDING =
HEADER =
DEPRECATED =

## ignored when CONNECTED = 1 (the default)

## associate this with the help target (and not .PHONY)
.PHONY: help
## second line in the description of the target help
help:
	@awk -v PADDING=$(PADDING) \
		-v HEADER=$(HEADER) \
		-v CONNECTED=$(CONNECTED) \
		-v DEPRECATED=$(DEPRECATED) \
		-f ../makefile-doc.awk $(MAKEFILE_LIST)

test-10: ##% some target
