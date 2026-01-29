# Interactive Shell Prompt Fix

## Problem
When running `.build/debug/hops run /tmp -- /bin/sh`, users saw a blank screen with no prompt. The shell started but didn't show the standard prompt (`$ ` or `# `) like SSH does.

## Root Causes
1. Shell was not running in interactive mode (missing `-i` flag)
2. PS1 environment variable was not set
3. TERM environment variable was not set

## Solution

### 1. Auto-detect Shells and Add `-i` Flag
**File**: `Sources/hopsd/CapabilityEnforcer.swift`

Added `processCommand()` function that:
- Detects shell commands (`/bin/sh`, `/bin/bash`, `/bin/ash`, `/bin/dash`, `/bin/zsh`)
- When `allocateTty=true` and command is a shell, automatically adds `-i` flag
- Only adds `-i` if it's not already specified (avoids double `-i`)
- Preserves existing flags like `-c`

**Example transformations:**
- `/bin/sh` → `/bin/sh -i`
- `/bin/bash` → `/bin/bash -i`  
- `/bin/sh -c "echo hello"` → unchanged (already has `-c`)

### 2. Set PS1 Environment Variable
**Files**: 
- `Sources/hopsd/CapabilityEnforcer.swift`
- `Sources/HopsCore/Policy.swift`

Added PS1 to environment:
- Default PS1: `\w $ ` (shows current directory + `$ `)
- Only added when `allocateTty=true` and not already set
- Included in default Policy environment

### 3. Set TERM Environment Variable
**Files**:
- `Sources/hopsd/CapabilityEnforcer.swift`
- `Sources/HopsCore/Policy.swift`

Added TERM to environment:
- Default TERM: `xterm-256color`
- Required for proper terminal behavior
- Enables color support and terminal features

## Code Changes

### CapabilityEnforcer.swift
```swift
// Added processCommand() to inject -i flag for shells
private static func processCommand(command: [String], allocateTty: Bool) -> [String] {
  guard allocateTty, !command.isEmpty else {
    return command
  }
  
  let firstArg = command[0]
  let isShell = firstArg.hasSuffix("/sh") || 
                firstArg.hasSuffix("/bash") || 
                firstArg.hasSuffix("/ash") ||
                firstArg.hasSuffix("/dash") ||
                firstArg.hasSuffix("/zsh")
  
  guard isShell else {
    return command
  }
  
  if command.count == 1 {
    return [firstArg, "-i"]
  }
  
  if command.count > 1 && (command[1] == "-c" || command[1].hasPrefix("-")) {
    return command
  }
  
  return [firstArg, "-i"] + command.dropFirst()
}

// Modified configure() to add PS1 and TERM
var environmentVars = sandbox.environment
if allocateTty {
  if !environmentVars.keys.contains("PS1") {
    environmentVars["PS1"] = "\\w $ "
  }
  if !environmentVars.keys.contains("TERM") {
    environmentVars["TERM"] = "xterm-256color"
  }
}
```

### Policy.swift
```swift
// Updated default environment
environment: [
  "PATH": "/usr/bin:/bin",
  "HOME": "/root",
  "PS1": "\\w $ ",
  "TERM": "xterm-256color"
]
```

## Expected Behavior After Fix

### Interactive Shell
```bash
$ .build/debug/hops run /tmp -- /bin/sh
/ $ ls
bin   dev   etc   home  lib   ...
/ $ pwd
/
/ $ echo hello
hello
/ $ exit
$
```

### With Commands
```bash
$ .build/debug/hops run /tmp -- /bin/sh -c "echo hello"
hello
$
```

### Non-Interactive (Piped Input)
```bash
$ echo "ls" | .build/debug/hops run --no-interactive /tmp -- /bin/sh
bin
dev
etc
...
$
```

## Testing

### Manual Test
```bash
./build-and-sign.sh
pkill -9 hopsd
.build/debug/hopsd > /tmp/hopsd.log 2>&1 &
sleep 2
.build/debug/hops run /tmp -- /bin/sh
```

**Expected**: Prompt appears immediately, can type commands, see output in real-time

### Automated Test
```bash
./test-interactive.sh
```

## Notes

1. The `-i` flag is only added when `allocateTty=true`, which happens when:
   - User runs from a terminal (stdin is a TTY)
   - User explicitly sets `--interactive` flag

2. When input is piped (e.g., `echo "ls" | hops run`), `allocateTty=false` and no prompt appears (correct behavior)

3. The PS1 format `\w $ ` shows:
   - `\w` = current working directory
   - `$ ` = dollar sign followed by space

4. Users can override PS1 in their profile TOML files

## Related Files
- `Sources/hops/Commands/RunCommand.swift` - CLI entry point, determines allocateTty
- `Sources/hopsd/CapabilityEnforcer.swift` - Processes command and environment
- `Sources/HopsCore/Policy.swift` - Default environment configuration
