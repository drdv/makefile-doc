SHELL := bash
TEST_DIR := test

## names of tests
TESTS := test-deprecated \
	test-default \
	test-padding \
	test-connected \
	test-backticks \
	test-vars \
	test-no-vars \
	test-vars-assignment \
	test-no-anchors

## awk executable to use:
##  + awk (system's default)
##  + mawk
##  + nawk
##  + bawk (busybox awk)
##  + wak
AWK := awk
AWK_FLAGS :=
AWK_BIN := $(TEST_DIR)/bin

URL_MAWK := https://invisible-island.net/datafiles/release/mawk.tar.gz
URL_NAWK := https://github.com/onetrueawk/awk/archive/refs/tags/20240728.tar.gz
URL_BUSYBOX_AWK := https://www.busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox_AWK
URL_WAK := https://github.com/raygard/wak/archive/refs/tags/v24.10.tar.gz

define run-test
# both the command and the expected results are stored in test/expected_output/$1
# the command is assumed to be on the first line
	$(eval CMD := $$(shell head -n 1 $(TEST_DIR)/expected_output/$1))
	diff -u \
		<(tail -n +2 $(TEST_DIR)/expected_output/$1) \
		<($(AWK_BIN)/$(AWK) -f makefile-doc.awk $(CMD:>=)) || \
	(echo "failed $1"; exit 1)
	echo "passed $1 ($(AWK))"
endef

define verify-download
	read -p "Download and build $(AWK) [Y/n]: " ans \
		&& ([ -z $$ans ] || [ $$ans = y ] || [ $$ans = Y ]) \
		&& exit 0 \
		|| echo "Download of $(AWK) cancelled"; exit 1
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
	@$(call run-test,$@)

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

$(AWK_BIN)/mawk:
	@$(call verify-download)
	@wget -P $(AWK_BIN) $(URL_MAWK)
	@mkdir -p $@-src
	@tar xvf $(AWK_BIN)/mawk.tar.gz -C $@-src --strip-components=1
	@cd $@-src && ./configure && make
	@cp $@-src/mawk $@

$(AWK_BIN)/nawk:
	@$(call verify-download)
	@wget -P $(AWK_BIN) $(URL_NAWK)
	@mkdir -p $@-src
	@tar xvf $(AWK_BIN)/20240728.tar.gz -C $@-src --strip-components=1
	@cd $@-src && make
	@cp $@-src/a.out $@

$(AWK_BIN)/bawk:
ifeq ($(shell uname),Darwin)
	@echo "No official version of Busybox awk for macos"
	@exit 1
else
	@$(call verify-download)
	@wget -P $(AWK_BIN) $(URL_BUSYBOX_AWK)
	@mv $(AWK_BIN)/busybox_AWK $@ && chmod +x $@
endif

$(AWK_BIN)/wak:
	@$(call verify-download)
	@wget -P $(AWK_BIN) $(URL_WAK)
	@mkdir -p $@-src
	@tar xvf $(AWK_BIN)/v24.10.tar.gz -C $@-src --strip-components=1
	@cd $@-src && make
	@cp $@-src/wak $@

$(AWK_BIN)/%: # a catch-all target for AWK values
	@echo "==================================================="
	@echo "Expected value for AWK: awk, mawk, nawk, bawk, wak."
	@echo "==================================================="
	@exit 1
