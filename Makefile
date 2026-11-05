APP_NAME := Jeff
APP_DIR  ?= $(APP_NAME).app
BINARY   := .build/$(APP_NAME)
SOURCES  := $(wildcard Sources/Jeff/*.swift)
VERSION  := $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
SIGN_IDENTITY ?= -
SIGN_OPTIONS ?=
DIST_DIR := dist
DISK_IMAGE := $(APP_NAME)-$(VERSION)-macos-arm64.dmg
DMGBUILD := .build/dmg-venv/bin/dmgbuild

.PHONY: build bundle install run dmg package lint typecheck clean

build:
	mkdir -p .build
	xcrun swiftc -O -o $(BINARY) $(SOURCES) -target arm64-apple-macosx14.0

bundle: build
	rm -rf $(APP_DIR)
	mkdir -p $(APP_DIR)/Contents/MacOS $(APP_DIR)/Contents/Resources
	cp $(BINARY) $(APP_DIR)/Contents/MacOS/$(APP_NAME)
	cp Resources/Info.plist $(APP_DIR)/Contents/Info.plist
	cp Resources/Icons/AppIcon.icns Resources/Icons/MenuBarIcon.pdf $(APP_DIR)/Contents/Resources/
	cp -R Resources/Skills $(APP_DIR)/Contents/Resources/Skills
	cp LICENSE $(APP_DIR)/Contents/Resources/LICENSE
	codesign --force --sign "$(SIGN_IDENTITY)" $(SIGN_OPTIONS) $(APP_DIR)

install: bundle
	mkdir -p ~/Applications
	rm -rf ~/Applications/$(APP_DIR)
	cp -R $(APP_DIR) ~/Applications/$(APP_DIR)

run: bundle
	open $(APP_DIR)

$(DMGBUILD): Resources/DMG/requirements.txt
	python3 -m venv .build/dmg-venv
	.build/dmg-venv/bin/python -m pip install --disable-pip-version-check -r $<
	touch $(DMGBUILD)

dmg: $(DMGBUILD)
	$(MAKE) bundle APP_DIR="$(DIST_DIR)/$(APP_NAME).app"
	$(DMGBUILD) -s Resources/DMG/settings.py -D app="$(DIST_DIR)/$(APP_NAME).app" "$(APP_NAME)" "$(DIST_DIR)/$(DISK_IMAGE)"

package: dmg
	cd "$(DIST_DIR)" && shasum -a 256 "$(DISK_IMAGE)" > SHA256SUMS.txt

lint:
	xcrun swift-format lint --strict --configuration '{"indentation":{"spaces":4}}' $(SOURCES)

typecheck:
	xcrun swiftc -typecheck $(SOURCES) -target arm64-apple-macosx14.0

clean:
	rm -rf .build $(APP_DIR) $(DIST_DIR)
