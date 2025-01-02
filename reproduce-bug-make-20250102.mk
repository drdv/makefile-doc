FOO := first
BAR = $(FOO)
$(info [1] BAR: $(BAR)) # OK
FOO := second
$(info [2] BAR: $(BAR)) # OK
FOO += third
$(info [3] BAR: $(BAR)) # OK

all: potential-bug info

# peculiar behaviour when the target-local FOO is defined using:
#  1. FOO := fourth
#  2. FOO += fourth
#  3. override FOO += fourth (when we make x FOO=something)
#  4. ...
potential-bug: override FOO += fourth
potential-bug:
	@echo "[4] BAR: $(BAR)" # OK
	@$(eval FOO += fifth)
	@echo "[5] BAR: $(BAR)" # not what I expect to see
	@$(eval FOO += sixth)
	@echo "[6] BAR: $(BAR)" # not what I expect to see

info:
	$(MAKE) --version
	$(MAKE) --help | tail -2 | head -1
