SHELL := bash
TEST_DIR := test
TEST_RECIPES_DIR := $(TEST_DIR)/recipes

TESTS := $(notdir $(wildcard $(TEST_RECIPES_DIR)/*))

## supported awk variants:
AWK := awk
AWK_FLAGS :=
AWK_BIN := $(TEST_DIR)/bin
SUPPORTED_AWK_VARIANTS := awk mawk nawk bawk wak goawk

## {ansi, html}
OUTPUT_FORMAT :=

## if set, debug info is generated in an org file
DEBUG :=

## if set, the expected value of a test recipe is updated
## e.g., `make test-default UPDATE_RECIPE=1`
UPDATE_RECIPE :=

MAKEFILE_DOC := makefile-doc.awk

# using $1 instead of $(AWK) is necessary for a target like
# deps: $(AWK_BIN)/mawk $(AWK_BIN)/nawk $(AWK_BIN)/bawk $(AWK_BIN)/wak
define verify-download
	read -p "Download and build $1 [Y/n]: " ans \
		&& ([ -z $$ans ] || [ $$ans = y ] || [ $$ans = Y ]) \
		&& exit 0 \
		|| echo "Download of $1 cancelled"; exit 1
endef

.PHONY: help
## show this help
help: AWK_SUB := <L:0,M:0,I:{,T:},S:\\,>AWK:$(foreach x,$(SUPPORTED_AWK_VARIANTS),`$(x)`)
help: TESTS_SUB := <L:1,M:1>$$(TESTS):test-:$(wordlist 1,5,$(subst test-,,$(TESTS))) ...
help: VFLAGS := \
	-v SUB='$(TESTS_SUB);$(AWK_SUB)' \
	-v DEBUG=$(DEBUG) \
	-v COLOR_BACKTICKS=33 \
	-v OUTPUT_FORMAT=$(OUTPUT_FORMAT)
help: $(AWK_BIN)/$(AWK)
	@$< $(VFLAGS) $(AWK_FLAGS) -f $(MAKEFILE_DOC) $(MAKEFILE_LIST)

deploy-local: DEPLOY_DIR := $(HOME)/.local/share/makefile-doc
deploy-local:
	@mkdir -p $(DEPLOY_DIR)
	@cp $(MAKEFILE_DOC) $(DEPLOY_DIR)

.PHONY: test
## run all tests
test: $(TESTS)

.PHONY: test-all-awk
## run all tests with all supported awk variants
test-all-awk:
	@$(foreach X,$(SUPPORTED_AWK_VARIANTS),$(MAKE) --no-print-directory test AWK=$(X);)

## run the tests with goawk and generate a coverage report
cover.html: AWK := goawk
cover.html: COVER_FILE := cover.out
cover.html: AWK_FLAGS := -coverprofile $(COVER_FILE) -coverappend
cover.html: $(MAKEFILE_DOC) $(foreach recipe,$(TESTS),$(TEST_RECIPES_DIR)/$(recipe))
	@$(MAKE) --no-print-directory test AWK=$(AWK) AWK_FLAGS='$(AWK_FLAGS)'
	@go tool cover -html=$(COVER_FILE) -o $@
	@rm -f $(COVER_FILE)

## lint the code using gawk
# Warnings to ignore have been stripped below
lint: UNINIT := (DEBUG|DEBUG_FILE|DEBUG_INDENT_STACK|SUB|COLOR_.*|VARS|OFFSET|PADDING|\
		|CONNECTED|DEPRECATED|TARGETS_REGEX|VARIABLES_REGEX|OUTPUT_FORMAT|EXPORT_THEME)
lint: check-variables
	@awk --lint -v SHOW_HELP=0 -f $(MAKEFILE_DOC) 2>&1 | \
		grep -vE "reference to uninitialized variable \`$(UNINIT)'" || echo "lint: OK"

## verify for unintended global variables
check-variables: AWK_CODE := '\
	{ v=$$1; if (v !~ /^[A-Z_]+$$/ && v !~ /^g_[a-z_]+$$/) a[k++]=v }\
	END { if (length(a) == 0) print "check-variables: OK"; else \
	{for(k in a) print "["a[k]"] violates naming rules"} }'
check-variables: AWKVARS_FILE := awkvars.out
check-variables:
	@$(AWK) -v SHOW_HELP=0 -d$(AWKVARS_FILE) -f $(MAKEFILE_DOC) || exit 0
	@cat $(AWKVARS_FILE) | $(AWK) -F: $(AWK_CODE)
	@rm -f $(AWKVARS_FILE)

.PHONY: clean-bin
clean-bin: ##! remove all downloaded awk variants
	@rm -rf $(AWK_BIN)

.PHONY: release
##! create github release at latest tag
release: LATEST_TAG := $(shell git describe --tags)
release: RELEASE_NOTES := release_notes.md
release:
	@test -f $($(RELEASE_NOTES)) && \
	gh release create $(LATEST_TAG) $(MAKEFILE_DOC) \
		--generate-notes \
		--notes-file $(RELEASE_NOTES) -t '$(LATEST_TAG)' || \
	echo "No file $(RELEASE_NOTES)"

%.png: DPI := 300
%.png: %.pdf Makefile
	@magick -density $(DPI) $*.pdf -quality 90 $@
	@rm -f $*.pdf

%.pdf: Makefile
	@$(MAKE) --no-print-directory help OUTPUT_FORMAT=latex > $*.tex
	@tectonic $*.tex
	@rm -f $*.tex

%.html: Makefile
	@$(MAKE) --no-print-directory help OUTPUT_FORMAT=html > $*.html

bugs-bawk: PARAMS := -v a=0 -f misc/busybox_awk_bug_20251107.awk
bugs-bawk:
	@$(AWK_BIN)/bawk $(PARAMS)
	@podman run -it --rm -v $(PWD):/work:Z -w /work docker.io/library/busybox:latest awk $(PARAMS)

##@
##@------ Individual tests ------
##@

## Recipes:
## ---------
$(TESTS): RECIPE_COMMAND_LINE = $(shell head -n 1 $(TEST_RECIPES_DIR)/$@)
$(TESTS): CMD_RECIPE_EXPECTED = tail -n +2 $(TEST_RECIPES_DIR)/$@
$(TESTS): CMD_RESULT = $< -f $(MAKEFILE_DOC) $(AWK_FLAGS) $(RECIPE_COMMAND_LINE)
# --ignore-space-at-eol is needed as empty descriptions add OFFSET
$(TESTS): CMD_DIFF = git diff --ignore-space-at-eol \
		<($(CMD_RECIPE_EXPECTED)) \
		<($(CMD_RESULT) 2>&1)
$(TESTS): TMP_FILE = /tmp/$@_updated
$(TESTS): $(AWK_BIN)/$(AWK)
# The reason for using echo "$(subst $,\$,$(RECIPE_COMMAND_LINE))" is that, the value of
# RECIPE_COMMAND_LINE may contain e.g., $(TARGET) and we need to make sure that the
# shell doesn't try to expand it. Unfortunately, we cannot simply use echo
# '$(RECIPE_COMMAND_LINE)' because the value of RECIPE_COMMAND_LINE already contains
# single quotes. While it doesn't contain doble-quotes, doing echo
# "$(RECIPE_COMMAND_LINE)" is not possible because the single quotes around $(TARGET)
# loose their "powers" when surrounded by double-quotes. So we have to escape the $.
	@$(if $(UPDATE_RECIPE),\
		echo "$(subst $,\$,$(RECIPE_COMMAND_LINE))" > $(TMP_FILE);\
		$(CMD_RESULT)\
		| tee -a $(TMP_FILE) && mv $(TMP_FILE) $(TEST_RECIPES_DIR)/$@,\
	$(CMD_DIFF) || (echo "failed $@"; exit 1) && echo "[$(notdir $<)] passed $@")

# ----------------------------------------------------
# Targets for downloading various awk implementations
# ----------------------------------------------------

$(AWK_BIN)/awk:
	@mkdir -p $(AWK_BIN)
	@ln -s $(shell which awk) $@

$(AWK_BIN)/mawk: URL := invisible-island.net/datafiles/release/mawk.tar.gz
$(AWK_BIN)/mawk:
	@$(call verify-download,mawk)
	@wget -P $(AWK_BIN) $(URL)
	@mkdir -p $@-src
	@tar xvf $(AWK_BIN)/mawk.tar.gz -C $@-src --strip-components=1
	@cd $@-src && ./configure && make
	@cp $@-src/mawk $@

$(AWK_BIN)/nawk: RELEASE := 20240728
$(AWK_BIN)/nawk: URL := github.com/onetrueawk/awk/archive/refs/tags/$(RELEASE).tar.gz
$(AWK_BIN)/nawk:
	@$(call verify-download,nawk)
	@wget -P $(AWK_BIN) $(URL)
	@mkdir -p $@-src
	@tar xvf $(AWK_BIN)/$(RELEASE).tar.gz -C $@-src --strip-components=1
	@cd $@-src && make
	@cp $@-src/a.out $@

$(AWK_BIN)/bawk: URL := busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox_AWK
$(AWK_BIN)/bawk:
ifeq ($(shell uname),Darwin)
	@echo "Busybox awk binaries not available for macos"
	@exit 1
else
	@$(call verify-download,bawk)
	@wget -P $(AWK_BIN) $(URL)
	@mv $(AWK_BIN)/busybox_AWK $@ && chmod +x $@
endif

$(AWK_BIN)/wak: RELEASE := v24.10
$(AWK_BIN)/wak: URL := github.com/raygard/wak/archive/refs/tags/$(RELEASE).tar.gz
$(AWK_BIN)/wak:
	@$(call verify-download,wak)
	@wget -P $(AWK_BIN) $(URL)
	@mkdir -p $@-src
	@tar xvf $(AWK_BIN)/$(RELEASE).tar.gz -C $@-src --strip-components=1
	@cd $@-src && make
	@cp $@-src/wak $@

# requires: sudo dnf install golang
$(AWK_BIN)/goawk: RELEASE := v1.30.0
$(AWK_BIN)/goawk: URL := github.com/benhoyt/goawk/archive/refs/tags/$(RELEASE).tar.gz
$(AWK_BIN)/goawk:
	@$(call verify-download,goawk)
	@wget -P $(AWK_BIN) $(URL)
	@mkdir -p $@-src
	@tar xvf $(AWK_BIN)/$(RELEASE).tar.gz -C $@-src --strip-components=1
	@cd $@-src && go build -o goawk goawk.go
	@cp $@-src/goawk $@

$(AWK_BIN)/%: # a catch-all target for AWK values
	@echo "==================================================="
	@echo "Supported AWK variants: $(SUPPORTED_AWK_VARIANTS)"
	@echo "==================================================="
	@exit 1
