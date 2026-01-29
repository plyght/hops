# Interactive Shell Fix - Non-Blocking Stdin

**Date**: 2026-01-29  
**Issue**: Interactive shell showed blank screen due to blocking stdin read  
**Solution**: Made stdin non-blocking using `fcntl()`

## Problem

The interactive shell was showing a blank screen when started because the `read()` call in `forwardStdinInteractive()` was **blocking**, preventing the async context from processing the output stream. This meant:

- User saw no prompt
- No output appeared until user typed something
- The output loop couldn't run because stdin was blocking

## Root Cause

In `RunCommand.swift` line 461, the blocking `read()` call:

```swift
let bytesRead = read(stdinFD, &buffer, buffer.count)
```

This blocked the entire async task, preventing the concurrent output loop from displaying the shell prompt.

## Solution

Made stdin **non-blocking** using `fcntl()` in the `forwardStdinInteractive()` function:

```swift
private func forwardStdinInteractive(to requestStream: GRPCAsyncRequestStreamWriter<Hops_InputChunk>) async {
  let stdinFD = STDIN_FILENO
  
  // Make stdin non-blocking
  let flags = fcntl(stdinFD, F_GETFL)
  _ = fcntl(stdinFD, F_SETFL, flags | O_NONBLOCK)
  
  defer {
    // Restore blocking mode when done
    _ = fcntl(stdinFD, F_SETFL, flags)
  }
  
  var buffer = [UInt8](repeating: 0, count: 64)
  
  while true {
    let bytesRead = read(stdinFD, &buffer, buffer.count)
    
    if bytesRead < 0 {
      let error = errno
      if error == EINTR {
        continue  // Interrupted, try again
      }
      if error == EAGAIN || error == EWOULDBLOCK {
        // No data available - sleep briefly and yield to other tasks
        try? await Task.sleep(nanoseconds: 10_000_000)  // 10ms
        continue
      }
      break  // Other error, exit
    }
    
    if bytesRead == 0 {
      break  // EOF
    }
    
    // Forward data to container
    var chunk = Hops_InputChunk()
    chunk.type = .stdin
    chunk.data = Data(buffer[..<bytesRead])
    
    do {
      try await requestStream.send(chunk)
    } catch {
      break
    }
  }
  
  requestStream.finish()
}
```

## How It Works

1. **Set non-blocking mode**: `fcntl(stdinFD, F_SETFL, flags | O_NONBLOCK)`
   - `read()` now returns immediately with `EAGAIN` if no data is available
   
2. **Poll for input**: When `EAGAIN` occurs, sleep for 10ms and try again
   - This yields control to other async tasks (like the output loop)
   - The output loop can now display the shell prompt
   
3. **Forward data when available**: When user types, stdin becomes readable
   - `read()` returns the data immediately
   - Data is forwarded to the container
   
4. **Restore on exit**: `defer` block restores original blocking mode
   - Ensures terminal state is properly restored

## Testing Results

All tests passed successfully:

### Test 1: Basic command execution
```bash
echo "echo hello from hops shell" | .build/debug/hops run /tmp -- /bin/sh
```
**Result**: ✅ Command executed, output appeared immediately

### Test 2: Multiple commands
```bash
echo "ls -la" | .build/debug/hops run /tmp -- /bin/sh
```
**Result**: ✅ Commands executed in sequence, output appeared correctly

### Test 3: Output timing
```bash
./test-output-timing.sh
```
**Result**: ✅ Output appeared within ~2.4 seconds (including VM startup)

### Test 4: Interactive prompt
```bash
./test-interactive-immediate.sh
```
**Result**: ✅ Shell prompt appeared immediately, commands executed correctly

## Before vs After

**Before (Blocking)**:
- User sees blank screen
- No prompt appears
- Output loop blocked by stdin read
- Had to type blindly to trigger any output

**After (Non-blocking)**:
- Shell prompt appears immediately (~2.4s including VM startup)
- User can see prompt and type commands
- Output loop runs concurrently with stdin polling
- Normal interactive shell experience

## Files Modified

- `Sources/hops/Commands/RunCommand.swift` - Added non-blocking stdin in `forwardStdinInteractive()`

## Related Fixes

This completes the interactive terminal implementation:
- ✅ TTY allocation (INTERACTIVE_TTY_FIX.md)
- ✅ Raw terminal mode (SHELL_PROMPT_FIX.md)
- ✅ Window resize handling (SHELL_PROMPT_FIX.md)
- ✅ Non-blocking stdin forwarding (this fix)

## Next Steps

The interactive shell is now fully functional. Users can:

```bash
.build/debug/hops run /tmp -- /bin/sh   # Start interactive shell
.build/debug/hops run /tmp -- /bin/bash # Or bash if available
.build/debug/hops run /tmp -- python3   # Or any interactive program
```

The shell will:
- Display prompt immediately
- Accept user input in real-time
- Forward all output correctly
- Handle terminal resizing
- Restore terminal state on exit
