SHELL := bash
TEST_DIR := test
TEST_RECIPES := $(TEST_DIR)/recipes

TESTS := $(notdir $(wildcard $(TEST_RECIPES)/*))

## Debug info is generated if set
DEBUG :=

## Supported AWK variants:
AWK := awk
AWK_FLAGS :=
AWK_BIN := $(TEST_DIR)/bin
SUPPORTED_AWK_VARIANTS := awk mawk nawk bawk wak goawk

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
help: VFLAGS := -v SUB='$$(TESTS):test-:$(subst test-,,$(TESTS));AWK:$(SUPPORTED_AWK_VARIANTS)' \
	-v DEBUG=$(DEBUG) \
	-v COLOR_ENCODING=$(COLOR_ENCODING)
help: $(AWK_BIN)/$(AWK)
	@$< $(VFLAGS) $(AWK_FLAGS) -f ./makefile-doc.awk $(MAKEFILE_LIST)

deploy-local: DEPLOY_DIR := $(HOME)/.local/share/makefile-doc
deploy-local:
	@mkdir -p $(DEPLOY_DIR)
	@cp makefile-doc.awk $(DEPLOY_DIR)

.PHONY: test
## run all tests
test: $(TESTS)

.PHONY: test-all-awk
## run all tests with all supported awk variants
test-all-awk:
	@$(foreach X,$(SUPPORTED_AWK_VARIANTS),$(MAKE) --no-print-directory test AWK=$(X);)

# FIXME:
#  1. array_next_index -- no idea what is the problem
#  2. number_of_files_processed -- it is actually initialized (maybe false-positive)
# Warnings to ignore have been stripped below
lint: UNINIT := (DEBUG|DEBUG_FILE|SUB|HEADER_TARGETS|HEADER_VARIABLES|DEBUG_INDENT_STACK|\
	|COLOR_.*|VARIABLES_REGEX|TARGETS_REGEX|VARS|PADDING|DEPRECATED|OFFSET|CONNECTED)
lint: SHADOW := (description|section|target|target_name|variable_name)
lint: ## lint the code using GNU awk
	@awk --lint -v SHOW_HELP=0 -f ./makefile-doc.awk 2>&1 | \
		grep -vE "parameter \`$(SHADOW)' shadows global variable" | \
		grep -vE "reference to uninitialized variable \`$(UNINIT)'"

.PHONY: clean-bin
clean-bin: ##! remove all downloaded awk variants
	@rm -rf $(AWK_BIN)

.PHONY: release
##! create github release at latest tag
release: LATEST_TAG := $(shell git describe --tags)
release: RELEASE_NOTES := release_notes.md
release:
	@test -f $($(RELEASE_NOTES)) && \
	gh release create $(LATEST_TAG) makefile-doc.awk \
		--generate-notes \
		--notes-file $(RELEASE_NOTES) -t '$(LATEST_TAG)' || \
	echo "No file $(RELEASE_NOTES)"

##@
##@------ Individual tests ------
##@

.PHONY: test-default test-deprecated test-padding test-connected test-backticks \
	test-vars test-no-vars test-vars-assignment test-no-anchors

##
# --ignore-space-at-eol is needed as empty descriptions still add OFFSET
$(TESTS): CMD_LINE = $(shell head -n 1 $(TEST_RECIPES)/$@)
$(TESTS): $(AWK_BIN)/$(AWK)
	@git diff --ignore-space-at-eol \
		<(tail -n +2 $(TEST_RECIPES)/$@) \
		<($< -f makefile-doc.awk $(CMD_LINE:>=)) || \
	(echo "failed $@"; exit 1)
	@echo "[$(notdir $<)] passed $@"

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

$(AWK_BIN)/nawk: URL := github.com/onetrueawk/awk/archive/refs/tags/20240728.tar.gz
$(AWK_BIN)/nawk:
	@$(call verify-download,nawk)
	@wget -P $(AWK_BIN) $(URL)
	@mkdir -p $@-src
	@tar xvf $(AWK_BIN)/20240728.tar.gz -C $@-src --strip-components=1
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

$(AWK_BIN)/wak: URL := github.com/raygard/wak/archive/refs/tags/v24.10.tar.gz
$(AWK_BIN)/wak:
	@$(call verify-download,wak)
	@wget -P $(AWK_BIN) $(URL)
	@mkdir -p $@-src
	@tar xvf $(AWK_BIN)/v24.10.tar.gz -C $@-src --strip-components=1
	@cd $@-src && make
	@cp $@-src/wak $@

# requires: sudo dnf install golang
$(AWK_BIN)/goawk: URL := github.com/benhoyt/goawk/archive/refs/tags/v1.29.1.tar.gz
$(AWK_BIN)/goawk:
	@$(call verify-download,goawk)
	@wget -P $(AWK_BIN) $(URL)
	@mkdir -p $@-src
	@tar xvf $(AWK_BIN)/v1.29.1.tar.gz -C $@-src --strip-components=1
	@cd $@-src && go build -o goawk goawk.go
	@cp $@-src/goawk $@

$(AWK_BIN)/%: # a catch-all target for AWK values
	@echo "==================================================="
	@echo "Supported AWK variants: $(SUPPORTED_AWK_VARIANTS)"
	@echo "==================================================="
	@exit 1
