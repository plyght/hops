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
- **Desktop GUI**: Iced-based Rust application for visual profile management and run history

## Quick Start

### 1. Build and Install

```bash
git clone https://github.com/plyght/hops.git
cd hops
./build-and-sign.sh
sudo cp .build/debug/hops /usr/local/bin/
sudo cp .build/debug/hopsd /usr/local/bin/
```

### 2. Download Runtime Files

```bash
cd ~/.hops
wget https://github.com/apple/container/releases/latest/download/vmlinux
wget https://github.com/apple/container/releases/latest/download/init.block
mv init.block initfs
wget https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/aarch64/alpine-minirootfs-3.19.1-aarch64.tar.gz
```

### 3. Create Alpine Rootfs

```bash
.build/debug/hops-create-rootfs
```

### 4. Start Daemon

```bash
.build/debug/hopsd > /tmp/hopsd.log 2>&1 &
```

### 5. Run a Command

```bash
.build/debug/hops run /tmp -- /bin/echo "Hello from Hops!"
```

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
# Run a command in sandbox
hops run /tmp -- /bin/echo "Hello"

# Run shell commands
hops run /tmp -- /bin/sh -c "uname -a"

# With resource limits
hops run --cpus 2 --memory 512M /tmp -- /bin/ls

# With network access
hops run --network outbound /tmp -- /bin/wget example.com

# Check daemon status
hops system status

# Stop daemon
hops system stop
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
# Build
swift build
./build-and-sign.sh

# Run tests
swift test

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
- Per-container filesystem isolation
- gRPC CLI-daemon communication
- Rust GUI with live daemon integration

Known Limitations:
- No interactive TTY support
- Single Alpine rootfs (all containers use same base image)
- Manual container cleanup required
- Network capabilities untested

## Documentation

- [docs/setup.md](docs/setup.md) - Detailed installation and configuration
- [config/README.md](config/README.md) - Policy configuration reference
- [launchd/README.md](launchd/README.md) - Daemon management
- [docs/testing.md](docs/testing.md) - Test coverage report

## License

MIT License
