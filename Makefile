# gameWE - SourceMod plugin
#   make build | package | clean
#
# Needs spcomp from SourceMod 1.12 or newer in PATH, or set SPCOMP=/path/to/spcomp.
# spcomp finds the SourceMod includes next to itself; add more with SM_INCLUDE=dir.
#
# The version comes from the git tag on HEAD (v1.2.3 -> 1.2.3), otherwise
# from the VERSION file. Override with: make package VERSION=1.2.3-rc1

SPCOMP     ?= spcomp
SM_INCLUDE ?=
GIT_TAG    := $(shell git describe --tags --exact-match --match 'v*' 2>/dev/null)
VERSION    ?= $(if $(GIT_TAG),$(patsubst v%,%,$(GIT_TAG)),$(shell cat VERSION))

SRC      := addons/sourcemod/scripting
STAGE    := build/stage
PLUGINS  := $(STAGE)/addons/sourcemod/plugins
PKG      := gamewe-sourcemod-$(VERSION)
DIST     := dist

# -E: warnings are errors, so the code stays warning free
SPFLAGS  := -E -O2 -v0 -i $(SRC)/include $(if $(SM_INCLUDE),-i $(SM_INCLUDE)) 'GAMEWE_PLUGIN_VERSION="$(VERSION)"'

.PHONY: all build package clean

all: build

build:
	rm -rf $(STAGE)
	install -d $(PLUGINS)/disabled
	$(SPCOMP) $(SPFLAGS) $(SRC)/gamewe.sp -o $(PLUGINS)/gamewe.smx
	$(SPCOMP) $(SPFLAGS) $(SRC)/gamewe_messages.sp -o $(PLUGINS)/disabled/gamewe_messages.smx

package: build
	cp -r addons/sourcemod/scripting addons/sourcemod/translations $(STAGE)/addons/sourcemod/
	install -m 0644 README.md CHANGELOG.md LICENSE $(STAGE)/
	install -d $(DIST)
	rm -f $(DIST)/$(PKG).tar.gz $(DIST)/$(PKG).zip $(DIST)/$(PKG).sha256 \
		$(DIST)/$(PKG).tar.gz.sha256 $(DIST)/$(PKG).zip.sha256
	tar --sort=name --owner=0 --group=0 --numeric-owner -C $(STAGE) -czf $(DIST)/$(PKG).tar.gz addons README.md CHANGELOG.md LICENSE
	cd $(STAGE) && zip -qrX ../../$(DIST)/$(PKG).zip addons README.md CHANGELOG.md LICENSE
	cd $(DIST) && sha256sum $(PKG).tar.gz > $(PKG).tar.gz.sha256
	cd $(DIST) && sha256sum $(PKG).zip > $(PKG).zip.sha256
	@echo "built $(DIST)/$(PKG).tar.gz and $(DIST)/$(PKG).zip"

clean:
	rm -rf build $(DIST)
