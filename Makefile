SHELL := bash
# --output-sync needs GNU make >= 4.0
MAKEFLAGS := --no-print-directory --warn-undefined-variables --output-sync=target
TEST_DIR := test

## Tool used to download the awk variants {curl, wget}
DOWNLOAD_TOOL ?= curl
DOWNLOAD_curl = curl -fsSL --create-dirs --output-dir $(AWK_BIN) -O
DOWNLOAD_wget = wget -P $(AWK_BIN)

INTEGRATION_TEST_DIR := $(TEST_DIR)/integration
INTEGRATION_TESTS := $(notdir $(wildcard $(INTEGRATION_TEST_DIR)/*))

# Known bugs: same format as integration tests, but the expected output is the
# correct one, so they fail until the bug is fixed.
BUG_TEST_DIR := $(TEST_DIR)/bugs
BUGS := $(notdir $(wildcard $(BUG_TEST_DIR)/*))
BUG_TARGETS := $(addprefix bug-,$(BUGS))

# script that runs a single test recipe file (see its header for the format)
RUN_RECIPE := $(TEST_DIR)/run-recipe.sh

UNIT_TEST_DIR := $(TEST_DIR)/unit
UNIT_TESTS := $(subst $(UNIT_TEST_DIR)/unittest.awk,,$(wildcard $(UNIT_TEST_DIR)/*.awk))
# we want unittest.awk to be the first one in the list
UNIT_TESTS_AWK_FLAGS := -f $(UNIT_TEST_DIR)/unittest.awk $(patsubst %,-f %,$(UNIT_TESTS))

## Supported awk variants:
AWK := awk
AWK_FLAGS :=
AWK_BIN := $(TEST_DIR)/bin
SUPPORTED_AWK_VARIANTS := awk mawk nawk bawk wak goawk

# one target per awk variant: test@awk, test@mawk, ...
TEST_ALL := $(addprefix test@,$(SUPPORTED_AWK_VARIANTS))
UTEST_ALL := $(addprefix utest@,$(SUPPORTED_AWK_VARIANTS))
BUGS_ALL := $(addprefix bugs@,$(SUPPORTED_AWK_VARIANTS))

## {ansi, html}
OUTPUT_FORMAT :=
EXPORT_THEME :=

## If set, the expected value of a test recipe is updated
## e.g., `make test-default UPDATE_RECIPE=1`
UPDATE_RECIPE :=

MAKEFILE_DOC := makefile-doc.awk
COVER_DIR := coverage-reports

.PHONY: help
## Show this help
help: AWK_SUB := <L:0,M:0,I:{,T:},S:\\,>AWK:$(foreach x,$(SUPPORTED_AWK_VARIANTS),`$(x)`)
help: TESTS_SUB := <L:1,M:1>$$(INTEGRATION_TESTS):test-:$(wordlist 1,5,$(subst test-,,$(INTEGRATION_TESTS))) ...
help: VFLAGS := \
	-v SUB='$(TESTS_SUB);$(AWK_SUB)' \
	-v EXPORT_THEME=$(EXPORT_THEME) \
	-v COLOR_BACKTICKS=33 \
	-v OUTPUT_FORMAT=$(OUTPUT_FORMAT)
help: $(AWK_BIN)/$(AWK)
	@$< $(VFLAGS) $(AWK_FLAGS) -f $(MAKEFILE_DOC) $(MAKEFILE_LIST)

##@
##@------ Tests (AWK=<variant> selects the awk) ------
##@

## Run integration tests
.PHONY: test
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
		-f $(MAKEFILE_DOC) \
		$(AWK_FLAGS) \
		/dev/null
	@rm /tmp/.makefile-doc-stderr

## Run tests of known bugs, all of them even if one fails (see test/README.md)
.PHONY: bugs
bugs:
	@$(if $(BUG_TARGETS),$(MAKE) -k $(BUG_TARGETS),:)

##@
##@------ All awk variants (use `make -k` to continue after a failure) ------
##@

## Run integration tests with all supported awk variants
.PHONY: test-all
test-all: $(TEST_ALL)

## Run unit tests with all supported awk variants
.PHONY: utest-all
utest-all: $(UTEST_ALL)

## Run tests of known bugs with all supported awk variants
.PHONY: bugs-all
bugs-all: $(BUGS_ALL)

.PHONY: $(TEST_ALL) $(UTEST_ALL) $(BUGS_ALL)
$(TEST_ALL): test@%:
	@$(MAKE) test AWK=$*
$(UTEST_ALL): utest@%:
	@$(MAKE) utest AWK=$*
$(BUGS_ALL): bugs@%:
	@$(MAKE) bugs AWK=$*

##@
##@------ Coverage ------
##@

## Run integration/unit tests with `goawk` and generate a coverage report (coverage-reports/all.html)
.PHONY: coverage
coverage: $(COVER_DIR)/all.html

$(COVER_DIR)/all.html: $(COVER_DIR)/integration.html $(COVER_DIR)/unit.html
	@{ cat $(COVER_DIR)/integration.out; tail -n +2 $(COVER_DIR)/unit.out; } > $(COVER_DIR)/all.out
	@go tool cover -html=$(COVER_DIR)/all.out -o $@

# Run the integration tests with goawk and generate a coverage report
$(COVER_DIR)/integration.html: override AWK := goawk
$(COVER_DIR)/integration.html: AWK_FLAGS := -coverprofile $(COVER_DIR)/integration.out -coverappend
$(COVER_DIR)/integration.html: $(MAKEFILE_DOC) $(foreach recipe,$(INTEGRATION_TESTS),$(INTEGRATION_TEST_DIR)/$(recipe)) | $(COVER_DIR)
	@$(MAKE) test AWK=$(AWK) AWK_FLAGS='$(AWK_FLAGS)'
	@go tool cover -html=$(COVER_DIR)/integration.out -o $@

# Run the unit tests with goawk and generate a coverage report
$(COVER_DIR)/unit.html: override AWK := goawk
$(COVER_DIR)/unit.html: override AWK_FLAGS := -coverprofile $(COVER_DIR)/unit.out -coverappend
$(COVER_DIR)/unit.html: utest | $(COVER_DIR)
	@go tool cover -html=$(COVER_DIR)/unit.out -o $@

$(COVER_DIR):
	@mkdir -p $@

##@
##@------ Lint ------
##@

## Lint the code using `gawk`
# Warnings to ignore have been stripped below
.PHONY: lint
lint: UNINIT := (sub_array|COLOR_.*|VARS|OFFSET|PADDING|DEPRECATED|RECIPEPREFIX|AWK|\
				|TARGETS_REGEX|VARIABLES_REGEX|OUTPUT_FORMAT|EXPORT_THEME|UNIT_TEST)
lint: override AWK := awk
lint: check-variables
	@$(AWK_BIN)/$(AWK) --lint \
		-v SHOW_HELP=0 \
		-v UNIT_TEST=0 \
		$(UNIT_TESTS_AWK_FLAGS) \
		-f $(MAKEFILE_DOC) 2>&1 | \
		grep -vE "reference to uninitialized .* \`$(UNINIT)'" || echo "lint: OK"

## Verify that there are no unintended global variables
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

##@
##@------ Housekeeping ------
##@

.PHONY: clean-bin
clean-bin: ##! Remove all downloaded awk variants
	@rm -rf $(AWK_BIN)

.PHONY: clean
clean: ## Remove coverage reports
	@rm -rf $(COVER_DIR)

##! Create github release at latest tag
.PHONY: release
release: LATEST_TAG := $(shell git describe --tags)
release: RELEASE_NOTES := release_notes.md
release:
	@test -f $(RELEASE_NOTES) && \
	gh release create $(LATEST_TAG) $(MAKEFILE_DOC) \
		--generate-notes \
		--notes-file $(RELEASE_NOTES) -t '$(LATEST_TAG)' || \
	echo "No file $(RELEASE_NOTES)"

##@
##@------ Individual integration tests ------
##@

## Recipes:
## ---------

# The logic is in $(RUN_RECIPE). Tests that must pass use mode `test`, known
# bugs use mode `bug` (they fail when they start passing), and UPDATE_RECIPE=1
# switches to mode `update`.
$(INTEGRATION_TESTS): $(AWK_BIN)/$(AWK)
	@MAKEFILE_DOC=$(MAKEFILE_DOC) $(RUN_RECIPE) $(if $(filter 1 yes,$(UPDATE_RECIPE)),update,test) \
		$< $(INTEGRATION_TEST_DIR)/$@ $(AWK_FLAGS)

$(BUG_TARGETS): $(AWK_BIN)/$(AWK)
	@MAKEFILE_DOC=$(MAKEFILE_DOC) $(RUN_RECIPE) bug \
		$< $(BUG_TEST_DIR)/$(patsubst bug-%,%,$@) $(AWK_FLAGS)

# --------------------------------------------------------------------------
# Internal stuff
# --------------------------------------------------------------------------
demo.html: Makefile
	@$(MAKE) help OUTPUT_FORMAT=html EXPORT_THEME=BG:000000,FG:F7F7F7 > $@

demo.pdf: %.pdf : Makefile
	@$(MAKE) help OUTPUT_FORMAT=latex EXPORT_THEME=BG:000000,FG:F7F7F7 > $*.tex
	@tectonic $*.tex
	@rm -f $*.tex

demo.png: DPI := 300
demo.png: %.png : demo.pdf Makefile
	@magick -density $(DPI) $*.pdf -quality 90 $@
	@rm -f $*.pdf

.PHONY: misc-bugs-bawk
misc-bugs-bawk: PARAMS := -v a=0 -f misc/busybox_awk_bug_20251107.awk
misc-bugs-bawk:
	@$(AWK_BIN)/bawk $(PARAMS)
	@podman run -it --rm -v $(PWD):/work:Z -w /work docker.io/library/busybox:latest awk $(PARAMS)

# awk variants (downloads); kept last so that `help` lists them last
include $(TEST_DIR)/awk-variants.mk
