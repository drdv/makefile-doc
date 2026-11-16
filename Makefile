SHELL := bash
MAKEFLAGS := --no-print-directory --warn-undefined-variables

TEST_DIR := test
MAKEFILE_DOC := makefile-doc.awk
COVER_DIR := coverage-reports

UV_RUN := uv run
PYTEST := $(UV_RUN) pytest
RUFF := $(UV_RUN) ruff

RELEASE_CMD := $(UV_RUN) python $(TEST_DIR)/tools/release.py

## The new version for `bump`, e.g., `v1.10`
V :=

## Platform(s) of test/containers.toml whose awk to test:
## a name or a pattern (e.g., `host-*`; see `make platforms`)
PLATFORM := host-awk

## Container engine of the container platforms (e.g., podman)
ENGINE := podman

## Flags for pytest in `test` and `lint`, e.g.:
##   `--update` (rewrite the expected output of integration tests)
##   `-x` (stop at the first failure)
##   ... as well as all standard pytest flags
PYTEST_FLAGS :=

# The awk that runs `help`
AWK := awk

## {ansi, html, latex}
OUTPUT_FORMAT :=
EXPORT_THEME :=

.PHONY: help
## Show this help
help: VFLAGS := \
	-v EXPORT_THEME=$(EXPORT_THEME) \
	-v COLOR_BACKTICKS=33 \
	-v OUTPUT_FORMAT=$(OUTPUT_FORMAT)
help:
	@$(AWK) $(VFLAGS) -f $(MAKEFILE_DOC) $(MAKEFILE_LIST)

##@
##@------ Tests ------
##@

## Run the integration and unit tests for a given `PLATFORM`
## (e.g., `make test PLATFORM='host-*' PYTEST_FLAGS='-k backslash-anchor'`)
.PHONY: test
test:
	@$(PYTEST) $(TEST_DIR)/test_integration.py $(TEST_DIR)/test_unit.py \
		--platform '$(PLATFORM)' --engine $(ENGINE) $(PYTEST_FLAGS)

## Lint the awk code with `gawk --lint`
.PHONY: lint
lint:
	@$(PYTEST) $(TEST_DIR)/test_lint.py $(PYTEST_FLAGS)
	@$(RUFF) check $(TEST_DIR)
	@$(RUFF) format --check $(TEST_DIR)

## Run `lint` and `test`
.PHONY: check
check: lint test

## List the platforms in test/containers.toml
.PHONY: platforms
platforms:
	@$(UV_RUN) python $(TEST_DIR)/platforms.py list

##@
##@------ Development ------
##@

## Generate a coverage report (coverage-reports/all.html)
.PHONY: coverage
coverage: | $(COVER_DIR)
	@rm -f $(COVER_DIR)/all.out
	@$(MAKE) test PLATFORM=coverage
	@go tool cover -html=$(COVER_DIR)/all.out -o $(COVER_DIR)/all.html

$(COVER_DIR):
	@mkdir -p $@

## Create a draft of release-message.md (with commits since the last tag)
.PHONY: release-notes
release-notes:
	@$(RELEASE_CMD) notes

## Update the version in `makefile-doc.awk` and the `README.md`;
## also commits and tags (with message from release-message.md)
.PHONY: bump
bump:
	@$(RELEASE_CMD) bump "$(V)"

##@
##@------ Clean ------
##@

## Remove the coverage reports
.PHONY: clean-coverage
clean-coverage:
	@rm -rf $(COVER_DIR)

## Remove the binaries of the host platforms (built again when needed)
.PHONY: clean-bin
clean-bin:
	@rm -rf $(TEST_DIR)/bin

# --------------------------------------------------------------------------
# Internal stuff
# --------------------------------------------------------------------------
DEMO := misc/Makefile.demo
DEMO_FLAGS := -v EXPORT_THEME=BG:000000,FG:F7F7F7 -v COLOR_BACKTICKS=33

demo.html: $(DEMO) $(MAKEFILE_DOC)
	@$(AWK) $(DEMO_FLAGS) -v OUTPUT_FORMAT=html -f $(MAKEFILE_DOC) $(DEMO) > $@

demo.pdf: %.pdf : $(DEMO) $(MAKEFILE_DOC)
	@$(AWK) $(DEMO_FLAGS) -v OUTPUT_FORMAT=latex -f $(MAKEFILE_DOC) $(DEMO) > $*.tex
	@tectonic $*.tex
	@rm -f $*.tex

demo.svg: %.svg : %.pdf
	@pdftocairo -svg $< $@
	@rm -f $<

demo.png: DPI := 300
demo.png: %.png : %.pdf
	@magick -density $(DPI) $< -quality 90 $@
	@rm -f $<
