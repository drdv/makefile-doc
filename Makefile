TEST_DIR := test

## Awk executable to use
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

# diff -u <(...) <(...) doesn't work in the CI
define run-test
	tail -n +4 $(TEST_DIR)/expected_output/$1 > $(TEST_DIR)/result_expected.txt
	cd $(TEST_DIR) && $2 $3 > result_actual.txt
	diff -u $(TEST_DIR)/result_actual.txt $(TEST_DIR)/result_expected.txt || \
	(echo "failed $1"; exit 1)
	echo "passed $1 ($3)"
endef

# for some reason `yes | make test AWK=mawk` results in a broken pipe on dash (ubuntu)
# so I use the SKIP_VERIFY hack
SKIP_VERIFY = 0
define verify-download
	[ $(SKIP_VERIFY) = 1 ] || read -p "Download and build $(AWK) [Y/n]: " ans \
		&& ([ -z $$ans ] || [ $$ans = y ] || [ $$ans = Y ]) \
		&& exit 0 \
		|| echo "Download of $(AWK) cancelled"; exit 1
endef

## show this help
help: $(AWK_BIN)/$(AWK)
	@$< $(AWK_FLAGS) -f ./makefile-doc.awk $(MAKEFILE_LIST)

## run all tests
.PHONY: test
test: test-default \
	test-deprecated \
	test-padding \
	test-connected \
	test-backticks \
	test-vars \
	test-no-vars \
	_clean-results

clean-bin: ##! remove all downloaded awk varsions
	@rm -rf $(AWK_BIN)

_clean-results:
	@rm -rf $(TEST_DIR)/result*

##@
##@ ----- Individual tests -----
##@

## test default behavior
test-default: $(AWK_BIN)/$(AWK)
	@$(call run-test,$@,make -s,AWK=$(AWK))

## test setting DEPRECATED=0
test-deprecated: $(AWK_BIN)/$(AWK)
	@$(call run-test,$@,make -s -f Makefile.inc DEPRECATED=0,AWK=$(AWK))

## test setting PADDING="."
test-padding: $(AWK_BIN)/$(AWK)
	@$(call run-test,$@,make -s -f Makefile.inc PADDING=".",AWK=$(AWK))

## test setting CONNECTED=0
test-connected: $(AWK_BIN)/$(AWK)
	@$(call run-test,$@,make -s -f Makefile.inc CONNECTED=0,AWK=$(AWK))

## test setting COLOR_BACKTICKS=1
test-backticks: $(AWK_BIN)/$(AWK)
	@$(call run-test,$@,make -s -f Makefile.inc COLOR_BACKTICKS=1,AWK=$(AWK))

## test with default VARS=1
test-vars: $(AWK_BIN)/$(AWK)
	@$(call run-test,$@,make -s -f Makefile.var,AWK=$(AWK))

## test with VARS=0
test-no-vars: $(AWK_BIN)/$(AWK)
	@$(call run-test,$@,make -s -f Makefile.var VARS=0,AWK=$(AWK))

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
	@$(call verify-download)
	@wget -P $(AWK_BIN) $(URL_BUSYBOX_AWK)
	@mv $(AWK_BIN)/busybox_AWK $@ && chmod +x $@

$(AWK_BIN)/wak:
	@$(call verify-download)
	@wget -P $(AWK_BIN) $(URL_WAK)
	@mkdir -p $@-src
	@tar xvf $(AWK_BIN)/v24.10.tar.gz -C $@-src --strip-components=1
	@cd $@-src && make
	@cp $@-src/wak $@

$(AWK_BIN)/%: FORCE # a catch-all target for AWK values
	@echo "==================================================="
	@echo "Expected value for AWK: awk, mawk, nawk, bawk, wak."
	@echo "==================================================="
	@exit 1

FORCE:
