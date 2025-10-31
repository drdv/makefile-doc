SHELL := bash
TEST_DIR := test
TEST_RECIPES := $(TEST_DIR)/recipes

TESTS := $(notdir $(wildcard $(TEST_RECIPES)/*))

## awk executable to use:
##  + awk (system's default)
##  + mawk
##  + nawk
##  + bawk (busybox awk)
##  + wak
AWK := awk
AWK_FLAGS :=
AWK_BIN := $(TEST_DIR)/bin

## Debug info is generated if set
DEBUG :=

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
help: VFLAG := -v EXPANDED_TARGETS='$$(TESTS):test-:$(subst test-,,$(TESTS))' \
	-v DEBUG=$(DEBUG)
help: $(AWK_BIN)/$(AWK)
	@$< $(VFLAG) $(AWK_FLAGS) -f ./makefile-doc.awk $(MAKEFILE_LIST)

deploy-local: DEPLOY_DIR := $(HOME)/.local/share/makefile-doc
deploy-local:
	@mkdir -p $(DEPLOY_DIR)
	@cp makefile-doc.awk $(DEPLOY_DIR)

.PHONY: test
## run all tests
test: $(TESTS)

.PHONY: test-all-awk
## run all tests with all awk versions
test-all-awk: ; $(foreach X,awk mawk nawk bawk wak,$(MAKE) test AWK=$(X);)

.PHONY: clean-bin
clean-bin: ##! remove all downloaded awk varsions
	@rm -rf $(AWK_BIN)

.PHONY: release
## create github release at latest tag
release: LATEST_TAG := $(shell git describe --tags)
release: RELEASE_NOTES := release_notes.md
release:
	@test -f $($(RELEASE_NOTES)) && \
	gh release create $(LATEST_TAG) makefile-doc.awk \
		--generate-notes \
		--notes-file $(RELEASE_NOTES) -t '$(LATEST_TAG)' || \
	echo "No file $(RELEASE_NOTES)"

##@
##@ ----- Individual tests -----
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
	@echo "passed $@ ($(notdir $<))"

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

$(AWK_BIN)/%: # a catch-all target for AWK values
	@echo "==================================================="
	@echo "Expected value for AWK: awk, mawk, nawk, bawk, wak."
	@echo "==================================================="
	@exit 1
