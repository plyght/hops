# Hops - Agent Development Guide

Multi-component macOS 26+ sandboxing system: CLI (hops), daemon (hopsd), GUI (hops-gui), using Apple's Containerization framework.

**Platform**: macOS 26+, Apple Silicon, Swift 6.0+, Rust 1.75+ (GUI only)
**Communication**: gRPC over Unix socket (`~/.hops/hops.sock`)

---

## Build & Test Commands

### Swift
```bash
swift build                                           # Build all (type checks)
swift build -c release                                # Release build
swift build --target hops                             # Specific target
swift test                                            # All tests
swift test --filter PolicyParserTests                 # Test class
swift test --filter PolicyParserTests/testMethod      # Single test
./generate-proto.sh                                   # Regenerate gRPC stubs

# Code Quality (Swift equivalents of cargo fmt/check/clippy)
swift-format lint --recursive Sources/ Tests/         # Check formatting (cargo fmt --check)
swift-format --in-place --recursive Sources/ Tests/  # Format code (cargo fmt)
swift build                                           # Type check only (cargo check)
swiftlint lint Sources/ Tests/                       # Lint code (cargo clippy)
swiftlint autocorrect Sources/ Tests/                # Auto-fix lint issues
```

### Rust (GUI)
```bash
cd hops-gui
cargo build                                           # Debug build
cargo build --release                                 # Release build
cargo test                                            # All tests
cargo test test_name                                  # Specific test
```

---

## Code Style

### Core Philosophy
**Zero-comment code** - No comments, docstrings, headers, or banners. Code must be self-documenting through naming and structure.

### Swift Conventions

**Naming**:
- Types: `PascalCase` (Policy, SandboxManager, NetworkCapability)
- Functions/properties: `camelCase` (parseCapabilities, allowedPaths)
- Enum cases: `camelCase` (.disabled, .readOnly)
- Files: Match primary type (Policy.swift, SandboxManager.swift)
- Tests: `test<Feature><Scenario>` prefix

**Imports** (explicit, ordered):
```swift
import Foundation
import ArgumentParser
import HopsCore
import GRPC
```

**Access Control**:
- Default: internal (no keyword)
- `public` for library APIs
- `private` for implementation details
- `fileprivate` for file-shared code

**Error Handling**:
```swift
enum PolicyParserError: Error {
    case invalidTOML(String)
    case missingRequiredField(String)
}

extension PolicyParserError: LocalizedError {
    var errorDescription: String? { /* user-facing message */ }
}

guard !command.isEmpty else {
    throw ValidationError("No command specified")
}
```

**Concurrency**:
```swift
actor SandboxManager {
    private var containers: [String: LinuxContainer] = [:]
    func runSandbox() async throws -> SandboxStatus { }
}
```

**Protocols**:
```swift
public struct Policy: Codable, Sendable, Equatable { }
```

### Rust Conventions

**Naming**:
- Types: `PascalCase` (Policy, HopsGui)
- Functions/variables: `snake_case` (load_profiles, allowed_paths)
- Constants: `SCREAMING_SNAKE_CASE`
- Modules/files: `snake_case` (grpc_client.rs)

**Imports**:
```rust
use std::collections::HashMap;
use iced::{Element, Task};
use crate::models::Policy;
```

**Error Handling**:
```rust
pub fn load_profiles() -> Result<Vec<Policy>, io::Error> {
    let path = get_profile_dir()?;
    Ok(profiles)
}
```

---

## Testing

### XCTest Structure
```swift
final class PolicyParserTests: XCTestCase {
    var parser: PolicyParser!
    
    override func setUp() {
        parser = PolicyParser()
    }
    
    func testParseValidBasicTOML() throws {
        let policy = try parser.parse(fromString: toml)
        XCTAssertEqual(policy.name, "test")
    }
    
    func testErrorHandling() {
        XCTAssertThrowsError(try parser.parse(invalid)) { error in
            if case PolicyParserError.missingRequiredField(let field) = error {
                XCTAssertEqual(field, "name")
            }
        }
    }
}
```

**Assertions**: `XCTAssertEqual`, `XCTAssertTrue`, `XCTAssertNil`, `XCTAssertThrowsError`
**Fixtures**: `/Tests/Fixtures/*.toml` (valid/invalid examples)

---

## TOML Configuration

Location: `~/.hops/profiles/*.toml`

```toml
name = "example"
version = "1.0.0"

[capabilities]
network = "disabled"                    # disabled, outbound, loopback, full
filesystem = ["read", "write"]
allowed_paths = ["/usr", "/tmp"]
denied_paths = ["/etc/shadow"]

[capabilities.resource_limits]
cpus = 4
memory_bytes = 4294967296
max_processes = 256

[sandbox]
root_path = "/"
hostname = "sandbox"
working_directory = "/"

[[sandbox.mounts]]
source = "/usr"
destination = "/usr"
type = "bind"                          # bind, tmpfs
mode = "ro"                            # ro, rw

[sandbox.environment]
PATH = "/usr/bin:/bin"
```

---

## Security Requirements

### Policy Validation (Security-Critical)
- **All paths must be absolute** - No `../` or `./`
- **Symlinks resolved before validation** - Prevent attacks
- **Sensitive paths protected**: `/etc/shadow`, `/etc/passwd`, `/etc/sudoers`, `/root/.ssh`
- **Read-write access forbidden** to sensitive paths
- **Conflicting mounts rejected** (overlapping destinations)

**Path Canonicalization**:
```swift
let realPath = try FileManager.default.destinationOfSymbolicLink(atPath: path)
```

### macOS Requirements
- **macOS 26+ (Tahoe)** - Containerization framework
- **Apple Silicon required** - M1/M2/M3/M4
- **Kernel & initfs required** in `~/.hops/` (vmlinux, initfs)

### Error Messages
Must include: (1) What went wrong, (2) Why it's a problem, (3) How to fix it

```swift
case .missingKernel(let path):
    return """
    vmlinux not found at \(path)
    
    To install:
    1. Download from: https://github.com/apple/container/releases
    2. Place vmlinux at: \(path)
    3. Set permissions: chmod 644 \(path)
    """
```

---

## Architecture

### gRPC Communication
- **Protocol**: `proto/hops.proto`
- **Transport**: Unix socket at `~/.hops/hops.sock`
- **Pattern**: Client (CLI) → Server (Daemon)

### Daemon Lifecycle
1. Initialize VirtualMachineManager
2. Load kernel/initfs from `~/.hops/`
3. Listen on Unix socket
4. Create LinuxContainer with policy
5. Stream output, handle exit

---

## Common Pitfalls

1. **Never suppress type errors** - No `as any`, `@ts-ignore`, `@ts-expect-error`
2. **Never add comments** - Refactor for clarity
3. **Always validate TOML** - Security-critical
4. **Use actors for mutable state** - Thread safety
5. **Check file existence** before operations
6. **Canonicalize paths** before validation
7. **Use explicit error types** - No generic `Error`

---

## Dependencies

**Swift**: swift-argument-parser, TOMLKit, grpc-swift, swift-nio, swift-log, Containerization (0.23.2)
**Rust**: iced (0.13), tonic, prost, serde, toml

---

## Quick Reference

```bash
# Development
swift build && swift test
swift test --filter PolicyParserTests/testMethod

# Daemon
hops system start/stop/status

# Run sandboxed
hops run ./project -- python script.py
hops run --profile untrusted ./code -- npm test
hops run --network disabled --memory 512M ./project -- cargo build

# Profiles
hops profile list/show/create
```
