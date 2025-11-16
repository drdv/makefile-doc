SHELL := bash
MAKEFLAGS := --no-print-directory --warn-undefined-variables
TEST_DIR := test

INTEGRATION_TEST_DIR := $(TEST_DIR)/integration
INTEGRATION_TESTS := $(notdir $(wildcard $(INTEGRATION_TEST_DIR)/*))

UNIT_TEST_DIR := $(TEST_DIR)/unit
UNIT_TESTS := $(subst $(UNIT_TEST_DIR)/unittest.awk,,$(wildcard $(UNIT_TEST_DIR)/*.awk))
# we want unittest.awk to be the first one in the list
UNIT_TESTS_AWK_FLAGS := -f $(UNIT_TEST_DIR)/unittest.awk $(patsubst %,-f %,$(UNIT_TESTS))

## Supported awk variants:
AWK := awk
AWK_FLAGS :=
AWK_BIN := $(TEST_DIR)/bin
SUPPORTED_AWK_VARIANTS := awk mawk nawk bawk wak goawk

## {ansi, html}
OUTPUT_FORMAT :=

## If set, the expected value of a test recipe is updated
## e.g., `make test-default UPDATE_RECIPE=1`
UPDATE_RECIPE :=

MAKEFILE_DOC := makefile-doc.awk
COVER_FILE := coverage

# using $1 instead of $(AWK) is necessary for a target like
# deps: $(AWK_BIN)/mawk $(AWK_BIN)/nawk $(AWK_BIN)/bawk $(AWK_BIN)/wak
define verify-download
	read -p "Download and build $1 [Y/n]: " ans \
		&& ([ -z $$ans ] || [ $$ans = y ] || [ $$ans = Y ]) \
		&& exit 0 \
		|| echo "Download of $1 cancelled"; exit 1
endef

.PHONY: help
## Show this help
help: AWK_SUB := <L:0,M:0,I:{,T:},S:\\,>AWK:$(foreach x,$(SUPPORTED_AWK_VARIANTS),`$(x)`)
help: TESTS_SUB := <L:1,M:1>$$(INTEGRATION_TESTS):test-:$(wordlist 1,5,$(subst test-,,$(INTEGRATION_TESTS))) ...
help: VFLAGS := \
	-v SUB='$(TESTS_SUB);$(AWK_SUB)' \
	-v COLOR_BACKTICKS=33 \
	-v OUTPUT_FORMAT=$(OUTPUT_FORMAT)
help: $(AWK_BIN)/$(AWK)
	@$< $(VFLAGS) $(AWK_FLAGS) -f $(MAKEFILE_DOC) $(MAKEFILE_LIST)

.PHONY: test
## Run integration tests
test: $(INTEGRATION_TESTS)

## Run unit tests
.PHONY: utest
utest: UNITTEST_VERBOSE :=
utest: $(AWK_BIN)/$(AWK) $(MAKEFILE_DOC) $(UNIT_TESTS) $(UNIT_TEST_DIR)/unittest.awk
	@$(AWK_BIN)/$(AWK) \
		-v AWK=$(AWK) \
		-v UNIT_TEST=1 \
		-v UNITTEST_VERBOSE=$(UNITTEST_VERBOSE) \
		$(UNIT_TESTS_AWK_FLAGS) \
		-f makefile-doc.awk \
		$(AWK_FLAGS) \
		/dev/null
	@rm /tmp/.makefile-doc-stderr

.PHONY: test-all-awk
## Run integration tests with all supported awk variants
test-all:
	@$(foreach X,$(SUPPORTED_AWK_VARIANTS),$(MAKE) test AWK=$(X);)

.PHONY: utest-all-awk
## Run unit tests with all supported awk variants
utest-all:
	@$(foreach X,$(SUPPORTED_AWK_VARIANTS),$(MAKE) utest AWK=$(X);)

## Run integration/unit tests with `goawk` and generate a coverage report
coverage.html: coverage-tests.html coverage-utests.html
	@{ cat $(COVER_FILE).integration; tail -n +2 $(COVER_FILE).unit; } > $(COVER_FILE).all
	@go tool cover -html=$(COVER_FILE).all -o $@

# Run the integration tests with goawk and generate a coverage report
coverage-tests.html: override AWK := goawk
coverage-tests.html: AWK_FLAGS := -coverprofile $(COVER_FILE).integration -coverappend
coverage-tests.html: $(MAKEFILE_DOC) $(foreach recipe,$(INTEGRATION_TESTS),$(INTEGRATION_TEST_DIR)/$(recipe))
	@$(MAKE) test AWK=$(AWK) AWK_FLAGS='$(AWK_FLAGS)'
	@go tool cover -html=$(COVER_FILE).integration -o $@

# Run the unit tests with goawk and generate a coverage report
coverage-utests.html: override AWK := goawk
coverage-utests.html: override AWK_FLAGS := -coverprofile $(COVER_FILE).unit -coverappend
coverage-utests.html: utest
	@go tool cover -html=$(COVER_FILE).unit -o $@

## Lint the code using `gawk`
# Warnings to ignore have been stripped below
lint: UNINIT := (|SUB|COLOR_.*|VARS|OFFSET|PADDING|DEPRECATED|RECIPEPREFIX|\
				|TARGETS_REGEX|VARIABLES_REGEX|OUTPUT_FORMAT|EXPORT_THEME|UNIT_TEST)
lint: override AWK := awk
lint: check-variables
	@$(AWK_BIN)/$(AWK) --lint \
		-v SHOW_HELP=0 \
		-v UNIT_TEST=0 \
		$(UNIT_TESTS_AWK_FLAGS) \
		-f $(MAKEFILE_DOC) 2>&1 | \
		grep -vE "reference to uninitialized variable \`$(UNINIT)'" || echo "lint: OK"

# Verify for unintended global variables
.PHONY: check-variables
check-variables: AWK_CODE := '\
	{ v=$$1; if (v !~ /^[A-Z_]+$$/ && v !~ /^g_[a-z_]+$$/) a[k++]=v }\
	END { if (length(a) == 0) print "check-variables: OK"; else \
	{for(k in a) print "["a[k]"] violates naming rules"} }'
check-variables: AWKVARS_FILE := awkvars.out
check-variables:
	@$(AWK_BIN)/awk -v SHOW_HELP=0 -d$(AWKVARS_FILE) -f $(MAKEFILE_DOC) || exit 0
	@cat $(AWKVARS_FILE) | $(AWK) -F: $(AWK_CODE)
	@rm -f $(AWKVARS_FILE)

.PHONY: clean-bin
clean-bin: ##! Remove all downloaded awk variants
	@rm -rf $(AWK_BIN)

## Remove coverage reports
.PHONY: clean
clean:
	@rm -f $(COVER_FILE).all $(COVER_FILE).integration $(COVER_FILE).unit \
			coverage-tests.html coverage-utests.html coverage.html

.PHONY: release
##! Create github release at latest tag
release: LATEST_TAG := $(shell git describe --tags)
release: RELEASE_NOTES := release_notes.md
release:
	@test -f $($(RELEASE_NOTES)) && \
	gh release create $(LATEST_TAG) $(MAKEFILE_DOC) \
		--generate-notes \
		--notes-file $(RELEASE_NOTES) -t '$(LATEST_TAG)' || \
	echo "No file $(RELEASE_NOTES)"

##@
##@------ Individual integration tests ------
##@

## Recipes:
## ---------

# Now we redirect to actual files because making sure that stderr and stdout
# appear in the righ order with all AWK variants (in particular goawk) and on
# CI was problematic
$(INTEGRATION_TESTS): FILE_CMD = /tmp/.makefile-doc_$@_command
$(INTEGRATION_TESTS): FILE_EXPECTED = /tmp/.makefile-doc_$@_expected
$(INTEGRATION_TESTS): FILE_ACTUAL = /tmp/.makefile-doc_$@_actual
$(INTEGRATION_TESTS): RECIPE_CMD = $(shell head -n 1 $(INTEGRATION_TEST_DIR)/$@)
$(INTEGRATION_TESTS): $(AWK_BIN)/$(AWK)
	@echo "$(subst $,\$,$(RECIPE_CMD))" > $(FILE_CMD);
	@tail -n +2 $(INTEGRATION_TEST_DIR)/$@ > $(FILE_EXPECTED)
	@$< -f $(MAKEFILE_DOC) $(AWK_FLAGS) $(RECIPE_CMD) \
		> $(FILE_ACTUAL).stdout 2> $(FILE_ACTUAL).stderr || exit 0
	@{ cat $(FILE_ACTUAL).stderr; cat $(FILE_ACTUAL).stdout; } > $(FILE_ACTUAL)
# --ignore-space-at-eol is needed as empty descriptions add OFFSET
	@$(if $(filter 1 yes,$(UPDATE_RECIPE)),\
		{ cat $(FILE_CMD); cat $(FILE_ACTUAL); } | tee -a $(FILE_ACTUAL).recipe && \
			mv $(FILE_ACTUAL).recipe $(INTEGRATION_TEST_DIR)/$@,\
		@git diff --ignore-space-at-eol $(FILE_EXPECTED) $(FILE_ACTUAL) ||\
			(echo "failed $@"; exit 1) && echo "[$(notdir $<)] passed $@")
	@rm -f $(FILE_CMD) $(FILE_EXPECTED) $(FILE_ACTUAL)*

# --------------------------------------------------------------------------
# Targets for downloading various awk implementations
# --------------------------------------------------------------------------
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

# --------------------------------------------------------------------------
# Internal stuff
# --------------------------------------------------------------------------
demo.html: Makefile
	@$(MAKE) help OUTPUT_FORMAT=html > $@

demo.pdf: %.pdf : Makefile
	@$(MAKE) help OUTPUT_FORMAT=latex > $*.tex
	@tectonic $*.tex
	@rm -f $*.tex

demo.png: DPI := 300
demo.png: %.png : demo.pdf Makefile
	@magick -density $(DPI) $*.pdf -quality 90 $@
	@rm -f $*.pdf

bugs-bawk: PARAMS := -v a=0 -f misc/busybox_awk_bug_20251107.awk
bugs-bawk:
	@$(AWK_BIN)/bawk $(PARAMS)
	@podman run -it --rm -v $(PWD):/work:Z -w /work docker.io/library/busybox:latest awk $(PARAMS)
