FOO := v1
BAR = $(FOO)
$(info [1] BAR: $(BAR)) # OK
FOO := v2
$(info [2] BAR: $(BAR)) # OK
FOO += v3
$(info [3] BAR: $(BAR)) # OK

with-target-specific-variable: override FOO += v41
with-target-specific-variable:
	$(info ------ with-target-specific-variable ------ )
	@echo "[4] BAR: $(BAR)" # OK
	@$(eval FOO += v51)
	@echo "[5] BAR: $(BAR)" # not what I expect to see
	@$(eval FOO := v61)
	@echo "[6] BAR: $(BAR)" # not what I expect to see

with-target-specific-override-variable: override FOO += v41
with-target-specific-override-variable:
	$(info ------ with-target-specific-override-variable ------ )
	@echo "[4] BAR: $(BAR)" # OK
	@$(eval FOO += v51)
	@echo "[5] BAR: $(BAR)" # not what I expect to see
	@$(eval FOO := v61)
	@echo "[6] BAR: $(BAR)" # not what I expect to see

without-target-specific-variable:
without-target-specific-variable:
	$(info ------ without-target-specific-variable ------ )
	@echo "[7] BAR: $(BAR)" # OK
	@$(eval FOO += v52)
	@echo "[8] BAR: $(BAR)" # OK
	@$(eval FOO := v62)
	@echo "[9] BAR: $(BAR)" # OK

info:
	$(info ------ info ------ )
	@$(MAKE) --help | tail -2 | head -1
	@$(MAKE) --version
