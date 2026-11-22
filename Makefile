SHELL := bash
MAKEFLAGS := --no-print-directory --warn-undefined-variables

TEST_DIR := test
MAKEFILE_DOC := makefile-doc.awk
COVER_DIR := coverage-reports

UV_RUN := uv run
PYTEST := $(UV_RUN) pytest
RUFF := $(UV_RUN) ruff

RELEASE_CMD := $(UV_RUN) python tools/release.py

## The new version for `bump`, e.g., `v1.10`
V :=

## Platform(s) of test/containers.toml whose awk to test:
## a name or a pattern (e.g., `host-*`; see `make platforms`)
PLATFORM := host-awk

## Container engine of the container platforms (default: podman)
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

## Lint the awk code (`gawk --lint`) and the Python code (ruff, mypy)
.PHONY: lint
lint:
	@$(PYTEST) $(TEST_DIR)/test_lint.py $(PYTEST_FLAGS)
	@$(RUFF) check $(TEST_DIR) tools
	@$(RUFF) format --check $(TEST_DIR) tools
	@$(UV_RUN) mypy $(TEST_DIR) tools

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
	@$(MAKE) test PLATFORM=host-coverage
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

## Remove caches, coverage reports and the demo files
.PHONY: clean
clean:
	@rm -rf $(COVER_DIR) $(OUT_DIR)/demo .ruff_cache .mypy_cache .pytest_cache
	@find $(TEST_DIR) -type d -name __pycache__ -prune -exec rm -rf {} +

## Remove the binaries of the host platforms (built again when needed)
.PHONY: clean-bin
clean-bin:
	@rm -rf $(TEST_DIR)/bin

# --------------------------------------------------------------------------
# Internal stuff (demo)
# --------------------------------------------------------------------------
OUT_DIR := out
DEMO := misc/Makefile.demo
DEMO_FLAGS := -v EXPORT_THEME=BG:000000,FG:F7F7F7
DEMO_DIR := $(OUT_DIR)/demo
DEMO_DPI := 300

# out/demo/demo.{html,tex}, and out/demo/ENGINE/demo.{pdf,svg,png} for each LaTeX engine
DEMO_PDFS := $(DEMO_DIR)/tectonic/demo.pdf $(DEMO_DIR)/pdflatex/demo.pdf
DEMO_SVGS := $(DEMO_PDFS:.pdf=.svg)
DEMO_PNGS := $(DEMO_PDFS:.pdf=.png)

.PHONY: demo-interface-variables
demo-interface-variables:
	@$(AWK) -f tools/dump-interface.awk -f $(MAKEFILE_DOC) $(DEMO)

.PHONY: demo-all
demo-all: $(DEMO_DIR)/demo.html $(DEMO_SVGS) $(DEMO_PNGS)

$(DEMO_DIR)/demo.html: FORMAT := html
$(DEMO_DIR)/demo.tex: FORMAT := latex
$(DEMO_DIR)/demo.html $(DEMO_DIR)/demo.tex: $(DEMO) $(MAKEFILE_DOC)
	@mkdir -p $(@D)
	@$(AWK) $(DEMO_FLAGS) -v OUTPUT_FORMAT=$(FORMAT) -f $(MAKEFILE_DOC) $(DEMO) > $@

$(DEMO_DIR)/tectonic/demo.pdf: $(DEMO_DIR)/demo.tex
	@mkdir -p $(@D)
	@tectonic --outdir $(@D) $<

$(DEMO_DIR)/pdflatex/demo.pdf: $(DEMO_DIR)/demo.tex
	@mkdir -p $(@D)
	@pdflatex -interaction=nonstopmode -halt-on-error -output-directory=$(@D) $< > /dev/null

$(DEMO_SVGS): %.svg: %.pdf
	@pdftocairo -svg $< $@

$(DEMO_PNGS): %.png: %.pdf
	@magick -density $(DEMO_DPI) $< -quality 90 $@
