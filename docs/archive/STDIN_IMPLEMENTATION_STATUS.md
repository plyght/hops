# Stdin Forwarding Implementation Status

## Summary

✅ **COMPLETE** - Stdin forwarding is now fully functional in hops using FileHandle async API and proper gRPC stream iteration.

## What Was Implemented

### 1. GRPCStdinReader (SandboxManager.swift)
- Created `GRPCStdinReader` class that implements `ReaderStream`
- Thread-safe implementation using NSLock
- Provides `write()` and `finish()` methods to feed data to the container's stdin

### 2. SandboxManager Changes
- Added `stdinWriters` dictionary to track stdin writers by sandbox ID
- Modified `runSandboxStreaming()` to create `GRPCStdinReader` for all streaming containers
- Added `getStdinWriter(id:)` method to retrieve stdin writer for a sandbox
- Updated `handleContainerExit()` to clean up stdin writers

### 3. ContainerService Changes
- Modified `runSandboxStreaming()` to spawn a task that reads stdin chunks from gRPC request stream
- Forwards `INPUT_TYPE_STDIN` chunks to the container's stdin writer
- Calls `finish()` on stdin writer when request stream ends

### 4. RunCommand Changes
- Added logic to detect when stdin should be forwarded (piped input or interactive TTY)
- Attempts to read from stdin and send via gRPC `INPUT_TYPE_STDIN` chunks
- Finishes request stream to signal end of input

## Issues Resolved

### 1. ✅ Blocking I/O Problem - FIXED
**Solution**: Replaced blocking `read()` with `FileHandle.standardInput.bytes` async API
- `FileHandle.bytes` provides an `AsyncSequence` that properly handles EOF
- Non-blocking, properly integrates with Swift concurrency
- Automatically detects when stdin closes

### 2. ✅ Timing Issues - FIXED
**Solution**: Used retry loop with small delays to ensure stdin writer is available
- Retry up to 10 times with 10ms delays
- Gives container enough time to initialize stdin writer
- Works reliably in all test cases

### 3. ✅ Bidirectional Streaming - FIXED
**Solution**: Single AsyncIterator for request stream
- Changed from `requestStream.first(where:)` to `makeAsyncIterator()`
- First read gets RUN request, subsequent reads get STDIN chunks
- Avoids "single AsyncIterator" error from NIO

## Testing Results

✅ **All Tests Passing:**
- `echo "hello" | hops run /tmp -- /bin/cat` → outputs "hello"
- `echo -e "ls\nexit" | hops run /tmp -- /bin/sh` → executes ls and exits
- `printf "echo hello\n" | hops run /tmp -- /bin/sh` → outputs "hello"
- Multi-line input with cat → correctly forwards all lines
- 100 lines of input → all lines processed
- 10KB of binary data → correctly counted (10240 bytes)
- Basic container execution without stdin → working
- Container output streaming → working

## Implementation Details

### Key Components:

1. **Client-side (RunCommand.swift)**:
   - Uses `FileHandle.standardInput.bytes` AsyncSequence
   - Buffers bytes up to 4KB before sending chunks
   - Sends remaining buffer when EOF reached
   - Finishes gRPC request stream when stdin closes

2. **Server-side (ContainerService.swift)**:
   - Uses single AsyncIterator for request stream
   - Reads RUN request first, then STDIN chunks
   - Spawns background task to forward stdin to container
   - Retry logic ensures stdin writer is available

3. **Container integration (SandboxManager.swift)**:
   - Creates `GRPCStdinReader` for all streaming containers
   - Thread-safe using NSLock
   - Provides `write()` and `finish()` methods
   - Cleans up stdin writers when containers exit

## Code Locations

- **GRPCStdinReader**: `Sources/hopsd/SandboxManager.swift` (lines 636-658)
- **Client stdin forwarding**: `Sources/hops/Commands/RunCommand.swift` (lines 386-395)
- **Server stdin forwarding**: `Sources/hopsd/ContainerService.swift` (lines 201-217)

## Proto Definition

The `INPUT_TYPE_STDIN` enum value is defined in `proto/hops.proto` line 128.

## Build Status

✅ Code compiles successfully
✅ Daemon starts without errors
✅ All tests passing
✅ **Stdin forwarding fully functional**

## Usage Examples

```bash
# Simple piped input
echo "hello" | hops run /tmp -- /bin/cat

# Multi-line commands
echo -e "ls\nexit" | hops run /tmp -- /bin/sh

# Execute script from stdin
printf "echo 'Hello from stdin'\n" | hops run /tmp -- /bin/sh

# Large data transfer
dd if=/dev/zero bs=1024 count=100 | hops run /tmp -- /usr/bin/wc -c
```
