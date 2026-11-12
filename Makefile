SHELL := bash
# --output-sync needs GNU make >= 4.0
MAKEFLAGS := --no-print-directory --warn-undefined-variables --output-sync=target
TEST_DIR := test

INTEGRATION_TEST_DIR := $(TEST_DIR)/integration
INTEGRATION_TESTS := $(notdir $(wildcard $(INTEGRATION_TEST_DIR)/*))

UNIT_TEST_DIR := $(TEST_DIR)/unit
UNIT_TESTS := $(wildcard $(UNIT_TEST_DIR)/test_*.awk)

# test runner (see its docstring); extra options can be passed with RUNNER_FLAGS
RUNNER := python3 $(TEST_DIR)/run.py
RUNNER_FLAGS :=
# $(call run-suite,SUITE[,OPTIONS])
run-suite = $(RUNNER) $(1) \
	--awk $(AWK_BIN)/$(AWK) \
	--script $(MAKEFILE_DOC) \
	--awk-flags='$(AWK_FLAGS)' \
	$(2) \
	$(RUNNER_FLAGS)

## Supported awk variants:
AWK := awk
AWK_FLAGS :=
AWK_BIN := $(TEST_DIR)/bin
SUPPORTED_AWK_VARIANTS := awk gawk mawk nawk bawk wak goawk

# one target per awk variant: test@awk, test@mawk, ...
TEST_ALL := $(addprefix test@,$(SUPPORTED_AWK_VARIANTS))
UTEST_ALL := $(addprefix utest@,$(SUPPORTED_AWK_VARIANTS))
BUGS_ALL := $(addprefix bugs@,$(SUPPORTED_AWK_VARIANTS))

## {ansi, html}
OUTPUT_FORMAT :=
EXPORT_THEME :=

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
## (e.g., `make test RUNNER_FLAGS='-k sub'`)
.PHONY: test
test: $(AWK_BIN)/$(AWK) $(MAKEFILE_DOC)
	@$(call run-suite,integration,)

## Run unit tests
## (e.g., `make utest RUNNER_FLAGS='-v -k parsing'`)
.PHONY: utest
utest: $(AWK_BIN)/$(AWK) $(MAKEFILE_DOC) $(UNIT_TESTS) $(UNIT_TEST_DIR)/harness.awk
	@$(call run-suite,unit,)

## Run tests of known bugs (recipes with a `#: bug: N` line)
## fails if a bug is fixed (see test/README.md)
.PHONY: bugs
bugs: $(AWK_BIN)/$(AWK) $(MAKEFILE_DOC)
	@$(call run-suite,bugs,)

## Run integration tests with all supported awk variants
## (`test@<variant>` is the same as `make test AWK=<variant>`)
.PHONY: test@all
test@all: $(TEST_ALL)

## Run unit tests with all supported awk variants
## (`utest@<variant>` is the same as `make utest AWK=<variant>`)
.PHONY: utest@all
utest@all: $(UTEST_ALL)

## Run tests of known bugs with all supported awk variants
## (`bugs@<variant>` is the same as `make bugs AWK=<variant>`;
## consider using `make -k` to continue after a failure)
.PHONY: bugs@all
bugs@all: $(BUGS_ALL)

.PHONY: $(TEST_ALL) $(UTEST_ALL) $(BUGS_ALL)
$(TEST_ALL): test@%:
	@$(MAKE) test AWK=$*
$(UTEST_ALL): utest@%:
	@$(MAKE) utest AWK=$*
$(BUGS_ALL): bugs@%:
	@$(MAKE) bugs AWK=$*

##@
##@------ Coverage & lint ------
##@

## Run integration/unit tests with `goawk`
## (generate a coverage report in coverage-reports/all.html)
.PHONY: coverage
coverage: $(COVER_DIR)/all.html

$(COVER_DIR)/all.html: $(COVER_DIR)/integration.html $(COVER_DIR)/unit.html
	@{ cat $(COVER_DIR)/integration.out; tail -n +2 $(COVER_DIR)/unit.out; } > $(COVER_DIR)/all.out
	@go tool cover -html=$(COVER_DIR)/all.out -o $@

# Run the integration tests with goawk and generate a coverage report
$(COVER_DIR)/integration.html: override AWK := goawk
$(COVER_DIR)/integration.html: AWK_FLAGS := -coverprofile $(COVER_DIR)/integration.out -coverappend
$(COVER_DIR)/integration.html: $(MAKEFILE_DOC) $(foreach recipe,$(INTEGRATION_TESTS),$(INTEGRATION_TEST_DIR)/$(recipe)) | $(COVER_DIR)
	@$(MAKE) test AWK=$(AWK) AWK_FLAGS='$(AWK_FLAGS)' RUNNER_FLAGS='--jobs 1'
	@go tool cover -html=$(COVER_DIR)/integration.out -o $@

# Run the unit tests with goawk and generate a coverage report
# (one test file at a time, as all of them append to the same coverage profile)
$(COVER_DIR)/unit.html: override AWK := goawk
$(COVER_DIR)/unit.html: override AWK_FLAGS := -coverprofile $(COVER_DIR)/unit.out -coverappend
$(COVER_DIR)/unit.html: override RUNNER_FLAGS := --jobs 1
$(COVER_DIR)/unit.html: utest | $(COVER_DIR)
	@go tool cover -html=$(COVER_DIR)/unit.out -o $@

$(COVER_DIR):
	@mkdir -p $@

## Lint the code using `gawk`
# Warnings to ignore have been stripped below
.PHONY: lint
lint: UNINIT := (sub_array|COLOR_.*|VARS|OFFSET|PADDING|DEPRECATED|RECIPEPREFIX|STDERR|\
				|TARGETS_REGEX|VARIABLES_REGEX|OUTPUT_FORMAT|EXPORT_THEME|UNIT_TEST)
lint: override AWK := gawk
lint: check-variables
	@$(AWK_BIN)/$(AWK) --lint \
		-v SHOW_HELP=0 \
		-v UNIT_TEST=0 \
		-f $(MAKEFILE_DOC) 2>&1 | \
		grep -vE "reference to uninitialized .* \`$(UNINIT)'" || echo "lint: OK"

## Verify that there are no unintended global variables
.PHONY: check-variables
check-variables: AWK_CODE := '\
	{ v=$$1; if (v !~ /^[A-Z_]+$$/ && v !~ /^g_[a-z_]+$$/) a[k++]=v }\
	END { if (length(a) == 0) print "check-variables: OK"; else \
	{for(k in a) print "["a[k]"] violates naming rules"} }'
check-variables: AWKVARS_FILE := awkvars.out
check-variables: $(AWK_BIN)/gawk
	@$(AWK_BIN)/gawk -v SHOW_HELP=0 -d$(AWKVARS_FILE) -f $(MAKEFILE_DOC) || exit 0
	@cat $(AWKVARS_FILE) | $(AWK) -F: $(AWK_CODE)
	@rm -f $(AWKVARS_FILE)

##@
##@------ Housekeeping ------
##@

.PHONY: clean
clean: ## Remove coverage reports
	@rm -rf $(COVER_DIR)

##! Create github release at latest tag
.PHONY: release
release: RELEASE_NOTES := release_notes.md
release:
	@test -f $(RELEASE_NOTES) || { echo "No file $(RELEASE_NOTES)"; exit 1; }
	@tag=$$(git describe --tags) && \
	gh release create "$$tag" $(MAKEFILE_DOC) \
		--generate-notes \
		--notes-file $(RELEASE_NOTES) -t "$$tag"

##@
##@------ Individual integration tests ------
##@

## Recipes:
## ---------

# One target per recipe, run by the test runner (RUNNER_FLAGS=--update rewrites the
# expected output). The recipe of a known bug (`#: bug: N`) is run as a bug test.
.PHONY: $(INTEGRATION_TESTS)
$(INTEGRATION_TESTS): $(AWK_BIN)/$(AWK)
	@$(call run-suite,integration,--name $@)

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
