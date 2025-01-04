FOO := v1
BAR = $(FOO)
$(info [1] BAR: $(BAR)) # OK
FOO := v2
$(info [2] BAR: $(BAR)) # OK
FOO += v3
$(info [3] BAR: $(BAR)) # OK

with-target-specific-variable-append: FOO += v41
with-target-specific-variable-append:
	$(info ------ with-target-specific-variable-append ------ )
	@echo "[4] BAR: $(BAR)" # OK
	@$(eval FOO += v51)
	@echo "[5] BAR: $(BAR)" # not what I expect to see
	@$(eval FOO := v61)
	@echo "[6] BAR: $(BAR)" # not what I expect to see

with-target-specific-override-variable-append: override FOO += v41
with-target-specific-override-variable-append:
	$(info ------ with-target-specific-override-variable-append ------ )
	@echo "[4] BAR: $(BAR)" # OK
	@$(eval FOO += v51)
	@echo "[5] BAR: $(BAR)" # not what I expect to see
	@$(eval FOO := v61)
	@echo "[6] BAR: $(BAR)" # not what I expect to see

with-target-specific-variable-set: FOO := v41
with-target-specific-variable-set:
	$(info ------ with-target-specific-variable-set ------ )
	@echo "[4] BAR: $(BAR)" # OK
	@$(eval FOO += v51)
	@echo "[5] BAR: $(BAR)" # not what I expect to see
	@$(eval FOO := v61)
	@echo "[6] BAR: $(BAR)" # not what I expect to see

without-target-specific-variable:
without-target-specific-variable:
	$(info ------ without-target-specific-variable ------ )
	@echo "[4] BAR: $(BAR)" # OK
	@$(eval FOO += v52)
	@echo "[5] BAR: $(BAR)" # OK
	@$(eval FOO := v62)
	@echo "[6] BAR: $(BAR)" # OK

info:
	$(info ------ info ------ )
	@$(MAKE) --help | tail -2 | head -1
	@$(MAKE) --version
