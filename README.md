# Hops

A capability-first sandboxing system for macOS that provides fine-grained control over process execution, filesystem access, network capabilities, and resource limits.

## Overview

Hops enables secure execution of untrusted or semi-trusted code by enforcing strict capability-based policies. Unlike traditional sandboxing approaches, Hops denies all access by default and requires explicit grants for every capability.

### Key Features

- **Capability-based security**: Deny-all default with explicit grants
- **Fine-grained filesystem control**: Separate read, write, and execute permissions
- **Network isolation**: Disabled, loopback, outbound, or full network access
- **Resource limits**: CPU, memory, and process count constraints
- **gRPC daemon architecture**: Persistent daemon manages sandbox lifecycle
- **Profile-based configuration**: Reusable TOML policies for different use cases

## Architecture

Hops consists of three main components:

1. **hops** (CLI): Command-line interface for running sandboxed processes
2. **hopsd** (Daemon): Background service managing sandbox lifecycle via gRPC
3. **HopsCore**: Swift library implementing policy parsing and enforcement

```
┌─────────┐                  ┌──────────┐                  ┌──────────┐
│  hops   │─── gRPC/Unix ───▶│  hopsd   │─── syscalls ───▶│  Kernel  │
│  (CLI)  │                  │ (Daemon) │                  │ Sandbox  │
└─────────┘                  └──────────┘                  └──────────┘
     │                             │
     └──── Policy (TOML) ──────────┘
```

## Requirements

- macOS 26 or later
- Apple Silicon (arm64)
- Swift 6.0+

## Quick Start

### Installation

```bash
git clone https://github.com/plyght/hops.git
cd hops
swift build -c release
cp .build/release/hops /usr/local/bin/
cp .build/release/hopsd /usr/local/bin/
```

### Start the daemon

```bash
launchctl load ~/Library/LaunchAgents/com.hops.daemon.plist
```

Or manually:

```bash
hopsd --socket ~/.hops/hops.sock
```

### Run a sandboxed process

```bash
hops run --policy config/default.toml -- /usr/bin/curl https://example.com
```

### Use a permissive development profile

```bash
hops run --policy config/examples/development.toml -- npm install
```

### Create a custom policy

```bash
mkdir -p ~/.hops/profiles
cat > ~/.hops/profiles/myapp.toml <<EOF
[sandbox]
root = "./myapp"

[capabilities]
network = "outbound"

[capabilities.filesystem]
read = ["./myapp", "/usr/lib"]
write = ["./myapp/data"]
execute = ["./myapp/bin"]

[resources]
cpus = 4
memory = "2G"
max_processes = 100
EOF

hops run --policy ~/.hops/profiles/myapp.toml -- ./myapp/bin/server
```

## Policy Configuration

Policies are defined in TOML format with three main sections:

### Sandbox

```toml
[sandbox]
root = "."  # Root directory for the sandboxed process
```

### Capabilities

```toml
[capabilities]
network = "disabled"  # disabled | outbound | loopback | full

[capabilities.filesystem]
read = [".", "/usr/lib"]
write = ["./output"]
execute = [".", "/usr/bin"]
```

### Resources

```toml
[resources]
cpus = 2
memory = "512M"
max_processes = 100
```

## Example Profiles

Hops includes several pre-configured profiles in `config/examples/`:

- **default.toml**: Deny-all baseline (no network, minimal filesystem)
- **development.toml**: Permissive for local development (loopback network, full toolchain access)
- **untrusted.toml**: Maximum restriction for untrusted code
- **network-allowed.toml**: Outbound network with project-scoped filesystem

## CLI Usage

```bash
hops run [OPTIONS] -- COMMAND [ARGS...]
  --policy PATH       Policy file to use (default: config/default.toml)
  
hops stop SANDBOX_ID
  Stop a running sandbox

hops list
  List all running sandboxes

hops status SANDBOX_ID
  Get detailed status of a sandbox
```

## Development

### Build

```bash
swift build
```

### Test

```bash
swift test
```

### Generate gRPC code

```bash
protoc --swift_out=. --grpc-swift_out=. proto/hops.proto
```

## License

MIT

## Contributing

Contributions are welcome. Please ensure all tests pass before submitting a pull request.
