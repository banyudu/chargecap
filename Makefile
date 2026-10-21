ROOT_DIR := $(CURDIR)
PROJECT := $(ROOT_DIR)/ChargeCap.xcodeproj
SCHEME := ChargeCap
BUILD_DIR := $(ROOT_DIR)/.build/xcode
DIST_APP := $(ROOT_DIR)/dist/ChargeCap.app
SIGN_IDENTITY ?= $(shell security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' | head -n 1)

.PHONY: project build build-unsigned install run release clean

project:
	xcodegen generate

build: project
	@test -n "$(SIGN_IDENTITY)" || (echo "No Developer ID Application certificate found." >&2; exit 1)
	xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -configuration Release \
		-derivedDataPath "$(BUILD_DIR)" build \
		CODE_SIGNING_ALLOWED=YES \
		CODE_SIGN_STYLE=Manual \
		CODE_SIGN_IDENTITY="$(SIGN_IDENTITY)" \
		DEVELOPMENT_TEAM=RYLS8UDY5D
	mkdir -p "$(ROOT_DIR)/dist"
	rm -rf "$(DIST_APP)"
	ditto "$(BUILD_DIR)/Build/Products/Release/ChargeCap.app" "$(DIST_APP)"
	codesign --verify --deep --strict "$(DIST_APP)"
	@echo "Built $(DIST_APP)"

build-unsigned: project
	xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -configuration Debug \
		-derivedDataPath "$(BUILD_DIR)" build \
		CODE_SIGNING_ALLOWED=NO

install: build
	./scripts/install.sh

run: build
	open "$(DIST_APP)"

release:
	./scripts/release.sh $(VERSION)

clean:
	rm -rf "$(BUILD_DIR)" "$(ROOT_DIR)/dist" "$(PROJECT)"
