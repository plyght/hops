<p align="center">
  <img src="public/images/hops.png" alt="Hops" width="140" />
</p>

# Hops

Lightweight sandboxing for untrusted code on macOS. Hops provides process isolation with fine-grained capability control, letting you run untrusted code safely with filesystem, network, and resource restrictions.

## Overview

Hops isolates processes in controlled sandbox environments using Apple's Containerization framework. A background daemon handles sandbox lifecycle while the CLI provides a clean interface for running commands, managing profiles, and controlling the system. Policies define exactly what each sandbox can access.

## Features

- **Fine-Grained Capabilities**: Control network access (disabled, outbound, loopback, full), filesystem permissions, and process limits per sandbox
- **Policy-Based Configuration**: Define reusable security profiles in TOML with explicit allow/deny path lists
- **Resource Limits**: Constrain CPU cores, memory allocation, and maximum process count
- **Daemon Architecture**: Background service manages sandbox lifecycle with gRPC communication
- **Profile System**: Create, share, and reuse sandbox configurations across projects
- **Secure Defaults**: Network disabled, minimal filesystem access, validated mount configurations

## Installation

```bash
# From source
git clone https://github.com/plyght/hops.git
cd hops
swift build -c release
sudo cp .build/release/hops /usr/local/bin/
sudo cp .build/release/hopsd /usr/local/bin/
```

## Usage

```bash
# Start the daemon
hops system start

# Run a command in a sandbox
hops run ./project -- python script.py

# Run with a named profile
hops run --profile untrusted ./code -- npm test

# Run with resource limits
hops run --network disabled --memory 512M --cpus 2 ./project -- cargo build

# Manage profiles
hops profile list
hops profile create restrictive --template restrictive
hops profile show default
```

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
denied_paths = ["/etc/shadow", "/root/.ssh"]

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

## Architecture

```
hops (CLI)
  Commands/
    RunCommand.swift      Command execution with policy loading
    ProfileCommand.swift  Profile CRUD operations
    SystemCommand.swift   Daemon lifecycle control

hopsd (Daemon)
  HopsDaemon.swift        Socket server and lifecycle
  SandboxManager.swift    Container orchestration via Containerization.framework
  ContainerService.swift  gRPC service implementation
  CapabilityEnforcer.swift Policy-to-container translation

HopsCore (Library)
  Policy.swift            Policy and sandbox configuration models
  Capability.swift        Network, filesystem, and resource capability types
  Mount.swift             Mount configuration types
  PolicyParser.swift      TOML parsing
  PolicyValidator.swift   Security validation
```

## Development

```bash
swift build
swift test
```

Requires Swift 5.9+ and macOS 14+. The Containerization framework is only available on macOS with Apple Silicon.

Key dependencies: swift-argument-parser, TOMLKit, grpc-swift, swift-nio.

## License

MIT License
