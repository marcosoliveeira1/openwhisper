APP_NAME := OpenWhisper
BUNDLE_ID := br.marcos.openwhisper
APP_DIR := build/$(APP_NAME).app
CONTENTS := $(APP_DIR)/Contents
MACOS_DIR := $(CONTENTS)/MacOS

.PHONY: all build app run test clean

all: app

build:
	swift build -c release

app: build
	mkdir -p $(MACOS_DIR)
	cp .build/release/$(APP_NAME) $(MACOS_DIR)/
	cp Info.plist $(CONTENTS)/
	plutil -replace CFBundleIdentifier -string $(BUNDLE_ID) $(CONTENTS)/Info.plist
	touch $(APP_DIR)
	codesign --force --sign - $(APP_DIR)

run: app
	open $(APP_DIR)

test:
	swift test

clean:
	rm -rf .build build
