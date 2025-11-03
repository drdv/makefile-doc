SHELL := bash
TEST_DIR := test
TEST_RECIPES := $(TEST_DIR)/recipes

TESTS := $(notdir $(wildcard $(TEST_RECIPES)/*))

## if set, debug info is generated in an org file
DEBUG :=

##
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
help: AWK_SUB := <L:0,M:0,I:{,T:},S:\\,>AWK:$(SUPPORTED_AWK_VARIANTS)
help: TESTS_SUB := <L:0,M:1>$$(TESTS):test-:$(wordlist 1,5,$(subst test-,,$(TESTS))) ...
help: VFLAGS := -v SUB='$(TESTS_SUB);$(AWK_SUB)' \
	-v DEBUG=$(DEBUG) \
	-v COLOR_ENCODING=$(COLOR_ENCODING)
help: $(AWK_BIN)/$(AWK)
	@$< $(VFLAGS) $(AWK_FLAGS) -f makefile-doc.awk $(MAKEFILE_LIST)

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

## lint the code using GNU awk
# Warnings to ignore have been stripped below
lint: UNINIT := (DEBUG|DEBUG_FILE|DEBUG_INDENT_STACK|SUB|COLOR_.*|VARS|OFFSET|PADDING|\
		|CONNECTED|DEPRECATED|TARGETS_REGEX|VARIABLES_REGEX)
lint: check-variables
	@awk --lint -v SHOW_HELP=0 -f makefile-doc.awk 2>&1 | \
		grep -vE "reference to uninitialized variable \`$(UNINIT)'" || exit 0

## verify names of variables
check-variables: AWK_CODE := '{if($$1!~/^[A-Z_]+$$/ && $$1!~/^g_[a-z_]+$$/) print $$1 " violates naming rules"}'
check-variables: AWKVARS_FILE := awkvars.out
check-variables:
	@$(AWK) -v SHOW_HELP=0 -d$(AWKVARS_FILE) -f makefile-doc.awk || exit 0
	@cat $(AWKVARS_FILE) | $(AWK) -F: $(AWK_CODE)
	@ rm -f $(AWKVARS_FILE)

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
