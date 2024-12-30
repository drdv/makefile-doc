SHELL := bash
TEST_DIR := test
TEST_RECIPES := $(TEST_DIR)/recipes

## names of tests
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

# using $1 instead of $(AWK) is necessary for a target like
# deps: $(AWK_BIN)/mawk $(AWK_BIN)/nawk $(AWK_BIN)/bawk $(AWK_BIN)/wak
define verify-download
	read -p "Download and build $1 [Y/n]: " ans \
		&& ([ -z $$ans ] || [ $$ans = y ] || [ $$ans = Y ]) \
		&& exit 0 \
		|| echo "Download of $1 cancelled"; exit 1
endef

## show this help
help: $(AWK_BIN)/$(AWK)
	@$< $(AWK_FLAGS) -f ./makefile-doc.awk $(MAKEFILE_LIST)

## run all tests
.PHONY: test
test: $(TESTS)

clean-bin: ##! remove all downloaded awk varsions
	@rm -rf $(AWK_BIN)

##@
##@ ----- Individual tests -----
##@

## multiple individual test targets:
$(TESTS): $(AWK_BIN)/$(AWK)
	@$(eval CMD_LINE := $$(shell head -n 1 $(TEST_RECIPES)/$@))
	@diff -u \
		<(tail -n +2 $(TEST_RECIPES)/$@) \
		<($(AWK_BIN)/$(AWK) -f makefile-doc.awk $(CMD_LINE:>=)) || \
	(echo "failed $@"; exit 1)
	@echo "passed $@ ($(AWK))"

# add docs
test-default:         ##  + test default behavior
test-deprecated:      ##  + test setting `DEPRECATED=0`
test-padding:         ##  + test setting `PADDING=.`
test-connected:       ##  + test setting `CONNECTED=0`
test-backticks:       ##  + test setting `COLOR_BACKTICKS=1`
test-vars:            ##  + test with default `VARS=1`
test-no-vars:         ##  + test with `VARS=0`
test-vars-assignment: ##  + test variable assignments
test-no-anchors:      ##  + test no anchors

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
