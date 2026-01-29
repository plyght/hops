# Hops Quick Start

Get Hops running in 5 minutes.

## Prerequisites

- macOS 26 (Sequoia) or later
- Apple Silicon (M1/M2/M3/M4)
- Swift 6.0+

## Installation

### 1. Clone and Build

```bash
git clone https://github.com/plyght/hops.git
cd hops
./build-and-sign.sh
```

### 2. Install Runtime Files

Download kernel, init filesystem, and Alpine tarball:

```bash
mkdir -p ~/.hops
cd ~/.hops

wget https://github.com/apple/container/releases/latest/download/vmlinux
wget https://github.com/apple/container/releases/latest/download/init.block
mv init.block initfs

wget https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/aarch64/alpine-minirootfs-3.19.1-aarch64.tar.gz
mv alpine-minirootfs-3.19.1-aarch64.tar.gz alpine-minirootfs.tar.gz

chmod 644 vmlinux initfs
```

### 3. Create Alpine Rootfs

```bash
cd ~/hops
.build/debug/hops-create-rootfs
```

Expected output:
```
Creating ext4 rootfs from Alpine tarball...
  Source: /Users/username/.hops/alpine-minirootfs.tar.gz
  Output: /Users/username/.hops/alpine-rootfs.ext4
Successfully created Alpine rootfs!
   Size: 512.0 MB
   Path: /Users/username/.hops/alpine-rootfs.ext4
```

### 4. Start Daemon

```bash
.build/debug/hopsd > /tmp/hopsd.log 2>&1 &
```

Verify daemon is running:

```bash
.build/debug/hops system status
```

Expected output:
```
Hops daemon: running

  Uptime: 5s
  Started: Jan 29, 2026 at 12:00:00 PM
  Active sandboxes: 0
```

## Usage

### Run a Command

```bash
.build/debug/hops run /tmp -- /bin/echo "Hello from Hops!"
```

Output:
```
Hello from Hops!
```

### Run Shell Commands

```bash
.build/debug/hops run /tmp -- /bin/sh -c "uname -a"
```

Output:
```
Linux grpc-policy 6.12.28 #1 SMP aarch64 Linux
```

### List Available Commands

```bash
.build/debug/hops run /tmp -- /bin/ls /bin/
```

### With Resource Limits

```bash
.build/debug/hops run --cpus 2 --memory 512M /tmp -- /bin/sh
```

### With Network Access

```bash
.build/debug/hops run --network outbound /tmp -- /bin/wget example.com
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

## Troubleshooting

### Daemon won't start

Check logs:
```bash
tail -f /tmp/hopsd.log
```

Common issues:
- Missing vmlinux/initfs → Check `~/.hops/`
- Missing entitlements → Run `./build-and-sign.sh`
- Port in use → `pkill -9 hopsd` first

### Container execution fails

Check if Alpine rootfs exists:
```bash
ls -lh ~/.hops/alpine-rootfs.ext4
```

If missing, run:
```bash
.build/debug/hops-create-rootfs
```

### "failed to find target executable"

Binary doesn't exist in Alpine rootfs. Use absolute paths like `/bin/echo` instead of `echo`.

Check available commands:
```bash
.build/debug/hops run /tmp -- /bin/ls /bin/
```

## Next Steps

- Install system-wide: See [docs/setup.md](setup.md)
- Configure launchd: See [launchd/README.md](../launchd/README.md)
- Create custom profiles: See [config/README.md](../config/README.md)
- Build GUI: `cd hops-gui && cargo build --release`

## Performance

- Container startup: <1 second (VM already running)
- Command execution: ~1 second total
- Memory per container: 512MB default
- Disk per container: ~80MB (sparse files, 512MB allocated)
