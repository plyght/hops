# Agent 2: Automatic Daemon Management Implementation

## Summary

Implemented automatic daemon startup for the `hops run` command to eliminate manual daemon management friction. Users no longer need to run `hops system start` before executing commands.

## Changes Made

### 1. New File: Sources/HopsCore/DaemonManager.swift

Created a shared daemon management module that provides:

**Public API:**
- `isRunning() async -> Bool` - Check if daemon is running via PID file
- `ensureRunning(verbose: Bool = false) async throws` - Start daemon if not running

**Implementation Details:**
- Searches for `hopsd` binary in standard locations:
  - `/usr/local/bin/hopsd`
  - `/usr/bin/hopsd`
  - `~/.local/bin/hopsd`
  - `.build/debug/hopsd`
  - `.build/release/hopsd`
- Launches daemon in background with `--daemon` flag
- Waits up to 5 seconds (20 x 250ms) for daemon to start
- Logs output to `~/.hops/logs/hopsd.log`
- Returns immediately if daemon already running

**Error Handling:**
- `DaemonManagerError.binaryNotFound` - Provides installation instructions
- `DaemonManagerError.startTimeout` - Points to logs and required files
- `DaemonManagerError.notRunning` - Suggests manual start or auto-start

### 2. Modified: Sources/hops/Commands/RunCommand.swift

**Added Flag:**
```swift
@Flag(name: .long, help: "Disable automatic daemon startup")
var noAutoStart: Bool = false
```

**Updated Help Text:**
Added to discussion:
```
The daemon is automatically started if not running. Use --no-auto-start
to disable this behavior and require manual daemon management.
```

**Modified executeViaDaemon():**
```swift
private func executeViaDaemon(...) async throws -> Int32 {
  if !noAutoStart {
    try await ensureDaemonRunning()
  }
  
  let client = try await DaemonClient.connect()
  // ... rest of execution
}
```

**Added Helper Method:**
```swift
private func ensureDaemonRunning() async throws {
  let daemonManager = DaemonManager()
  
  if await daemonManager.isRunning() {
    return
  }
  
  try await daemonManager.ensureRunning(verbose: verbose)
}
```

## User Experience

### Before
```bash
$ hops run echo "hello"
Error: Connection refused (daemon not running)

$ hops system start
Starting Hops daemon...
Hops daemon started successfully.

$ hops run echo "hello"
hello
```

### After
```bash
$ hops run echo "hello"
hello

# Or with verbose output:
$ hops run --verbose echo "hello"
Hops: Starting daemon...
Hops: Daemon started successfully
Hops: Preparing sandbox environment...
hello
```

### Disable Auto-Start
```bash
$ hops run --no-auto-start echo "hello"
Error: Daemon is not running

Start it with: hops system start
Or it will start automatically on next run
```

## Integration with Other Agents

### Agent 1 (Install/Setup)
- DaemonManager searches standard paths including `.build/debug/hopsd`
- Works seamlessly with both development and installed binaries
- Error messages guide users through installation process

### Agent 3 (Run Command UX)
- Auto-start is transparent to simplified UX
- `--no-auto-start` flag available for advanced users
- Verbose mode shows daemon startup for debugging

### Agent 4 (Error Messages)
- DaemonManagerError provides comprehensive error messages
- Points users to logs when startup fails
- Lists required files (vmlinux, initfs, alpine-rootfs.ext4)

## Design Decisions

1. **Shared Module in HopsCore** - DaemonManager is reusable by other commands (profile, system) if needed in future

2. **Non-Interactive by Default** - Daemon starts silently unless `--verbose` is used, avoiding cluttered output

3. **5-Second Timeout** - Balances between fast failure and giving daemon time to initialize

4. **PID File Check** - Uses same mechanism as SystemCommand for consistency

5. **Opt-Out Flag** - Auto-start is default behavior, but `--no-auto-start` allows power users to retain control

## Testing Recommendations

1. **First-Time User Flow:**
   ```bash
   hops run echo "hello"
   ```
   Verify daemon starts automatically

2. **Already Running:**
   ```bash
   hops system start
   hops run echo "hello"
   ```
   Verify no duplicate daemon startup

3. **Timeout Handling:**
   ```bash
   # Temporarily move vmlinux to simulate failure
   mv ~/.hops/vmlinux ~/.hops/vmlinux.bak
   hops run echo "hello"
   # Should see timeout error with helpful message
   mv ~/.hops/vmlinux.bak ~/.hops/vmlinux
   ```

4. **No Auto-Start:**
   ```bash
   hops system stop
   hops run --no-auto-start echo "hello"
   # Should fail with error message
   ```

5. **Verbose Output:**
   ```bash
   hops system stop
   hops run --verbose echo "hello"
   # Should show daemon startup messages
   ```

## Files Modified

- `Sources/HopsCore/DaemonManager.swift` (NEW)
- `Sources/hops/Commands/RunCommand.swift` (MODIFIED)
- `AGENT2_IMPLEMENTATION.md` (NEW - this file)

## Not Modified

- `Package.swift` (DaemonManager automatically included in HopsCore target)
- `Sources/hops/Commands/SystemCommand.swift` (kept separate for explicit control)
- `Sources/hops/Commands/ProfileCommand.swift` (doesn't need daemon access)

## Next Steps for Other Agents

- Agent 3 can assume daemon auto-starts when simplifying run command
- Agent 4 can reference DaemonManagerError messages for consistency
- Agent 1 can ensure install.sh properly signs hopsd for daemon functionality

## Build Instructions

```bash
# Build all targets
swift build

# Sign hopsd (required for virtualization)
codesign -s - --entitlements hopsd.entitlements --force .build/debug/hopsd

# Test the implementation
.build/debug/hops run echo "Auto-start works!"
```
