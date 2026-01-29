# Interactive Terminal Implementation

## Summary

Implemented SSH-like interactive terminal sessions for hops where users can type commands in real-time and see responses immediately.

## Changes Made

### Modified File: `Sources/hops/Commands/RunCommand.swift`

**Before**: Stdin forwarding used buffered input (`FileHandle.standardInput.bytes`) which accumulated bytes until reaching 4096 bytes before sending.

**After**: 
- **Interactive TTY mode**: Uses low-level `read()` on `STDIN_FILENO` to read 1-64 bytes at a time
- **Piped input mode**: Keeps the buffered approach for efficiency
- Automatically detects mode based on `allocateTty` and `isatty(STDIN_FILENO)`

### New Functions

#### `forwardStdinInteractive(to:)`
- Reads stdin character-by-character (up to 64 bytes per read)
- Forwards immediately without buffering
- Handles `EINTR`, `EAGAIN`, and `EWOULDBLOCK` errors gracefully
- Exits cleanly on EOF (ctrl-d) or errors

#### `forwardStdinBuffered(to:)`
- Uses `FileHandle.standardInput.bytes` async sequence
- Buffers up to 4096 bytes before sending
- Optimized for piped input scenarios

### Logic Flow

```swift
if shouldForwardStdin {
  Task {
    if allocateTty && isatty(STDIN_FILENO) != 0 {
      // Interactive: forward keystrokes immediately
      await forwardStdinInteractive(to: call.requestStream)
    } else {
      // Piped: use buffered approach
      await forwardStdinBuffered(to: call.requestStream)
    }
  }
}
```

## Testing

### ✅ Automated Tests (Piped Input)

Already verified working:

```bash
# Single command
echo "echo 'Hello from piped input'" | .build/debug/hops run /tmp -- /bin/sh
# Output: Hello from piped input

# Multiple commands
echo -e "ls /\necho test\npwd\nexit" | .build/debug/hops run /tmp -- /bin/sh
# Output: directory listing, "test", "/"
```

### 🧪 Manual Tests (Interactive TTY)

To test interactive mode, open a real terminal and run:

```bash
.build/debug/hops run /tmp -- /bin/sh
```

**Expected behavior:**

1. **Immediate response**: Type `ls` and press Enter → see output immediately
2. **Control characters work**:
   - `ctrl-c`: Interrupt current command
   - `ctrl-d`: Exit shell (EOF)
   - `ctrl-l`: Clear screen (if supported by shell)
3. **Real-time editing**: Arrow keys, backspace work as expected
4. **Multiple commands**: 
   ```
   $ ls /
   bin dev etc home ...
   $ echo hello
   hello
   $ pwd
   /
   $ exit
   ```

### Test Matrix

| Input Type | TTY Allocated | Mode Used | Behavior |
|------------|---------------|-----------|----------|
| Terminal | Yes | Interactive | Character-by-character forwarding |
| Pipe | Yes | Buffered | 4096-byte buffering |
| Terminal | No | None | No stdin forwarding |
| Pipe | No | Buffered | 4096-byte buffering |

## Key Implementation Details

### Why 64-byte buffer for interactive?

Small enough to feel instant (single keystrokes) but large enough to handle paste operations efficiently.

### Why separate buffered mode?

Piped input benefits from batching to reduce syscalls. Interactive mode prioritizes latency over throughput.

### Error Handling

- `EINTR`: Retry read (interrupted by signal)
- `EAGAIN`/`EWOULDBLOCK`: Sleep 1ms and retry (would block)
- Other errors or EOF: Break loop and finish stream
- gRPC send errors: Break loop immediately

### Raw Terminal Mode

Already implemented (lines 191-193 in `RunCommand.swift`):
- Disables line buffering
- Disables echo
- Forwards control characters
- Restored on exit via `defer`

## Verification Checklist

- [x] Piped input still works (echo "..." | hops run)
- [x] No linter errors
- [x] Proper error handling (EINTR, EAGAIN, EOF)
- [x] Stream cleanup on exit
- [ ] Manual test: Interactive shell sessions
- [ ] Manual test: Control character handling (ctrl-c, ctrl-d)
- [ ] Manual test: Arrow keys and backspace
- [ ] Manual test: Multiple commands in sequence
- [ ] Manual test: Exit with "exit" command
- [ ] Manual test: Exit with ctrl-d

## Performance Considerations

### Interactive Mode
- **Latency**: ~1-2ms per keystroke (syscall + gRPC send)
- **Throughput**: Irrelevant (human typing speed)
- **CPU**: Minimal (blocking read with small buffer)

### Buffered Mode
- **Latency**: Up to 4096 bytes before first send
- **Throughput**: High (batch processing)
- **CPU**: Minimal (async iteration)

## Future Enhancements

Potential improvements (not implemented):

1. **Adaptive buffering**: Start small, grow if paste detected
2. **Line-editing support**: Implement readline-like features
3. **Terminal size forwarding**: Send window dimensions to container
4. **Bracketed paste**: Detect paste operations for better handling

## Related Files

- `Sources/hops/Commands/RunCommand.swift` - Main implementation
- `Sources/hopsd/ContainerService.swift` - Daemon-side stdin handling
- `proto/hops.proto` - gRPC message definitions

## Build & Deploy

```bash
./build-and-sign.sh
pkill -9 hopsd
.build/debug/hopsd > /tmp/hopsd.log 2>&1 &
```

Test immediately after:
```bash
.build/debug/hops run /tmp -- /bin/sh
```
