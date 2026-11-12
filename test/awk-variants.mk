# Targets for downloading and building the supported awk variants.
# Included from the root Makefile (uses AWK_BIN and SUPPORTED_AWK_VARIANTS).
#
# Each variant is built into $(AWK_BIN)/<variant> by a file target (used as a prerequisite
# by the test targets). Users call deps@<variant> and clean@<variant> instead.
#
# Every download is checked against its SHA256. An empty SHA256 (e.g., right after changing
# a version) skips the check and prints the value to fill in.

##@
##@------ Awk variants ------
##@

## Download and build awk variants
## (`deps@<variant>`, or all of them with `deps@all`; e.g., before `make -j test@all`)
.PHONY: deps@all $(addprefix deps@,$(SUPPORTED_AWK_VARIANTS))
deps@all: $(addprefix deps@,$(SUPPORTED_AWK_VARIANTS))
$(addprefix deps@,$(SUPPORTED_AWK_VARIANTS)): deps@%: $(AWK_BIN)/%

## Remove awk variants (with their downloads and sources)
## (`clean@<variant>`, or all of them with `clean@all`)
.PHONY: clean@all $(addprefix clean@,$(SUPPORTED_AWK_VARIANTS))
clean@all:
	@rm -rf $(AWK_BIN)
$(addprefix clean@,$(SUPPORTED_AWK_VARIANTS)): clean@%:
	@rm -rf $(AWK_BIN)/$* $(AWK_BIN)/$*-*

# ------------------------------------------------------------------------------------------
# versions, downloads and build commands
# ------------------------------------------------------------------------------------------
# gawk is the one installed on the system (test/bench.py reads its version)
gawk_VERSION :=

# the author's git export of mawk (invisible-island.net blocks scripted downloads at times)
mawk_VERSION := t20260302
mawk_URL := https://github.com/ThomasDickey/mawk-snapshots/archive/refs/tags/$(mawk_VERSION).tar.gz
mawk_SHA256 := 68740bcb801350b0d8be79fe794baa1186e3d1c718511a17d6690b8d0995bbc6
mawk_BUILD := ./configure && make
mawk_BINARY := mawk

nawk_VERSION := 20240728
nawk_URL := https://github.com/onetrueawk/awk/archive/refs/tags/$(nawk_VERSION).tar.gz
nawk_SHA256 := 2d479817f95d5997fc4348ecebb1d8a1b25c81cebedb46ca4f59434247e08543
nawk_BUILD := make
nawk_BINARY := a.out

wak_VERSION := v24.10
wak_URL := https://github.com/raygard/wak/archive/refs/tags/$(wak_VERSION).tar.gz
wak_SHA256 := b0902e299d9956e5920c3a0fff686de3b9dc60b7e3cc5c658fb379a5835d4c0c
wak_BUILD := make
wak_BINARY := wak

# requires go (e.g., `sudo dnf install golang`)
goawk_VERSION := v1.30.0
goawk_URL := https://github.com/benhoyt/goawk/archive/refs/tags/$(goawk_VERSION).tar.gz
goawk_SHA256 := 7a42ca223f1319483c3f46014c80f5e78e8410be29175ac852d88b79e3e64a36
goawk_BUILD := go build -o goawk goawk.go
goawk_BINARY := goawk

# a prebuilt binary (x86_64 linux only)
bawk_VERSION := 1.35.0
bawk_URL := https://busybox.net/downloads/binaries/$(bawk_VERSION)-x86_64-linux-musl/busybox_AWK
bawk_SHA256 := a0be3443bc46b48c761249003bf5d0750afac092bc87d2a541d09bce05172a7b

SOURCE_VARIANTS := mawk nawk wak goawk

# ------------------------------------------------------------------------------------------
# rules
# ------------------------------------------------------------------------------------------
SHA256SUM := $(if $(shell command -v sha256sum),sha256sum,shasum -a 256)

# $(call download,URL,FILE,SHA256): download URL to FILE and check its SHA256
define download
	@mkdir -p $(AWK_BIN)
	@curl -fsSL -o $(2) $(1)
	@sum=$$($(SHA256SUM) $(2) | cut -d ' ' -f 1); \
	if [ -z "$(3)" ]; then \
		echo "WARNING: no SHA256 to check $(notdir $(2)) (it is $$sum)"; \
	elif [ "$$sum" != "$(3)" ]; then \
		echo "ERROR: wrong SHA256 for $(notdir $(2)): $$sum (expected $(3))"; \
		rm -f $(2); \
		exit 1; \
	fi
endef

# awk and gawk are the ones installed on the system
$(AWK_BIN)/awk $(AWK_BIN)/gawk:
	@path=$$(command -v $(notdir $@)) || { echo "$(notdir $@) is not installed"; exit 1; }; \
	mkdir -p $(AWK_BIN) && ln -sf "$$path" $@

# variants built from a source archive (see the <variant>_* variables above)
$(addprefix $(AWK_BIN)/,$(SOURCE_VARIANTS)): $(AWK_BIN)/%:
	$(call download,$($*_URL),$(AWK_BIN)/$*-$($*_VERSION).tar.gz,$($*_SHA256))
	@rm -rf $@-src && mkdir -p $@-src
	@tar xzf $(AWK_BIN)/$*-$($*_VERSION).tar.gz -C $@-src --strip-components=1
	@cd $@-src && $($*_BUILD)
	@cp $@-src/$($*_BINARY) $@

$(AWK_BIN)/bawk:
ifeq ($(shell uname),Darwin)
	@echo "Busybox awk binaries are not available for macos"
	@exit 1
else
	$(call download,$(bawk_URL),$(AWK_BIN)/bawk-$(bawk_VERSION),$(bawk_SHA256))
	@cp $(AWK_BIN)/bawk-$(bawk_VERSION) $@ && chmod +x $@
endif

$(AWK_BIN)/%: # a catch-all target for AWK values
	@echo "==================================================="
	@echo "Supported AWK variants: $(SUPPORTED_AWK_VARIANTS)"
	@echo "==================================================="
	@exit 1
