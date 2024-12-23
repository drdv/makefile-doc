TEST_DIR := test
AWK_BIN := $(TEST_DIR)/bin

URL_MAWK := https://invisible-island.net/datafiles/release/mawk.tar.gz
URL_NAWK := https://github.com/onetrueawk/awk/archive/refs/tags/20240728.tar.gz
URL_BAWK := https://www.busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox_AWK
URL_WAK := https://github.com/raygard/wak/archive/refs/tags/v24.10.tar.gz
UNTAR := tar xvf

## Awk executable
##  + `awk` (system's default)
##  + `bin/mawk`
##  + `bin/nawk`
##  + ...
AWK := awk

define run-test
	cd test && $2 $3 > tmp.txt
	tail -n +4 $(TEST_DIR)/expected_output/$1 > /tmp/expected_output # <(...) doesn't work on dash
	diff -u /tmp/expected_output $(TEST_DIR)/tmp.txt || \
	(echo "failed $1"; exit 1)
	echo "passed $1 ($3)"
endef

help: ## show this help
	@$(AWK) -f ./makefile-doc.awk $(MAKEFILE_LIST)

## run all tests (`make test AWK=custom-awk`)
.PHONY: test
test: test-default \
	test-deprecated \
	test-padding \
	test-connected \
	test-backticks \
	test-vars \
	test-no-vars \
	_clean-tmp

_clean-tmp:
	@rm -rf $(TEST_DIR)/tmp.txt

##@
##@ ----- Individual tests -----
##@

test-default: ## test default behavior
	@$(call run-test,$@,make -s,AWK=$(AWK))

test-deprecated: ## test setting DEPRECATED=0
	@$(call run-test,$@,make -s -f Makefile.inc DEPRECATED=0,AWK=$(AWK))

test-padding: ## test setting PADDING="."
	@$(call run-test,$@,make -s -f Makefile.inc PADDING=".",AWK=$(AWK))

test-connected: ## test setting CONNECTED=0
	@$(call run-test,$@,make -s -f Makefile.inc CONNECTED=0,AWK=$(AWK))

test-backticks: ## test setting COLOR_BACKTICKS=1
	@$(call run-test,$@,make -s -f Makefile.inc COLOR_BACKTICKS=1,AWK=$(AWK))

test-vars: ## test with default VARS=1
	@$(call run-test,$@,make -s -f Makefile.var,AWK=$(AWK))

test-no-vars: ## test with VARS=0
	@$(call run-test,$@,make -s -f Makefile.var VARS=0,AWK=$(AWK))

##@
##@ ----- Get other awk implementations -----
##@

## download and build all other
build-other-awk-versions: mawk nawk bawk wak

mawk: ## download and build mawk
	@wget -P $(AWK_BIN) $(URL_MAWK)
	@mkdir -p $(AWK_BIN)/src-$@
	$(UNTAR) $(AWK_BIN)/mawk.tar.gz -C $(AWK_BIN)/src-$@ --strip-components=1
	@cd $(AWK_BIN)/src-$@ && ./configure && make && cp $@ ../$@

nawk: ## download and build nawk
	@wget -P $(AWK_BIN) $(URL_NAWK)
	@mkdir -p $(AWK_BIN)/src-$@
	@$(UNTAR) $(AWK_BIN)/20240728.tar.gz -C $(AWK_BIN)/src-$@ --strip-components=1
	@cd $(AWK_BIN)/src-$@ && make && cp a.out ../$@

bawk: ## download and build busybox awk
	@wget -P $(AWK_BIN) $(URL_BAWK)
	@mv $(AWK_BIN)/busybox_AWK $(AWK_BIN)/$@
	@chmod +x $(AWK_BIN)/$@

wak: ## download and build wak
	@wget -P $(AWK_BIN) $(URL_WAK)
	@mkdir -p $(AWK_BIN)/src-$@
	@$(UNTAR) $(AWK_BIN)/v24.10.tar.gz -C $(AWK_BIN)/src-$@ --strip-components=1
	@cd $(AWK_BIN)/src-$@ && make && cp wak ../$@

clean-bin: ##! remove the awk bin dir
	@rm -rf $(AWK_BIN)
