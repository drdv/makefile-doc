TMP_DIR := /tmp/makefile-doc-test-dir
EXPECTED_OUTPUT_DIR := test/expected_output

AWK := awk
# AWK := $(TMP_DIR)/mawk/mawk
# AWK := $(TMP_DIR)/nawk/nawk

define run-test
	@mkdir -p $(TMP_DIR) && cd test && $2 $3 > $(TMP_DIR)/out
	@diff -u $(EXPECTED_OUTPUT_DIR)/$1 $(TMP_DIR)/out || (echo "failed $1"; exit 1)
	@echo "passed $1 ($3)"
endef

help: ## show this help
	@awk -f ./makefile-doc.awk $(MAKEFILE_LIST)

## run all tests
.PHONY: test
test: test-default test-deprecated test-padding test-header test-connected

clean: ## clean tmp stuff
	@rm -rf $(TMP_DIR)

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

##@
##@ ----- Download mawk and nawk -----
##@

## download and build mawk and nawk
build-other-awk-versions: mawk nawk

mawk: ## download and build mawk
	@mkdir -p $(TMP_DIR)/$@
	@wget -P $(TMP_DIR) https://invisible-island.net/datafiles/release/mawk.tar.gz
	@tar xvf $(TMP_DIR)/mawk.tar.gz -C $(TMP_DIR)/$@ --strip-components=1
	@cd $(TMP_DIR)/$@ && ./configure && make

nawk: ## download and build nawk
	@mkdir -p $(TMP_DIR)/$@
	@wget -P $(TMP_DIR) https://github.com/onetrueawk/awk/archive/refs/tags/20240728.tar.gz
	@tar xvf $(TMP_DIR)/20240728.tar.gz -C $(TMP_DIR)/$@ --strip-components=1
	@cd $(TMP_DIR)/$@ && make && mv $(TMP_DIR)/$@/a.out $(TMP_DIR)/$@/$@
