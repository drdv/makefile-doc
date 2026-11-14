# --output-sync needs GNU make >= 4.0
ifeq ($(filter output-sync,$(.FEATURES)),)
$(error GNU Make 4.0 or later is needed, this is version $(MAKE_VERSION))
endif

SHELL := bash
MAKEFLAGS := --no-print-directory --warn-undefined-variables --output-sync=target
TEST_DIR := test

INTEGRATION_TEST_DIR := $(TEST_DIR)/integration
INTEGRATION_TESTS := $(notdir $(wildcard $(INTEGRATION_TEST_DIR)/*))

UNIT_TEST_DIR := $(TEST_DIR)/unit
UNIT_TESTS := $(wildcard $(UNIT_TEST_DIR)/test_*.awk)

# the test tools (see test/README.md)
TOOLS_DIR := $(TEST_DIR)/tools

# downloads what the tests need (see test/tools/deps.toml)
DEPS := python3 $(TOOLS_DIR)/deps.py

# test runner (see its docstring); extra options can be passed with RUNNER_FLAGS
RUNNER := python3 $(TOOLS_DIR)/run.py
# $(call run-suite,SUITE[,OPTIONS])
run-suite = $(RUNNER) $(1) \
	--awk $(AWK_BIN)/$(AWK) \
	--script $(MAKEFILE_DOC) \
	--awk-flags='$(AWK_FLAGS)' \
	$(2) \
	$(RUNNER_FLAGS)

## Supported awk variants:
AWK := awk

## Flags for awk in `test@<variant>`, `utest@<variant>` and `bugs@<variant>`:
##   `--posix` (gawk)
##   `-W posix` (mawk)
AWK_FLAGS :=

## Flags for `test@<variant>`, `utest@<variant>`, `bugs@<variant>` and `lint-tests`:
##   `-v` (show the output of passing tests)
##   `NAME ...` (run only these tests: exact names or patterns, e.g., `misc 'options-*'`)
##   `--update` (rewrite the expected output of integration tests)
##   `--timeout SECONDS` (default: 30)
##   `--jobs N` (number of tests run in parallel)
RUNNER_FLAGS :=

## Flags for `bench@<variant>`:
##   `--rev REV` (also show the change from this git revision)
##   `-n N` (runs per measurement, default: 5)
##   `--keep` (save the annotated Makefiles in test/bin/)
BENCH_FLAGS :=

AWK_BIN := $(TEST_DIR)/bin
SUPPORTED_AWK_VARIANTS := $(shell $(DEPS) list)
ifeq ($(SUPPORTED_AWK_VARIANTS),)
$(error cannot list the awk variants, `$(DEPS) list` failed)
endif

# one target per awk variant: test@awk, test@mawk, ...
TEST_ALL := $(addprefix test@,$(SUPPORTED_AWK_VARIANTS))
UTEST_ALL := $(addprefix utest@,$(SUPPORTED_AWK_VARIANTS))
BUGS_ALL := $(addprefix bugs@,$(SUPPORTED_AWK_VARIANTS))
DEPS_ALL := $(addprefix deps@,$(SUPPORTED_AWK_VARIANTS))
CLEAN_ALL := $(addprefix clean@,$(SUPPORTED_AWK_VARIANTS))
BENCH_ALL := $(addprefix bench@,$(SUPPORTED_AWK_VARIANTS))

## {ansi, html, latex}
OUTPUT_FORMAT :=
EXPORT_THEME :=

MAKEFILE_DOC := makefile-doc.awk
COVER_DIR := coverage-reports

.PHONY: help
## Show this help
help: AWK_SUB := <L:0,M:0,I:{,T:},S:\\,>AWK:$(foreach x,$(SUPPORTED_AWK_VARIANTS),`$(x)`)
# the targets per awk variant are shown as, e.g., test@<variant>
help: VARIANT_SUB := $$(TEST_ALL):test@<variant>:;$$(UTEST_ALL):utest@<variant>:;\
	$$(BUGS_ALL):bugs@<variant>:;$$(DEPS_ALL):deps@<variant>:;$$(CLEAN_ALL):clean@<variant>:;\
	$$(BENCH_ALL):bench@<variant>:
help: VFLAGS := \
	-v SUB='$(VARIANT_SUB);$(AWK_SUB)' \
	-v EXPORT_THEME=$(EXPORT_THEME) \
	-v COLOR_BACKTICKS=33 \
	-v OUTPUT_FORMAT=$(OUTPUT_FORMAT)
help: $(AWK_BIN)/$(AWK)
	@$< $(VFLAGS) $(AWK_FLAGS) -f $(MAKEFILE_DOC) $(MAKEFILE_LIST)

##@
##@------ Tests ------
##@

## Run integration tests with an awk variant (or `test@all`)
## (e.g., `make test@mawk AWK_FLAGS='-W posix' RUNNER_FLAGS='-v'`)
$(TEST_ALL): test@%: $(AWK_BIN)/%
	@$(MAKE) test AWK=$*

## Run unit tests with an awk variant (or `utest@all`)
$(UTEST_ALL): utest@%: $(AWK_BIN)/%
	@$(MAKE) utest AWK=$*

## Run tests of known bugs with an awk variant (or `bugs@all`)
$(BUGS_ALL): bugs@%: $(AWK_BIN)/%
	@$(MAKE) bugs AWK=$*

.PHONY: test@all utest@all bugs@all $(TEST_ALL) $(UTEST_ALL) $(BUGS_ALL)
test@all: $(TEST_ALL)
utest@all: $(UTEST_ALL)
bugs@all: $(BUGS_ALL)

# A known bug of busybox awk: a -v value of 0 returned by a function is true (see the file).
# This fails once the bug is fixed in the pinned busybox: then remove the workaround, the
# int() in validate_ansi_param(). It is part of `bugs@bawk`.
.PHONY: check-busybox-bug
check-busybox-bug: $(AWK_BIN)/bawk
	@out=$$($< -v a=0 -f misc/busybox_awk_bug_20251107.awk); \
	test "$$out" = "b: 0" || \
		{ echo "[bawk] FIXED: the busybox awk bug of validate_ansi_param()"; exit 1; }; \
	echo "[bawk] known bug of busybox awk: still there"

bugs@bawk: check-busybox-bug

# The awk of a variant is a prerequisite of its targets above: it is then built once, by
# this make, before the sub-makes of test@X, utest@X and bugs@X run (also with -j).

## Run `lint`, `test`, `utest` and `bugs` (the tests with the variant `AWK`)
.PHONY: check
check: lint test utest bugs

# the tests with AWK and AWK_FLAGS (the targets above set AWK)
.PHONY: test utest bugs
test: $(AWK_BIN)/$(AWK) $(MAKEFILE_DOC)
	@$(call run-suite,integration,)

utest: $(AWK_BIN)/$(AWK) $(MAKEFILE_DOC) $(UNIT_TESTS) $(UNIT_TEST_DIR)/harness.awk
	@$(call run-suite,unit,)

bugs: $(AWK_BIN)/$(AWK) $(MAKEFILE_DOC)
	@$(call run-suite,bugs,)

##@
##@------ Development ------
##@

## Run the tests with `goawk` (see coverage-reports/all.html)
.PHONY: coverage
coverage: $(COVER_DIR)/all.html

$(COVER_DIR)/all.html: $(COVER_DIR)/integration.html $(COVER_DIR)/unit.html
	@{ cat $(COVER_DIR)/integration.out; tail -n +2 $(COVER_DIR)/unit.out; } > $(COVER_DIR)/all.out
	@go tool cover -html=$(COVER_DIR)/all.out -o $@

# $(call coverage-run,MAKE_TARGET,PROFILE): run the tests of MAKE_TARGET with goawk and
# write their coverage to PROFILE. The profile is removed first, as each test process
# appends to it (one at a time: --jobs 1).
define coverage-run
	@rm -f $(2)
	@$(MAKE) $(1) AWK=goawk AWK_FLAGS='-coverprofile $(2) -coverappend' RUNNER_FLAGS='--jobs 1'
	@go tool cover -html=$(2) -o $@
endef

# Run the integration tests with goawk and generate a coverage report
$(COVER_DIR)/integration.html: $(MAKEFILE_DOC) $(TOOLS_DIR)/run.py \
		$(addprefix $(INTEGRATION_TEST_DIR)/,$(INTEGRATION_TESTS)) | $(COVER_DIR)
	$(call coverage-run,test,$(COVER_DIR)/integration.out)

# Run the unit tests with goawk and generate a coverage report
$(COVER_DIR)/unit.html: $(MAKEFILE_DOC) $(TOOLS_DIR)/run.py \
		$(UNIT_TESTS) $(UNIT_TEST_DIR)/harness.awk | $(COVER_DIR)
	$(call coverage-run,utest,$(COVER_DIR)/unit.out)

$(COVER_DIR):
	@mkdir -p $@

BENCH := python3 $(TOOLS_DIR)/bench.py --script $(MAKEFILE_DOC) $(BENCH_FLAGS)

## Time the script with an awk variant (or `bench@all`; see test/README.md)
$(BENCH_ALL): bench@%:
	@$(BENCH) --awk $*

.PHONY: bench@all $(BENCH_ALL)
bench@all:
	@$(BENCH)

## Lint the awk code and check its global variables (`lint-tests`), lint the Python test
## tools (`lint-py`) and check the version in the README (`check-version`)
.PHONY: lint
lint: lint-tests lint-py check-version

# Lint makefile-doc.awk with `gawk --lint` while running the integration cases and the unit
# tests, and check the global variables (the expected warnings are in test/tools/lint.toml;
# see test/README.md)
.PHONY: lint-tests
lint-tests: override AWK := gawk
lint-tests: $(AWK_BIN)/gawk $(MAKEFILE_DOC)
	@$(call run-suite,lint,)

# prints the version of the script (the VERSION variable set in init_globals)
SCRIPT_VERSION := sed -n 's/^ *VERSION = "\([^"]*\)".*/\1/p' $(MAKEFILE_DOC)

# Verify that the README installs the version of the script (the `help: VER := ...` line)
.PHONY: check-version
check-version:
	@version=$$($(SCRIPT_VERSION)); \
	readme=$$(sed -n 's/^help: VER := //p' README.md); \
	test -n "$$version" && test "$$readme" = "$$version" || \
		{ echo "README.md installs '$$readme', $(MAKEFILE_DOC) is '$$version'"; exit 1; }; \
	echo "check-version: OK"

# the version is pinned; without uv, use an installed ruff: `make lint-py RUFF=ruff`
RUFF := uvx ruff@0.16.9

# Lint and check the formatting of the Python test tools (settings in ruff.toml)
.PHONY: lint-py
lint-py:
	@$(RUFF) check $(TEST_DIR)
	@$(RUFF) format --check $(TEST_DIR)

$(MAKEFILE_DOC).sha256: $(MAKEFILE_DOC)
	@sha256sum $< > $@

##! Create a draft github release at the tag of HEAD
.PHONY: draft-release
draft-release: check-version $(MAKEFILE_DOC).sha256
	@tag=$$(git describe --tags --exact-match 2>/dev/null) || { echo "HEAD has no tag"; exit 1; }; \
	version=$$($(SCRIPT_VERSION)); \
	test "$$version" = "$$tag" || \
		{ echo "Version $$version in $(MAKEFILE_DOC) differs from tag $$tag"; exit 1; }; \
	gh release create "$$tag" $(MAKEFILE_DOC) $(MAKEFILE_DOC).sha256 \
		--draft --generate-notes -t "$$tag"

##@
##@------ Install and clean ------
##@

## Download and build an awk variant (or `deps@all`; see test/tools/deps.toml)
$(DEPS_ALL): deps@%: $(AWK_BIN)/%

## Remove an awk variant with its downloads (or `clean@all`)
$(CLEAN_ALL): clean@%:
	@rm -rf $(AWK_BIN)/$* $(AWK_BIN)/$*-*

## Remove coverage reports
clean:
	@rm -rf $(COVER_DIR)
	@rm -f $(MAKEFILE_DOC).sha256

.PHONY: deps@all clean@all clean $(DEPS_ALL) $(CLEAN_ALL)
deps@all: $(DEPS_ALL)
clean@all:
	@rm -rf $(AWK_BIN)

# (only for the supported variants)
$(addprefix $(AWK_BIN)/,$(SUPPORTED_AWK_VARIANTS)): $(AWK_BIN)/%:
	@$(DEPS) install $*

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
