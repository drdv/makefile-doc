# Targets for downloading and building the supported awk variants.
# Included from the root Makefile (uses AWK_BIN and SUPPORTED_AWK_VARIANTS).

##@
##@------ Awk variants ------
##@

## Download/build all supported awk variants (run this before using `make -j`)
.PHONY: deps
deps: $(addprefix $(AWK_BIN)/,$(SUPPORTED_AWK_VARIANTS))

# using $1 instead of $(AWK) is necessary for a target like
# deps: $(AWK_BIN)/mawk $(AWK_BIN)/nawk $(AWK_BIN)/bawk $(AWK_BIN)/wak
define verify-download
	read -p "Download and build $1 [Y/n]: " ans \
		&& ([ -z $$ans ] || [ $$ans = y ] || [ $$ans = Y ]) \
		&& exit 0 \
		|| echo "Download of $1 cancelled"; exit 1
endef

define download
	$(DOWNLOAD_$(DOWNLOAD_TOOL)) https://$(URL)
endef

$(AWK_BIN)/awk:
	@mkdir -p $(AWK_BIN)
	@ln -s $(shell which awk) $@

$(AWK_BIN)/mawk: URL := invisible-island.net/datafiles/release/mawk.tar.gz
$(AWK_BIN)/mawk:
	@$(call verify-download,mawk)
	@$(call download)
	@mkdir -p $@-src
	@tar xvf $(AWK_BIN)/mawk.tar.gz -C $@-src --strip-components=1
	@cd $@-src && ./configure && make
	@cp $@-src/mawk $@

$(AWK_BIN)/nawk: RELEASE := 20240728
$(AWK_BIN)/nawk: URL := github.com/onetrueawk/awk/archive/refs/tags/$(RELEASE).tar.gz
$(AWK_BIN)/nawk:
	@$(call verify-download,nawk)
	@$(call download)
	@mkdir -p $@-src
	@tar xvf $(AWK_BIN)/$(RELEASE).tar.gz -C $@-src --strip-components=1
	@cd $@-src && make
	@cp $@-src/a.out $@

$(AWK_BIN)/bawk: URL := busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox_AWK
$(AWK_BIN)/bawk:
ifeq ($(shell uname),Darwin)
	@echo "Busybox awk binaries not available for macos"
	@exit 1
else
	@$(call verify-download,bawk)
	@$(call download)
	@mv $(AWK_BIN)/busybox_AWK $@ && chmod +x $@
endif

$(AWK_BIN)/wak: RELEASE := v24.10
$(AWK_BIN)/wak: URL := github.com/raygard/wak/archive/refs/tags/$(RELEASE).tar.gz
$(AWK_BIN)/wak:
	@$(call verify-download,wak)
	@$(call download)
	@mkdir -p $@-src
	@tar xvf $(AWK_BIN)/$(RELEASE).tar.gz -C $@-src --strip-components=1
	@cd $@-src && make
	@cp $@-src/wak $@

# requires: sudo dnf install golang
$(AWK_BIN)/goawk: RELEASE := v1.30.0
$(AWK_BIN)/goawk: URL := github.com/benhoyt/goawk/archive/refs/tags/$(RELEASE).tar.gz
$(AWK_BIN)/goawk:
	@$(call verify-download,goawk)
	@$(call download)
	@mkdir -p $@-src
	@tar xvf $(AWK_BIN)/$(RELEASE).tar.gz -C $@-src --strip-components=1
	@cd $@-src && go build -o goawk goawk.go
	@cp $@-src/goawk $@

$(AWK_BIN)/%: # a catch-all target for AWK values
	@echo "==================================================="
	@echo "Supported AWK variants: $(SUPPORTED_AWK_VARIANTS)"
	@echo "==================================================="
	@exit 1
