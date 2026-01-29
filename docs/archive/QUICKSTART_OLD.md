# Hops Quick Start Guide

## Prerequisites

- macOS 26 (Sequoia) or later
- Apple Silicon (M1/M2/M3/M4)
- Swift 6.0+
- Boot files already installed at:
  - `~/.hops/vmlinux` (Linux kernel)
  - `~/.hops/initfs` (vminitd init system)

## One-Time Setup

### 1. Build Hops

```bash
cd ~/hops
./build-and-sign.sh
```

This builds `hops` (CLI), `hopsd` (daemon), and signs the daemon with virtualization entitlements.

### 2. Create Alpine Rootfs

```bash
.build/debug/hops-create-rootfs
```

**Output**:
```
Creating ext4 rootfs from Alpine tarball...
  Source: /Users/nicojaffer/.hops/alpine-minirootfs.tar.gz
  Output: /Users/nicojaffer/.hops/alpine-rootfs.ext4
  This may take a minute...
✅ Successfully created Alpine rootfs!
   Size: 512.0 MB
   Path: /Users/nicojaffer/.hops/alpine-rootfs.ext4
```

**Note**: This only needs to be done once. The Alpine rootfs tarball should already exist at `~/.hops/alpine-minirootfs.tar.gz`.

### 3. Start Daemon

```bash
.build/debug/hopsd > /tmp/hopsd.log 2>&1 &
```

Or for foreground logging:
```bash
.build/debug/hopsd
```

## Basic Usage

### Check Daemon Status

```bash
.build/debug/hops system status
```

**Output**:
```
Hops daemon: running

  Uptime: 30s
  Started: Jan 29, 2026 at 12:00:00 PM
  Active sandboxes: 0
```

### Run a Simple Command

```bash
.build/debug/hops run /tmp -- /bin/echo "Hello from Hops!"
```

**Output**:
```
Hello from Hops!
```

### Run Shell Commands

```bash
.build/debug/hops run /tmp -- /bin/sh -c "uname -a"
```

**Output**:
```
Linux grpc-policy 6.12.28 #1 SMP Tue May 20 15:19:05 UTC 2025 aarch64 Linux
```

### List Available Commands in Container

```bash
.build/debug/hops run /tmp -- /bin/ls /bin/
```

**Output** (Alpine uses BusyBox):
```
arch         chgrp        df           ln           nice         stty
ash          chmod        dmesg        login        pidof        su
base64       chown        dnsdomainname ls          ping         sync
busybox      cp           echo         mkdir        ps           tar
cat          date         false        mknod        pwd          touch
...
```

### Run More Complex Commands

```bash
.build/debug/hops run /tmp -- /bin/sh -c "echo 'Files in /etc:' && ls -la /etc/ | head -10"
```

## Command Line Options

### Network Control

```bash
# Disable network (default)
.build/debug/hops run /tmp -- /bin/sh

# Enable outbound network
.build/debug/hops run --network outbound /tmp -- /bin/sh

# Full network access
.build/debug/hops run --network full /tmp -- /bin/sh
```

### Resource Limits

```bash
# Limit to 2 CPUs
.build/debug/hops run --cpus 2 /tmp -- /bin/sh

# Limit to 512MB memory
.build/debug/hops run --memory 512M /tmp -- /bin/sh

# Combine limits
.build/debug/hops run --cpus 2 --memory 512M --network disabled /tmp -- /bin/sh
```

### Using Profiles

```bash
# List available profiles
.build/debug/hops profile list

# Use a specific profile
.build/debug/hops run --profile untrusted /tmp -- /bin/sh
```

### Verbose Output

```bash
.build/debug/hops run --verbose /tmp -- /bin/echo "test"
```

**Output**:
```
Hops: Preparing sandbox environment...
  Root: /tmp
  Command: /bin/echo test
  Network: disabled
test
```

## Stopping the Daemon

```bash
.build/debug/hops system stop
```

Or forcefully:
```bash
pkill -9 hopsd
```

## Troubleshooting

### Daemon won't start

**Check logs**:
```bash
tail -f /tmp/hopsd.log
```

**Common issues**:
- Missing vmlinux/initfs → Check `~/.hops/`
- Missing entitlements → Run `./build-and-sign.sh`
- Port in use → `pkill -9 hopsd` first

### Container execution fails

**Check if Alpine rootfs exists**:
```bash
ls -lh ~/.hops/alpine-rootfs.ext4
```

If missing, run:
```bash
.build/debug/hops-create-rootfs
```

**Check daemon logs**:
```bash
tail -20 /tmp/hopsd.log
```

### "failed to find target executable"

This means the binary doesn't exist in the Alpine rootfs. Use absolute paths like `/bin/echo` instead of `echo`.

**Check what's available**:
```bash
.build/debug/hops run /tmp -- /bin/ls /bin/
```

### Clean up old containers

Containers leave 512MB rootfs copies in `~/.hops/containers/`. To clean up:

```bash
rm -rf ~/.hops/containers/*
```

## Architecture

```
┌─────────────────────────────────────────────────┐
│  macOS Host                                     │
│  ┌───────────────────────────────────────────┐ │
│  │  hops (CLI)                               │ │
│  │  - Sends commands via gRPC                │ │
│  └─────────────┬─────────────────────────────┘ │
│                │ Unix socket                     │
│  ┌─────────────▼─────────────────────────────┐ │
│  │  hopsd (Daemon)                           │ │
│  │  - Manages VMs and containers             │ │
│  │  ┌─────────────────────────────────────┐  │ │
│  │  │  VZVirtualMachineManager            │  │ │
│  │  │  - kernel: vmlinux (14MB)           │  │ │
│  │  │  - initfs: vminitd (256MB)          │  │ │
│  │  │                                     │  │ │
│  │  │  ┌───────────────────────────────┐ │  │ │
│  │  │  │  Linux VM (aarch64)           │ │  │ │
│  │  │  │  - vminitd (PID 1)            │ │  │ │
│  │  │  │                               │ │  │ │
│  │  │  │  ┌─────────────────────────┐  │ │  │ │
│  │  │  │  │  Container              │  │ │  │ │
│  │  │  │  │  - Alpine Linux rootfs  │  │ │  │ │
│  │  │  │  │  - Your command         │  │ │  │ │
│  │  │  │  └─────────────────────────┘  │ │  │ │
│  │  │  └───────────────────────────────┘ │  │ │
│  │  └─────────────────────────────────────┘  │ │
│  └───────────────────────────────────────────┘ │
└─────────────────────────────────────────────────┘
```

## File Locations

- **Binaries**: `.build/debug/hops`, `.build/debug/hopsd`
- **Daemon PID**: `~/.hops/hopsd.pid`
- **gRPC Socket**: `~/.hops/hops.sock`
- **Daemon Logs**: `/tmp/hopsd.log`
- **Boot Files**: `~/.hops/vmlinux`, `~/.hops/initfs`
- **Alpine Rootfs**: `~/.hops/alpine-rootfs.ext4`
- **Container Copies**: `~/.hops/containers/{uuid}/rootfs.ext4`
- **Profiles**: `~/.hops/profiles/*.toml`

## What's Working

✅ Daemon lifecycle (start/stop/status)  
✅ Container execution with real Linux userland  
✅ Streaming stdout/stderr  
✅ Exit code propagation  
✅ Resource limits (CPU, memory)  
✅ Per-container filesystem isolation  
✅ gRPC CLI-daemon communication  
✅ PID tracking  

## What's Not Yet Implemented

❌ Interactive TTY (can't run interactive shells)  
❌ Network testing (disabled by default)  
❌ Multiple rootfs images (all use Alpine)  
❌ Container cleanup (manual deletion required)  
❌ OCI image support (Docker Hub integration)  
❌ Profile loading from TOML files  

## Examples

### Python Script Execution

If you had Python in the rootfs:
```bash
.build/debug/hops run /tmp -- /usr/bin/python3 script.py
```

**Note**: Alpine minimal rootfs doesn't include Python. You'd need to create a custom rootfs with Python installed.

### Multi-Command Pipeline

```bash
.build/debug/hops run /tmp -- /bin/sh -c "ls -la /bin/ | grep echo"
```

### Environment Variables

```bash
.build/debug/hops run /tmp -- /bin/sh -c "echo \$PATH"
```

**Output**:
```
/usr/bin:/bin
```

## Need Help?

- **Documentation**: See `PROGRESS.md` for detailed development history
- **Logs**: Check `/tmp/hopsd.log` for daemon logs
- **Issues**: Daemon logs show container lifecycle events with timestamps
- **Architecture**: See `AGENTS.md` for framework architecture details

## Performance

- **Container startup**: <1 second (VM already running)
- **Command execution**: ~1 second total
- **Memory per container**: 512MB default
- **Disk per container**: ~80MB (sparse files, 512MB allocated)
