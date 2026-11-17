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

# Python and its tools (pytest, ruff) are run by uv, in the environment of pyproject.toml
# and uv.lock (https://docs.astral.sh/uv)
UV_RUN := uv run

# downloads what the tests need (see test/tools/deps.toml)
DEPS := $(UV_RUN) python $(TOOLS_DIR)/deps.py
RELEASE := $(UV_RUN) python $(TOOLS_DIR)/release.py

# the tests of makefile-doc.awk, run by pytest (test/test_*.py; see test/README.md)
PYTEST := $(UV_RUN) pytest
# $(call run-tests,FILE): run the tests of FILE with the awk variant AWK and AWK_FLAGS
run-tests = $(PYTEST) $(TEST_DIR)/$(1) --awk '$(strip $(AWK_BIN)/$(AWK) $(AWK_FLAGS))' $(PYTEST_FLAGS)

## Supported awk variants:
AWK := awk

## Flags for awk in `test@<variant>` and `utest@<variant>`:
##   `--posix` (gawk)
##   `-W posix` (mawk)
AWK_FLAGS :=

## Flags for pytest in `test@<variant>`, `utest@<variant>`, `ctest@<platform>` and `lint-tests`:
##   `-k NAME` (run only the tests with NAME in their name, e.g., `-k options-`)
##   `--update` (rewrite the expected output of integration tests)
##   `-x` (stop at the first failure)
##   `-vv` (show full diffs)
PYTEST_FLAGS :=

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
	$$(DEPS_ALL):deps@<variant>:;$$(CLEAN_ALL):clean@<variant>:;$$(BENCH_ALL):bench@<variant>:;\
	$$(CTEST_ALL):ctest@<platform>:
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
## (e.g., `make test@mawk AWK_FLAGS='-W posix' PYTEST_FLAGS='-k options-'`)
$(TEST_ALL): test@%: $(AWK_BIN)/%
	@$(MAKE) test AWK=$*

## Run unit tests with an awk variant (or `utest@all`)
$(UTEST_ALL): utest@%: $(AWK_BIN)/%
	@$(MAKE) utest AWK=$*

.PHONY: test@all utest@all $(TEST_ALL) $(UTEST_ALL)
test@all: $(TEST_ALL)
utest@all: $(UTEST_ALL)

# ----------------------------------------------------------------------------------------
# The awk of other platforms, in containers: one platform per table of test/containers.toml
# ----------------------------------------------------------------------------------------

## The container engine of `ctest@<platform>`
CONTAINER := podman

PLATFORMS := $(shell $(UV_RUN) python $(TEST_DIR)/platforms.py list)
CTEST_ALL := $(addprefix ctest@,$(PLATFORMS))

.PHONY: ctest@all $(CTEST_ALL)
ctest@all: $(CTEST_ALL)

## Run the integration and unit tests with the awk of a platform, in a container (or
## `ctest@all`; see test/containers.toml)
$(CTEST_ALL): ctest@%:
	@$(PYTEST) $(TEST_DIR)/test_integration.py $(TEST_DIR)/test_unit.py \
		--platform $* --engine $(CONTAINER) $(PYTEST_FLAGS)

# A known bug of busybox awk: a -v value of 0 returned by a function is true (see the file).
# This fails once the bug is fixed in the pinned busybox: then remove the workaround, the
# int() in validate_ansi_param(). It is part of `test@bawk`.
.PHONY: check-busybox-bug
check-busybox-bug: $(AWK_BIN)/bawk
	@out=$$($< -v a=0 -f misc/busybox_awk_bug_20251107.awk); \
	test "$$out" = "b: 0" || \
		{ echo "[bawk] FIXED: the busybox awk bug of validate_ansi_param()"; exit 1; }; \
	echo "[bawk] known bug of busybox awk: still there"

test@bawk: check-busybox-bug

# The awk of a variant is a prerequisite of its targets above: it is then built once, by
# this make, before the sub-makes of test@X and utest@X run (also with -j).

## Run `lint`, `test`, `utest` (the tests with the variant `AWK`) and `test-tools`
.PHONY: check
check: lint test utest test-tools

# the tests with AWK and AWK_FLAGS (the targets above set AWK); the cases of known bugs
# (`#: bug: N`, `check_bug`) are part of them: they are expected to fail
.PHONY: test utest
test: $(AWK_BIN)/$(AWK) $(MAKEFILE_DOC)
	@$(call run-tests,test_integration.py)

utest: $(AWK_BIN)/$(AWK) $(MAKEFILE_DOC) $(UNIT_TESTS) $(UNIT_TEST_DIR)/harness.awk
	@$(call run-tests,test_unit.py)

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
# appends to it (pytest runs them one at a time).
define coverage-run
	@rm -f $(2)
	@$(MAKE) $(1) AWK=goawk AWK_FLAGS='-coverprofile $(2) -coverappend'
	@go tool cover -html=$(2) -o $@
endef

# Run the integration tests with goawk and generate a coverage report
$(COVER_DIR)/integration.html: $(MAKEFILE_DOC) $(wildcard $(TEST_DIR)/*.py) \
		$(addprefix $(INTEGRATION_TEST_DIR)/,$(INTEGRATION_TESTS)) | $(COVER_DIR)
	$(call coverage-run,test,$(COVER_DIR)/integration.out)

# Run the unit tests with goawk and generate a coverage report
$(COVER_DIR)/unit.html: $(MAKEFILE_DOC) $(wildcard $(TEST_DIR)/*.py) \
		$(UNIT_TESTS) $(UNIT_TEST_DIR)/harness.awk | $(COVER_DIR)
	$(call coverage-run,utest,$(COVER_DIR)/unit.out)

$(COVER_DIR):
	@mkdir -p $@

BENCH := $(UV_RUN) python $(TOOLS_DIR)/bench.py --script $(MAKEFILE_DOC) $(BENCH_FLAGS)

## Time the script with an awk variant (or `bench@all`; see test/README.md)
$(BENCH_ALL): bench@%:
	@$(BENCH) --awk $*

.PHONY: bench@all $(BENCH_ALL)
bench@all:
	@$(BENCH)

## Lint the awk code and check its global variables (`lint-tests`) and lint the Python test
## tools (`lint-py`)
.PHONY: lint
lint: lint-tests lint-py

# Lint makefile-doc.awk with `gawk --lint` while running the integration cases and the unit
# tests, and check the global variables (the expected warnings are in pyproject.toml; see
# test/README.md). It uses the gawk in PATH.
.PHONY: lint-tests
lint-tests: $(MAKEFILE_DOC)
	@$(PYTEST) $(TEST_DIR)/test_lint.py $(PYTEST_FLAGS)

## Write a draft of the release notes (the commits since the last tag) to release-message.md
.PHONY: release-notes
release-notes:
	@$(RELEASE) notes

## The new version for `bump`, e.g., `v1.10`
V :=

## Set the version `V` in the script and the README; with release-message.md, also commit
## them and create an annotated tag with its message (then push the commit and the tag: CI
## tests and creates a draft release)
.PHONY: bump
bump:
	@$(RELEASE) bump "$(V)"

# the version of ruff is pinned in uv.lock
RUFF := $(UV_RUN) ruff

# Lint and check the formatting of the Python code (settings in pyproject.toml)
.PHONY: lint-py
lint-py:
	@$(RUFF) check $(TEST_DIR)
	@$(RUFF) format --check $(TEST_DIR)

## Test the Python test tools (test/tools/test_*.py and test/test_platforms.py)
.PHONY: test-tools
test-tools:
	@$(PYTEST) --no-header $(TOOLS_DIR) $(TEST_DIR)/test_platforms.py

##@
##@------ Install and clean ------
##@

## Show the versions of the installed awk variants (and those that differ from deps.toml)
.PHONY: versions
versions:
	@$(DEPS) versions

## Download and build an awk variant (or `deps@all`; see test/tools/deps.toml)
$(DEPS_ALL): deps@%: $(AWK_BIN)/%

## Remove an awk variant with its downloads (or `clean@all`)
$(CLEAN_ALL): clean@%:
	@rm -rf $(AWK_BIN)/$* $(AWK_BIN)/$*-*

## Remove coverage reports
clean:
	@rm -rf $(COVER_DIR)

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
