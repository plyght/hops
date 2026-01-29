.PHONY: all build install uninstall test clean help

INSTALL_DIR := /usr/local/bin
BUILD_MODE := release

all: build

build:
	@echo "Building Hops..."
	@swift build -c $(BUILD_MODE)
	@echo "Code signing hopsd..."
	@codesign -s - --entitlements hopsd.entitlements --force .build/$(BUILD_MODE)/hopsd
	@echo "Build complete: .build/$(BUILD_MODE)/"

install:
	@./install.sh

uninstall:
	@echo "Uninstalling Hops..."
	@if [ -w "$(INSTALL_DIR)" ]; then \
		rm -f $(INSTALL_DIR)/hops $(INSTALL_DIR)/hopsd $(INSTALL_DIR)/hops-create-rootfs; \
	else \
		sudo rm -f $(INSTALL_DIR)/hops $(INSTALL_DIR)/hopsd $(INSTALL_DIR)/hops-create-rootfs; \
	fi
	@echo "Binaries removed from $(INSTALL_DIR)"
	@echo ""
	@echo "Note: Configuration directory ~/.hops not removed"
	@echo "To remove it: rm -rf ~/.hops"

test:
	@echo "Running tests..."
	@swift test

clean:
	@echo "Cleaning build artifacts..."
	@swift package clean
	@rm -rf .build
	@echo "Clean complete"

help:
	@echo "Hops Makefile"
	@echo ""
	@echo "Available targets:"
	@echo "  make build      - Build the project (default: release mode)"
	@echo "  make install    - Run the installation script"
	@echo "  make uninstall  - Remove installed binaries"
	@echo "  make test       - Run tests"
	@echo "  make clean      - Clean build artifacts"
	@echo "  make help       - Show this help message"
	@echo ""
	@echo "Environment variables:"
	@echo "  BUILD_MODE      - Build mode (release or debug, default: release)"
	@echo ""
	@echo "Examples:"
	@echo "  make build BUILD_MODE=debug"
	@echo "  make install"
