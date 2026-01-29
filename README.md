<p align="center">
  <img src="public/images/hops.png" alt="Hops" width="140" />
</p>

# Hops

Lightweight sandboxing for untrusted code on macOS. Hops provides process isolation with fine-grained capability control, letting you run untrusted code safely with filesystem, network, and resource restrictions.

## Overview

Hops isolates processes in controlled sandbox environments using [Apple's Containerization framework](https://github.com/apple/containerization) (v0.23.2). A background daemon manages sandbox lifecycle via gRPC while the CLI provides a clean interface for running commands and managing profiles. An optional Rust GUI offers visual profile management.

## Requirements

- **macOS 26 (Sequoia)** or later
- **Apple Silicon** (M1/M2/M3/M4)
- **Swift 6.0+**
- **Rust 1.75+** (GUI only)

### Runtime Prerequisites

Before starting the daemon, you must have:

1. **Linux Kernel**: `~/.hops/vmlinux` (Kata Containers ARM64 kernel, ~14MB)
2. **Init Filesystem**: `~/.hops/initfs` (vminitd init system, ~256MB)
3. **Alpine Rootfs**: `~/.hops/alpine-rootfs.ext4` (Alpine Linux userland, ~512MB)

Download from [Apple Container releases](https://github.com/apple/container/releases) or see [docs/setup.md](docs/setup.md) for detailed installation.

## Features

- **Fine-Grained Capabilities**: Control network access (disabled, outbound, loopback, full), filesystem permissions, and process limits per sandbox
- **Policy-Based Configuration**: Define reusable security profiles in TOML with explicit allow/deny path lists
- **Resource Limits**: Constrain CPU cores, memory allocation, and maximum process count
- **Daemon Architecture**: Background service manages sandbox lifecycle with gRPC over Unix socket
- **Profile System**: Create, share, and reuse sandbox configurations across projects
- **Secure Defaults**: Network disabled, minimal filesystem access, symlink attack prevention
- **Interactive TTY Support**: Run interactive shells with full stdin/stdout/stderr support using `--interactive` or `-it` flag
- **Automatic Daemon Management**: Daemon starts automatically when needed, no manual lifecycle management required
- **Desktop GUI**: Iced-based Rust application for visual profile management and run history

## Quick Start

### Option 1: Automated Installation (Recommended)

```bash
git clone https://github.com/plyght/hops.git
cd hops
make install
```

The installation script will:
- Build the project in release mode
- Code sign hopsd with proper entitlements
- Install binaries to /usr/local/bin
- Create ~/.hops directory structure
- Download runtime files (vmlinux, initfs)
- Create Alpine rootfs image

Then run your first command:

```bash
hops run /tmp -- /bin/echo "Hello from Hops!"
```

The daemon starts automatically when needed. To manage it manually:

```bash
hops system start   # Explicitly start daemon
hops system status  # Check daemon status
hops system stop    # Stop daemon
```

### Option 2: Manual Installation

If you prefer manual control:

```bash
git clone https://github.com/plyght/hops.git
cd hops
make build
sudo cp .build/release/hops /usr/local/bin/
sudo cp .build/release/hopsd /usr/local/bin/
sudo cp .build/release/hops-create-rootfs /usr/local/bin/
hops init
```

### Option 3: Step-by-Step (Legacy)

<details>
<summary>Click to expand manual steps</summary>

#### 1. Build and Install

```bash
git clone https://github.com/plyght/hops.git
cd hops
swift build -c release
codesign -s - --entitlements hopsd.entitlements --force .build/release/hopsd
sudo cp .build/release/hops /usr/local/bin/
sudo cp .build/release/hopsd /usr/local/bin/
sudo cp .build/release/hops-create-rootfs /usr/local/bin/
```

#### 2. Download Runtime Files

```bash
mkdir -p ~/.hops
cd ~/.hops
curl -L -o vmlinux https://github.com/apple/container/releases/latest/download/vmlinux
curl -L -o initfs https://github.com/apple/container/releases/latest/download/init.block
curl -L -o alpine-minirootfs.tar.gz https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/aarch64/alpine-minirootfs-3.19.1-aarch64.tar.gz
```

#### 3. Create Alpine Rootfs

```bash
hops-create-rootfs
```

#### 4. Run a Command

```bash
hops run /tmp -- /bin/echo "Hello from Hops!"
```

</details>

See [docs/setup.md](docs/setup.md) for detailed installation and [launchd/README.md](launchd/README.md) for daemon management.

### GUI (Optional)

```bash
cd hops-gui
cargo build --release
cp target/release/hops-gui /usr/local/bin/
hops-gui
```

## Usage

### Basic Commands

```bash
# Initialize environment (download runtime files)
hops init

# Check environment setup
hops init --check-only

# Verify system health
hops doctor

# Run a command in sandbox (daemon starts automatically)
hops run /tmp -- /bin/echo "Hello"

# Run shell commands
hops run /tmp -- /bin/sh -c "uname -a"

# Interactive shell (SSH-like experience with prompts)
hops run /tmp -- /bin/sh
# You'll see a prompt: / $
# Type commands in real-time and see immediate output
# Exit with ctrl-d or "exit"

# Piped input also works
echo "ls -la" | hops run /tmp -- /bin/sh
echo "hello" | hops run /tmp -- /bin/cat

# Disable interactive mode if needed
hops run --no-interactive /tmp -- /bin/sh

# With resource limits
hops run --cpus 2 --memory 512M /tmp -- /bin/ls

# With network access (NAT with DNS)
hops run --network outbound /tmp -- /bin/ping -c 2 google.com
hops run --network outbound /tmp -- /bin/wget -O- example.com

# Manual daemon management (optional - daemon auto-starts by default)
hops system status        # Check daemon status
hops system start         # Explicitly start daemon
hops system stop          # Stop daemon
hops system restart       # Restart daemon
```

### Profile Management

```bash
# List available profiles
hops profile list

# Run with profile
hops run --profile untrusted /tmp -- /bin/sh

# Create custom profile
hops profile create custom --template restrictive
```

### GUI

```bash
hops-gui
```

Features:
- Visual profile editor
- Real-time sandbox status
- Run history with gRPC integration
- Connection status indicator

## Configuration

Policies are TOML files defining sandbox behavior:

```toml
name = "build"
version = "1.0.0"
description = "Build environment with network access"

[capabilities]
network = "outbound"
filesystem = ["read", "write", "execute"]
allowed_paths = ["/usr", "/lib", "/bin"]
denied_paths = ["/etc/shadow", "/etc/passwd", "/root/.ssh"]

[capabilities.resource_limits]
cpus = 4
memory_bytes = 4294967296
max_processes = 256

[sandbox]
root_path = "/"
hostname = "build-sandbox"
working_directory = "/"

[[sandbox.mounts]]
source = "/usr"
destination = "/usr"
type = "bind"
mode = "ro"

[[sandbox.mounts]]
source = "tmpfs"
destination = "/tmp"
type = "tmpfs"
mode = "rw"
```

Profiles are stored in `~/.hops/profiles/` and selected with `--profile <name>`.

See [config/README.md](config/README.md) for more examples and the full schema.

## Architecture

```
hops (CLI)
  Commands/
    RunCommand.swift       Command execution with gRPC client
    ProfileCommand.swift   Profile CRUD operations
    SystemCommand.swift    Daemon lifecycle control

hopsd (Daemon)
  HopsDaemon.swift         Unix socket server and lifecycle
  SandboxManager.swift     Container orchestration via Containerization.framework
  ContainerService.swift   gRPC service implementation (Hops_HopsServiceAsyncProvider)
  CapabilityEnforcer.swift Policy-to-container translation

HopsCore (Library)
  Policy.swift             Policy and sandbox configuration models
  Capability.swift         Network, filesystem, and resource capability types
  Mount.swift              Mount configuration types
  PolicyParser.swift       TOML parsing with TOMLKit
  PolicyValidator.swift    Security validation (path canonicalization, symlink prevention)

HopsProto (Library)
  hops.pb.swift            Generated protobuf messages
  hops.grpc.swift          Generated gRPC client and server stubs

hops-gui (Rust)
  app.rs                   Iced application state and message handling
  models/                  Policy, Capability, Profile structs (synced with HopsCore)
  views/                   Profile editor, list, and run history views
```

### Communication Flow

```
┌─────────┐     gRPC/Unix Socket     ┌─────────┐     Containerization     ┌───────────┐
│  hops   │ ──────────────────────▶  │  hopsd  │ ──────────────────────▶  │  Sandbox  │
│  (CLI)  │    ~/.hops/hops.sock     │ (Daemon)│      VZVirtualMachine    │  (Linux)  │
└─────────┘                          └─────────┘                          └───────────┘
```

## Development

```bash
# Build with Makefile (recommended)
make build                  # Release build with code signing
make build BUILD_MODE=debug # Debug build

# Or build manually
swift build

# Code signing (required for hopsd to use virtualization)
codesign -s - --entitlements hopsd.entitlements --force .build/debug/hopsd

# Run tests
make test
# Or: swift test

# Clean build artifacts
make clean

# Install locally
make install

# Uninstall
make uninstall

# Regenerate gRPC stubs (after modifying proto/hops.proto)
./generate-proto.sh
```

### Dependencies

**Swift**:
- swift-argument-parser - CLI parsing
- TOMLKit - TOML configuration parsing
- grpc-swift - gRPC communication
- swift-nio - Async networking
- Containerization (0.23.2) - Apple's sandbox framework

**Rust**:
- iced (0.13) - Cross-platform GUI
- tonic (0.12) - gRPC client
- serde - Serialization
- toml - TOML parsing

## Status

**Current Version**: Fully functional end-to-end

Working:
- Daemon lifecycle (start/stop/status)
- Container execution with Alpine Linux userland
- Streaming stdout/stderr with exit code propagation
- Resource limits (CPU, memory, process count)
- Per-container filesystem isolation with writable rootfs copies
- gRPC CLI-daemon communication
- Rust GUI with live daemon integration
- Automatic container cleanup on daemon restart
- Interactive TTY support with shell prompts (SSH-like experience, default behavior)
- Network capabilities (disabled/loopback/outbound/full with NAT and DNS)

Known Limitations:
- None currently identified

## Documentation

- [docs/setup.md](docs/setup.md) - Detailed installation and configuration
- [config/README.md](config/README.md) - Policy configuration reference
- [launchd/README.md](launchd/README.md) - Daemon management
- [docs/testing.md](docs/testing.md) - Test coverage report

## Quick Reference

### Installation
```bash
make install              # Automated installation
make build                # Build only
make uninstall            # Remove binaries
```

### Setup
```bash
hops init                 # Download runtime files
hops init --check-only    # Verify setup
hops doctor               # Diagnose issues
```

### Daemon
```bash
hops system start         # Start daemon
hops system stop          # Stop daemon
hops system status        # Check status
hops system restart       # Restart daemon
```

### Running Commands
```bash
hops run <path> -- <cmd>                    # Basic usage
hops run --network outbound <path> -- <cmd> # With network
hops run --cpus 2 --memory 512M <path> -- <cmd> # Resource limits
hops run --profile untrusted <path> -- <cmd>    # With profile
```

### Profiles
```bash
hops profile list                           # List profiles
hops profile show <name>                    # Show profile
hops profile create <name>                  # Create profile
```

## License

MIT License
