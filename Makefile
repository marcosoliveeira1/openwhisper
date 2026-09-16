APP_NAME := OpenWhisper
BUNDLE_ID := br.marcos.openwhisper
APP_DIR := build/$(APP_NAME).app
CONTENTS := $(APP_DIR)/Contents
MACOS_DIR := $(CONTENTS)/MacOS
RESOURCES_DIR := $(CONTENTS)/Resources

.PHONY: all build app run test clean

# CLT 27.0 ships without libSwiftUIMacros.dylib (SwiftUI macros broke);
# build against the previous SDK while the workaround is needed.
SDK_265 := $(wildcard /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk)
ifneq ($(SDK_265),)
export SDKROOT := $(SDK_265)
endif

all: app

build:
	swift build -c release

app: build
	mkdir -p $(MACOS_DIR) $(RESOURCES_DIR)
	cp .build/release/$(APP_NAME) $(MACOS_DIR)/
	cp Info.plist $(CONTENTS)/
	cp Resources/AppIcon.icns $(RESOURCES_DIR)/
	plutil -replace CFBundleIdentifier -string $(BUNDLE_ID) $(CONTENTS)/Info.plist
	touch $(APP_DIR)
	codesign --force --sign - $(APP_DIR)

run: app
	open $(APP_DIR)

test:
	swift test

clean:
	rm -rf .build build
