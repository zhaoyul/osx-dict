# Makefile for osx-dict
#
# Builds a self-contained macOS .app bundle that can be launched directly
# (no Xcode or signing required for local use).
#
# Requirements:
#   • macOS with Xcode Command Line Tools  (xcode-select --install)
#   • clang (ships with the above)
#
# Usage:
#   make          – build osx-dict.app in build/
#   make run      – build and launch the app
#   make clean    – remove build artefacts

# --------------------------------------------------------------------------
# Configuration
# --------------------------------------------------------------------------
APP_NAME   := osx-dict
BUNDLE     := build/$(APP_NAME).app
BIN        := $(BUNDLE)/Contents/MacOS/$(APP_NAME)
PLIST_SRC  := Info.plist
PLIST_DST  := $(BUNDLE)/Contents/Info.plist

SRC_DIR    := src
SRCS       := $(SRC_DIR)/main.m        \
              $(SRC_DIR)/AppDelegate.m  \
              $(SRC_DIR)/PopupWindow.m  \
              $(SRC_DIR)/TextGrabber.c  \
              $(SRC_DIR)/DictService.c

# --------------------------------------------------------------------------
# Compiler / linker flags
# --------------------------------------------------------------------------
CC         := clang
CFLAGS     := -Wall -Wextra -O2 \
              -fobjc-arc \
              -I$(SRC_DIR)

LDFLAGS    := -framework Cocoa            \
              -framework ApplicationServices \
              -framework Carbon           \
              -framework CoreFoundation   \
              -framework CoreGraphics

# --------------------------------------------------------------------------
# Targets
# --------------------------------------------------------------------------
.PHONY: all run clean

all: $(BIN) $(PLIST_DST)
	@echo "Build complete: $(BUNDLE)"

$(BIN): $(SRCS) | $(BUNDLE)/Contents/MacOS
	$(CC) $(CFLAGS) $(SRCS) $(LDFLAGS) -o $@

$(PLIST_DST): $(PLIST_SRC) | $(BUNDLE)/Contents
	cp $(PLIST_SRC) $(PLIST_DST)

$(BUNDLE)/Contents/MacOS:
	mkdir -p $@

$(BUNDLE)/Contents:
	mkdir -p $@

run: all
	open $(BUNDLE)

clean:
	rm -rf build/
