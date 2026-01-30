# Hops - Agent Development Guide

Multi-component macOS 26+ sandboxing system: CLI (hops), daemon (hopsd), GUI (hops-gui), using Apple's Containerization framework.

**Platform**: macOS 26+, Apple Silicon, Swift 6.0+, Rust 1.75+ (GUI only)
**Communication**: gRPC over Unix socket (`~/.hops/hops.sock`)

---

## Build & Test Commands

### Swift
```bash
make build                                            # Release build with code signing
make build BUILD_MODE=debug                           # Debug build
make test                                             # All tests
make clean                                            # Clean artifacts

swift build                                           # Debug build (no signing)
swift build -c release --arch arm64                   # Release build ARM64
swift test                                            # All tests
swift test --filter PolicyParserTests                 # Single test class
swift test --filter PolicyParserTests/testMethod      # Single test method

codesign -s - --entitlements hopsd.entitlements \
  --force .build/debug/hopsd                          # Sign hopsd manually
```

### Rust (GUI)
```bash
cd hops-gui
cargo build --release --target aarch64-apple-darwin  # Release build ARM64
cargo test                                            # All tests
cargo test test_name                                  # Single test
```

---

## Code Style

**Zero-comment code** - No comments, docstrings, headers, or banners. Code must be self-documenting through naming and structure.

### Swift
- Naming: Types `PascalCase`, functions/properties `camelCase`, enum cases `camelCase`
- Files match primary type (Policy.swift, SandboxManager.swift)
- Tests: `test<Feature><Scenario>` prefix
- Imports: explicit, ordered (Foundation, ArgumentParser, HopsCore, GRPC)
- Access: Default internal, `public` for library APIs, `private` for implementation
- Errors: Use enum with `LocalizedError` conformance
- Concurrency: Use `actor` for mutable state, `async throws` for async operations

### Rust
- Naming: Types `PascalCase`, functions/variables `snake_case`, constants `SCREAMING_SNAKE_CASE`
- Imports: `use std::collections::HashMap;` then external, then `crate::`
- Error Handling: `Result<T, E>` pattern with `?` operator

---

## Testing

```bash
swift test                                            # All tests
swift test --filter PolicyParserTests                 # Single class
swift test --filter PolicyParserTests/testMethod      # Single test
```

**Assertions**: `XCTAssertEqual`, `XCTAssertTrue`, `XCTAssertNil`, `XCTAssertThrowsError`
**Fixtures**: `/Tests/Fixtures/*.toml` (valid/invalid policy examples)

---

## Security Requirements (Critical)

- All paths must be absolute (no `../` or `./`)
- Symlinks resolved before validation
- Sensitive paths protected: `/etc/shadow`, `/etc/passwd`, `/etc/sudoers`, `/root/.ssh`
- Read-write access forbidden to sensitive paths
- Conflicting mounts rejected
- macOS 26+ (Tahoe) with Apple Silicon (M1/M2/M3/M4)
- Kernel & initfs in `~/.hops/` (vmlinux, initfs)

Error messages must include: (1) What went wrong, (2) Why it's a problem, (3) How to fix it

---

## Common Pitfalls

1. Never suppress type errors
2. Never add comments - refactor for clarity
3. Always validate TOML - security-critical
4. Use actors for mutable state
5. Canonicalize paths before validation

---

## Version Management & Releases

**IMPORTANT**: Version changes must be made in `uncommit.json` at the repository root.

```json
{
  "version": "0.1.0"
}
```

When you bump the version in `uncommit.json` and push to main/master, GitHub Actions automatically:
1. Detects version change
2. Generates AI release notes from code diff
3. Creates git tag and GitHub release
4. Builds Swift CLI binaries (hops, hopsd, hops-create-rootfs) for macOS ARM64
5. Builds Rust GUI and packages as DMG for macOS ARM64

**Never manually create releases or tags.** Always use uncommit.json for version management.

---

## Quick Reference

```bash
make build                         # Release build + code sign
make test                          # All tests
swift test --filter TestClass/test # Single test

hops system start/stop/status      # Daemon control
hops run ./project -- cmd          # Run sandboxed
hops profile list/show/create      # Profile management

# Version bump
vim uncommit.json                  # Edit version
git add uncommit.json && git commit -m "Bump version to X.Y.Z"
git push origin main               # Triggers GitHub Actions release
```
