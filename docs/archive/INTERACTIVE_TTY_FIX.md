# Interactive TTY Implementation - Fix Documentation

## Problem Summary

The previous implementation had **error 13 (gRPC INTERNAL error)** when running commands. This was caused by:

1. **Missing virtualization entitlement**: The `hopsd` daemon was not signed with the `com.apple.security.virtualization` entitlement
2. **Complex stdin forwarding**: The bidirectional stdin streaming implementation using actors was causing daemon crashes

## Root Cause: Error 13

**Error 13** in gRPC context means `INTERNAL` error (not POSIX EACCES).

The actual error message was hidden by the gRPC error wrapping:
```
Invalid virtual machine configuration. The process doesn't have the 
"com.apple.security.virtualization" entitlement.
```

## What Was Fixed

### 1. **Entitlements Issue (Primary Fix)**

**Problem**: Running `swift build` alone does NOT apply entitlements. The daemon needs to be code-signed with the virtualization entitlement.

**Solution**: Always use `./build-and-sign.sh` to build the project. This script:
1. Runs `swift build`
2. Signs `hopsd` with `hopsd.entitlements` file using:
   ```bash
   codesign -s - --entitlements hopsd.entitlements --force .build/debug/hopsd
   ```

**Verification**:
```bash
codesign -d --entitlements - .build/debug/hopsd
```

Should show:
```
[Key] com.apple.security.virtualization
[Value]
    [Bool] true
```

**Note**: Do NOT add extra entitlements like `com.apple.vm.networking` - this caused the daemon to exit immediately with code 0.

### 2. **Interactive Mode Made Default**

**Changes to `RunCommand.swift`**:
- Removed `--interactive` / `-it` flag
- Changed to `--no-interactive` flag using ArgumentParser's `.prefixedNo` inversion
- Interactive mode is now default: `interactive: Bool = true`
- TTY is allocated when: `allocateTty = interactive && isStdinTTY()`

**Behavior**:
- When running from a terminal: TTY is automatically allocated
- When piping input: TTY is NOT allocated (as expected)
- Use `--no-interactive` to explicitly disable TTY allocation

### 3. **Simplified Stdin Implementation**

**Problem**: The previous attempt to implement bidirectional stdin forwarding using:
- `GRPCStdinReader` actor
- `StreamingResult` struct
- Client-side `forwardStdin()` function

This caused the daemon to crash/exit immediately.

**Solution**: Reverted to using `EmptyStdinReader` for now. Interactive TTY support means the container allocates a pseudo-TTY, but stdin is not forwarded from the client. This is sufficient for most use cases where users want proper terminal output formatting.

**Future Work**: Full stdin forwarding would require:
- Non-blocking stdin reading
- Proper gRPC bidirectional streaming
- Careful handling of TTY vs non-TTY input

## Testing

### Build and Run
```bash
# Build with entitlements
./build-and-sign.sh

# Start daemon
.build/debug/hopsd &

# Test basic command
.build/debug/hops run /tmp -- echo "Hello"

# Test with verbose output
.build/debug/hops run --verbose /tmp -- ls -la

# Test with no-interactive flag
.build/debug/hops run --no-interactive /tmp -- ./batch-job.sh
```

### Verification
```bash
# Check daemon status
.build/debug/hops system status

# Verify entitlements
codesign -d --entitlements - .build/debug/hopsd
```

## Summary of Changes

### Files Modified:
1. **hopsd.entitlements** - Reverted to only include `com.apple.security.virtualization`
2. **Sources/hops/Commands/RunCommand.swift** - Interactive mode is now default
3. **Sources/hopsd/SandboxManager.swift** - No changes (kept EmptyStdinReader)
4. **Sources/hopsd/ContainerService.swift** - No changes (kept baseline streaming)
5. **README.md** - Updated to document interactive mode as default

### Key Takeaways:
- ✅ Error 13 fixed by proper code signing
- ✅ Interactive mode is now default
- ✅ Build process requires `./build-and-sign.sh`
- ❌ Full stdin forwarding not implemented (future work)
- ✅ TTY allocation works for proper output formatting

## Build Requirements

**IMPORTANT**: Always use `./build-and-sign.sh` instead of `swift build` directly.

The build script ensures:
1. All targets are compiled
2. `hopsd` is signed with virtualization entitlement
3. The binary can actually create and manage virtual machines

Without proper signing, you'll get:
- "Invalid virtual machine configuration" errors
- Error 13 (INTERNAL) from gRPC
- Daemon unable to create containers
