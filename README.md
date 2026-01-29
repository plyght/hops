<p align="center">
  <img src="public/images/hops.png" alt="Hops" width="140" />
</p>

# Hops

Lightweight sandboxing for untrusted code on macOS. Hops provides process isolation with fine-grained capability control, letting you run untrusted code safely with filesystem, network, and resource restrictions.

## Overview

Hops isolates processes in controlled sandbox environments using [Apple's Containerization framework](https://github.com/apple/containerization) (v0.23.2). A background daemon manages sandbox lifecycle via gRPC while the CLI provides a clean interface for running commands and managing profiles. An optional Rust GUI offers visual profile management.

## Requirements

- **macOS 26** (Sequoia) or later
- **Apple Silicon** (M1/M2/M3/M4)
- **Swift 6.0+**
- **Rust 1.75+** (for GUI only)

> **Note**: The Containerization framework requires a Linux kernel image and init filesystem. See [docs/setup.md](docs/setup.md) for details.

## Features

- **Fine-Grained Capabilities**: Control network access (disabled, outbound, loopback, full), filesystem permissions, and process limits per sandbox
- **Policy-Based Configuration**: Define reusable security profiles in TOML with explicit allow/deny path lists
- **Resource Limits**: Constrain CPU cores, memory allocation, and maximum process count
- **Daemon Architecture**: Background service manages sandbox lifecycle with gRPC over Unix socket
- **Profile System**: Create, share, and reuse sandbox configurations across projects
- **Secure Defaults**: Network disabled, minimal filesystem access, symlink attack prevention
- **Desktop GUI**: Iced-based Rust application for visual profile management and run history

## Installation

### CLI & Daemon

```bash
git clone https://github.com/plyght/hops.git
cd hops
swift build -c release
sudo cp .build/release/hops /usr/local/bin/
sudo cp .build/release/hopsd /usr/local/bin/
```

### Daemon Setup (launchd)

```bash
# System-wide (requires root)
sudo ./launchd/install.sh

# Or user-level (no root)
./launchd/install-user.sh
```

See [launchd/README.md](launchd/README.md) for manual setup and troubleshooting.

### GUI (Optional)

```bash
cd hops-gui
cargo build --release
cp target/release/hops-gui /usr/local/bin/
```

## Usage

### CLI

```bash
# Start the daemon
hops system start

# Run a command in a sandbox
hops run ./project -- python script.py

# Run with a named profile
hops run --profile untrusted ./code -- bun test

# Run with inline resource limits
hops run --network disabled --memory 512M --cpus 2 ./project -- cargo build

# Manage profiles
hops profile list
hops profile create restrictive --template restrictive
hops profile show default
```

### GUI

```bash
hops-gui
```

The GUI provides:
- Visual profile editor with capability toggles
- Profile list with summary cards
- Run history with filtering and statistics
- One-click profile duplication and deletion

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
# Build everything
swift build
cd hops-gui && cargo build

# Run tests
swift test
cd hops-gui && cargo test

# Regenerate gRPC stubs (after modifying proto/hops.proto)
swift build --product protoc-gen-grpc-swift
protoc \
  --swift_out=Visibility=Public:Sources/HopsProto \
  --grpc-swift_out=Visibility=Public,Server=true,Client=true:Sources/HopsProto \
  --plugin=protoc-gen-grpc-swift=.build/debug/protoc-gen-grpc-swift \
  -I proto proto/hops.proto
```

### Dependencies

**Swift**:
- [swift-argument-parser](https://github.com/apple/swift-argument-parser) - CLI parsing
- [TOMLKit](https://github.com/LebJe/TOMLKit) - TOML configuration parsing
- [grpc-swift](https://github.com/grpc/grpc-swift) - gRPC communication
- [swift-nio](https://github.com/apple/swift-nio) - Async networking
- [Containerization](https://github.com/apple/containerization) - Apple's sandbox framework

**Rust**:
- [iced](https://github.com/iced-rs/iced) - Cross-platform GUI
- [serde](https://github.com/serde-rs/serde) - Serialization
- [toml](https://github.com/toml-rs/toml) - TOML parsing

## Documentation

- [docs/setup.md](docs/setup.md) - Detailed setup guide including kernel/initfs
- [config/README.md](config/README.md) - Policy configuration reference
- [launchd/README.md](launchd/README.md) - Daemon installation options

## License

MIT License
