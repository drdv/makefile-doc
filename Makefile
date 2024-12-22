TEST_DIR := test
AWK_BIN := $(TEST_DIR)/bin

AWK := awk

define run-test
	cd test && $2 $3 > tmp.txt
	@diff -u $(TEST_DIR)/expected_output/$1 $(TEST_DIR)/tmp.txt || (echo "failed $1"; exit 1)
	@echo "passed $1 ($3)"
endef

help: ## show this help
	@$(AWK) -f ./makefile-doc.awk $(MAKEFILE_LIST)

## run all tests (`make test AWK=custom-awk`)
.PHONY: test
test: test-default \
	test-deprecated \
	test-padding \
	test-header \
	test-connected \
	test-backticks \
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
	@$(call run-test,$@,make -s -f Makefile.inc PADDING='.',AWK=$(AWK))

test-header: ## test setting HEADER=0
	@$(call run-test,$@,make -s -f Makefile.inc HEADER=0 PADDING='.',AWK=$(AWK))

test-connected: ## test setting CONNECTED=0
	@$(call run-test,$@,make -s -f Makefile.inc CONNECTED=0,AWK=$(AWK))

test-backticks: ## test setting COLOR_BACKTICKS=1
	@$(call run-test,$@,make -s -f Makefile.inc COLOR_BACKTICKS=1,AWK=$(AWK))

##@
##@ ----- Download mawk and nawk -----
##@

## download and build mawk and nawk
build-other-awk-versions: mawk nawk

mawk: ## download and build mawk
	@wget -P $(AWK_BIN) https://invisible-island.net/datafiles/release/mawk.tar.gz
	@mkdir -p $(AWK_BIN)/src-$@
	@tar xvf $(AWK_BIN)/mawk.tar.gz -C $(AWK_BIN)/src-$@ --strip-components=1
	@cd $(AWK_BIN)/src-$@ && ./configure && make && cp $@ ../$@

nawk: ## download and build nawk
	@wget -P $(AWK_BIN) https://github.com/onetrueawk/awk/archive/refs/tags/20240728.tar.gz
	@mkdir -p $(AWK_BIN)/src-$@
	@tar xvf $(AWK_BIN)/20240728.tar.gz -C $(AWK_BIN)/src-$@ --strip-components=1
	@cd $(AWK_BIN)/src-$@ && make && cp a.out ../$@

clean-bin: ##! remove the awk bin
	@rm -rf $(AWK_BIN)
