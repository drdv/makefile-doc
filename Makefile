TMP_DIR := /tmp/makefile-doc-test-dir
EXPECTED_OUTPUT_DIR := test/expected_output

define run-test
	@mkdir -p $(TMP_DIR) && cd test && $2 > $(TMP_DIR)/out
	@diff -u $(EXPECTED_OUTPUT_DIR)/$1 $(TMP_DIR)/out || (echo "failed $1"; exit 1)
	@echo "passed $1"
endef

help: ## show this help
	@awk -f ./makefile-doc.awk $(MAKEFILE_LIST)

## run all tests
.PHONY: test
test: test-default test-deprecated test-padding test-header test-connected clean-tmp-dir

##@
##@ ----- Individual tests -----
##@

test-default: ## test default behavior
	@$(call run-test,$@, make -s)

test-deprecated: ## test setting DEPRECATED=0
	@$(call run-test,$@, make -s -f Makefile.inc DEPRECATED=0)

test-padding: ## test setting PADDING="."
	@$(call run-test,$@, make -s -f Makefile.inc PADDING='.')

test-header: ## test setting HEADER=0
	@$(call run-test,$@, make -s -f Makefile.inc HEADER=0 PADDING='.')

test-connected: ## test setting CONNECTED=0
	@$(call run-test,$@, make -s -f Makefile.inc CONNECTED=0)

clean-tmp-dir:
	@rm -rf $(TMP_DIR)
