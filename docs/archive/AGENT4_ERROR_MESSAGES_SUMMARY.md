# Agent 4: Error Messages - Implementation Summary

## Overview
Improved error messages throughout the Hops system to be helpful, actionable, and guide users to solutions.

## Files Created

### 1. `Sources/HopsCore/ErrorMessages.swift`
Centralized error message formatting with helpers for common scenarios:
- `daemonNotRunning()` - Clear instructions to start daemon
- `daemonConnectionFailed()` - Detailed connection troubleshooting
- `missingRuntimeFiles()` - Guide to download required files
- `permissionDenied()` - Specific chmod/chown commands to fix
- `invalidPolicyFile()` - Show minimal valid policy example
- `invalidPathInPolicy()` - Security requirements explained
- `networkCapabilityRequired()` - Network options with examples
- `resourceLimitExceeded()` - How to adjust limits
- `profileNotFound()` - List searched paths, suggest creating
- `commandFailed()` - Debug suggestions for failed commands
- `daemonStartupFailed()` - Logs location and troubleshooting
- `binaryNotFound()` - Expected locations and install instructions
- `firstTimeWelcome()` - Welcome message for new users
- `missingCommand()` - Usage examples
- `doctorCheckFailed/Passed()` - Health check formatting
- `formatInColor()` - Terminal color support helper

### 2. `Sources/hops/Commands/DoctorCommand.swift`
New `hops doctor` command for system diagnostics:
- Checks daemon status (PID file, process running, socket exists)
- Validates runtime files (vmlinux, initfs, alpine-rootfs.ext4)
- Verifies permissions on ~/.hops directory
- Lists available profiles
- Locates hops and hopsd binaries
- Color-coded output (green ✓, red ✗, yellow !)
- Suggests specific fixes for each issue
- Verbose mode for detailed paths

## Files Modified

### 3. `Sources/hops/Hops.swift`
- Added DoctorCommand to subcommands list

### 4. `Sources/hops/Commands/RunCommand.swift`
**DaemonClient Connection:**
- Check socket exists before connecting
- Improved error messages for connection failures
- Added `DaemonClientError.connectionFailed` with helpful message

**Error Handling:**
- `validate()` - Use ErrorMessages.missingCommand()
- `loadPolicy()` - Use ErrorMessages.profileNotFound() with searched paths
- Better context in all error messages

### 5. `Sources/hops/Commands/SystemCommand.swift`
**First-Time User Experience:**
- Detect first run (check for .first_run marker)
- Show welcome message on first daemon start
- Suggest next steps after successful start

**Improved Errors:**
- Daemon startup failure points to logs and suggests fixes
- Binary not found shows warning with fallback to PATH
- Added HopsCore import for ErrorMessages

### 6. `Sources/HopsCore/PolicyParser.swift`
**Better Error Descriptions:**
- `invalidTOML` - Use ErrorMessages.invalidPolicyFile()
- `missingRequiredField` - Show what's missing with example
- `invalidFieldValue` - Explain what's wrong
- `fileNotFound` - Actionable message
- `unreadableFile` - Use ErrorMessages.permissionDenied()

### 7. `Sources/HopsCore/PolicyValidator.swift`
**Improved Validation Errors:**
- All errors now use ErrorMessages helpers
- Security violations clearly explained
- Resource limit errors show how to fix
- Path errors explain security requirements
- Rootfs not found suggests running `hops init`

## Key Improvements

### 1. **Error Structure**
Every error message includes:
- What went wrong (the problem)
- Why it's a problem (context)
- How to fix it (specific commands)

### 2. **Actionable Guidance**
- Specific commands to run (e.g., `hops system start`, `chmod 644 ~/.hops/vmlinux`)
- Examples of correct configuration
- Pointers to documentation
- Suggestions for debugging

### 3. **First-Time User Support**
- Welcome message on first daemon start
- `hops doctor` command for health checks
- Suggestions to run `hops init` when files are missing
- Next steps after successful setup

### 4. **Color-Coded Output**
- Green (✓) for successful checks
- Red (✗) for failures
- Yellow (!) for warnings
- Automatic detection of terminal color support

### 5. **Troubleshooting Helper**
`hops doctor` command provides:
- Comprehensive system health check
- Specific fixes for each issue
- Verbose mode for detailed diagnostics
- Exit code 1 if any check fails

## Example Error Messages

### Before:
```
Error: Policy file not found: untrusted.toml
```

### After:
```
Profile not found: untrusted

Searched in:
  • ~/.hops/profiles
  • ./config/profiles
  • ./config/examples

Available profiles:
  hops profile list

To create a new profile:
  hops profile create untrusted --template restrictive

To use a custom policy file:
  hops run --policy-file path/to/policy.toml /path -- command
```

### Before:
```
Connection refused
```

### After:
```
Daemon is not running

The Hops daemon (hopsd) manages all sandbox operations but is not currently active.

To start the daemon:
  hops system start

To check daemon status:
  hops system status

For troubleshooting:
  hops doctor
```

## Integration with Other Agents

This work complements:
- **Agent 1 (Init)**: Error messages guide users to run `hops init`
- **Agent 2 (Auto-daemon)**: Connection errors work with auto-start feature
- **Agent 3 (Run UX)**: Better feedback when commands fail

## Testing Recommendations

1. **Test daemon connection errors:**
   ```bash
   # Stop daemon and try to run
   hops system stop
   hops run /tmp -- echo "test"  # Should show helpful error
   ```

2. **Test missing files:**
   ```bash
   # Temporarily rename a file
   mv ~/.hops/vmlinux ~/.hops/vmlinux.bak
   hops doctor  # Should detect missing file
   mv ~/.hops/vmlinux.bak ~/.hops/vmlinux
   ```

3. **Test first-time experience:**
   ```bash
   # Remove marker file
   rm ~/.hops/.first_run
   hops system start  # Should show welcome message
   ```

4. **Test invalid policies:**
   ```bash
   # Create invalid policy
   echo "invalid toml" > /tmp/bad.toml
   hops run --policy-file /tmp/bad.toml /tmp -- echo "test"
   ```

5. **Test doctor command:**
   ```bash
   hops doctor          # Full check
   hops doctor --verbose  # With details
   ```

## Future Enhancements

- Add localization support for error messages
- Include error codes for programmatic handling
- Add "Did you mean?" suggestions for typos
- Telemetry opt-in for common error patterns
- Interactive error recovery (e.g., "Would you like me to run `hops init` now?")
