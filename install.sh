#!/usr/bin/env bash
set -euo pipefail

HOPS_DIR="${HOME}/.hops"
INSTALL_DIR="/usr/local/bin"
BUILD_MODE="${BUILD_MODE:-release}"

echo "Hops Installation Script"
echo "========================"
echo

check_macos_version() {
	local version
	version=$(sw_vers -productVersion | cut -d. -f1)
	if [[ "$version" -lt 15 ]]; then
		echo "Error: Hops requires macOS 15 (Sequoia) or later"
		echo "Current version: $(sw_vers -productVersion)"
		exit 1
	fi
}

check_architecture() {
	local arch
	arch=$(uname -m)
	if [[ "$arch" != "arm64" ]]; then
		echo "Error: Hops requires Apple Silicon (arm64)"
		echo "Current architecture: $arch"
		exit 1
	fi
}

check_swift() {
	if ! command -v swift &>/dev/null; then
		echo "Error: Swift not found. Please install Xcode Command Line Tools."
		exit 1
	fi

	local version
	version=$(swift --version | head -n1 | grep -oE '[0-9]+\.[0-9]+' | head -n1)
	local major="${version%%.*}"

	if [[ "$major" -lt 6 ]]; then
		echo "Error: Swift 6.0+ required, found version $version"
		exit 1
	fi
}

build_project() {
	echo "[1/7] Building Hops..."

	if [[ "$BUILD_MODE" == "release" ]]; then
		swift build -c release
	else
		swift build
	fi

	echo "     ✓ Build complete"
	echo
}

codesign_hopsd() {
	echo "[2/7] Code signing hopsd..."

	local hopsd_path
	if [[ "$BUILD_MODE" == "release" ]]; then
		hopsd_path=".build/release/hopsd"
	else
		hopsd_path=".build/debug/hopsd"
	fi

	if [[ ! -f "hopsd.entitlements" ]]; then
		echo "Error: hopsd.entitlements not found"
		exit 1
	fi

	codesign -s - --entitlements hopsd.entitlements --force "$hopsd_path"
	echo "     ✓ Code signing complete"
	echo
}

install_binaries() {
	echo "[3/7] Installing binaries to $INSTALL_DIR..."

	local build_dir
	if [[ "$BUILD_MODE" == "release" ]]; then
		build_dir=".build/release"
	else
		build_dir=".build/debug"
	fi

	if [[ ! -w "$INSTALL_DIR" ]]; then
		echo "     Note: Installing to $INSTALL_DIR requires sudo"
		sudo cp "$build_dir/hops" "$INSTALL_DIR/"
		sudo cp "$build_dir/hopsd" "$INSTALL_DIR/"
		sudo cp "$build_dir/hops-create-rootfs" "$INSTALL_DIR/"
		sudo chmod +x "$INSTALL_DIR/hops" "$INSTALL_DIR/hopsd" "$INSTALL_DIR/hops-create-rootfs"
	else
		cp "$build_dir/hops" "$INSTALL_DIR/"
		cp "$build_dir/hopsd" "$INSTALL_DIR/"
		cp "$build_dir/hops-create-rootfs" "$INSTALL_DIR/"
		chmod +x "$INSTALL_DIR/hops" "$INSTALL_DIR/hopsd" "$INSTALL_DIR/hops-create-rootfs"
	fi

	echo "     ✓ Binaries installed"
	echo
}

create_directory_structure() {
	echo "[4/7] Creating directory structure..."

	mkdir -p "$HOPS_DIR"/{profiles,logs,containers,rootfs}

	echo "     ✓ Directories created"
	echo "       - $HOPS_DIR/profiles"
	echo "       - $HOPS_DIR/logs"
	echo "       - $HOPS_DIR/containers"
	echo "       - $HOPS_DIR/rootfs"
	echo
}

download_runtime_files() {
	echo "[5/7] Checking runtime files..."

	local needs_download=false

	if [[ ! -f "$HOPS_DIR/vmlinux" ]]; then
		echo "     Missing: vmlinux (Linux kernel)"
		needs_download=true
	fi

	if [[ ! -f "$HOPS_DIR/initfs" ]]; then
		echo "     Missing: initfs (init filesystem)"
		needs_download=true
	fi

	if [[ "$needs_download" == "true" ]]; then
		echo
		echo "     Would you like to download missing files? (y/n)"
		read -r response
		if [[ "$response" =~ ^[Yy]$ ]]; then
			download_vmlinux
			download_initfs
		else
			echo "     Skipping download. You can run 'hops init' later to download."
		fi
	else
		echo "     ✓ All runtime files present"
	fi
	echo
}

download_vmlinux() {
	if [[ ! -f "$HOPS_DIR/vmlinux" ]]; then
		echo "     Downloading vmlinux..."
		curl -L -o "$HOPS_DIR/vmlinux" \
			"https://github.com/apple/container/releases/latest/download/vmlinux"
		chmod 644 "$HOPS_DIR/vmlinux"
		echo "     ✓ vmlinux downloaded"
	fi
}

download_initfs() {
	if [[ ! -f "$HOPS_DIR/initfs" ]]; then
		echo "     Downloading initfs..."
		curl -L -o "$HOPS_DIR/initfs" \
			"https://github.com/apple/container/releases/latest/download/init.block"
		chmod 644 "$HOPS_DIR/initfs"
		echo "     ✓ initfs downloaded"
	fi
}

setup_alpine_rootfs() {
	echo "[6/7] Checking Alpine rootfs..."

	if [[ -f "$HOPS_DIR/alpine-rootfs.ext4" ]]; then
		echo "     ✓ Alpine rootfs already exists"
	else
		echo "     Missing: alpine-rootfs.ext4"
		echo
		echo "     Would you like to create Alpine rootfs? (y/n)"
		read -r response
		if [[ "$response" =~ ^[Yy]$ ]]; then
			create_alpine_rootfs
		else
			echo "     Skipping rootfs creation. You can run 'hops init' later."
		fi
	fi
	echo
}

create_alpine_rootfs() {
	local tarball="$HOPS_DIR/alpine-minirootfs.tar.gz"

	if [[ ! -f "$tarball" ]]; then
		echo "     Downloading Alpine minirootfs..."
		curl -L -o "$tarball" \
			"https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/aarch64/alpine-minirootfs-3.19.1-aarch64.tar.gz"
	fi

	echo "     Creating rootfs image..."
	"$INSTALL_DIR/hops-create-rootfs"

	rm -f "$tarball"
	echo "     ✓ Alpine rootfs created"
}

copy_example_profiles() {
	echo "[7/7] Installing example profiles..."

	if [[ -d "config/profiles" ]]; then
		for profile in config/profiles/*.toml; do
			if [[ -f "$profile" ]]; then
				cp "$profile" "$HOPS_DIR/profiles/"
			fi
		done
		echo "     ✓ Example profiles installed"
	else
		echo "     No example profiles found (skipping)"
	fi
	echo
}

print_summary() {
	echo "========================"
	echo "Installation Complete!"
	echo "========================"
	echo
	echo "Binaries installed to: $INSTALL_DIR"
	echo "  - hops"
	echo "  - hopsd"
	echo "  - hops-create-rootfs"
	echo
	echo "Configuration directory: $HOPS_DIR"
	echo
	echo "Next steps:"
	echo "  1. Start the daemon:    hops system start"
	echo "  2. Run a command:       hops run /tmp -- /bin/echo 'Hello Hops!'"
	echo "  3. Check status:        hops system status"
	echo "  4. List profiles:       hops profile list"
	echo
	echo "For help: hops --help"
	echo
}

main() {
	check_macos_version
	check_architecture
	check_swift

	build_project
	codesign_hopsd
	install_binaries
	create_directory_structure
	download_runtime_files
	setup_alpine_rootfs
	copy_example_profiles

	print_summary
}

main "$@"
