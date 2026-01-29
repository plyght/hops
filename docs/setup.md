# Hops Setup Guide

Complete installation and configuration guide for Hops sandboxing system.

## Prerequisites

- macOS 14+ (Sonoma or later)
- Apple Silicon (M1/M2/M3)
- Xcode Command Line Tools
- Swift 5.9+
- Root access for system-level installation

## Installation

### 1. Build from Source

```bash
git clone https://github.com/plyght/hops.git
cd hops
swift build -c release
```

### 2. Install Binaries

```bash
sudo cp .build/release/hops /usr/local/bin/
sudo cp .build/release/hopsd /usr/local/bin/
sudo chmod +x /usr/local/bin/hops
sudo chmod +x /usr/local/bin/hopsd
```

### 3. Create System Directories

```bash
sudo mkdir -p /var/run/hops
sudo mkdir -p /usr/local/var/log/hops
sudo mkdir -p /usr/local/etc/hops/profiles
sudo chown -R $USER /var/run/hops
sudo chown -R $USER /usr/local/var/log/hops
sudo chown -R $USER /usr/local/etc/hops
```

### 4. Install Launch Daemon

```bash
sudo cp launchd/com.hops.daemon.plist /Library/LaunchDaemons/
sudo chown root:wheel /Library/LaunchDaemons/com.hops.daemon.plist
sudo chmod 644 /Library/LaunchDaemons/com.hops.daemon.plist
```

### 5. Load Launch Daemon

```bash
sudo launchctl load /Library/LaunchDaemons/com.hops.daemon.plist
sudo launchctl start com.hops.daemon
```

Verify the daemon is running:
```bash
ps aux | grep hopsd
ls -la /var/run/hops/hops.sock
```

## Configuration

### Profile Setup

Hops uses TOML configuration files called profiles. Profiles define sandbox capabilities, resource limits, and mount configurations.

#### Copy Example Profiles

```bash
cp config/examples/*.toml /usr/local/etc/hops/profiles/
```

Available profiles:
- `minimal.toml` - Absolute minimum permissions
- `untrusted.toml` - Maximum security for untrusted code
- `development.toml` - Development environment with loopback networking
- `network-allowed.toml` - Outbound network access
- `build.toml` - Build environment with package downloads
- `ci.toml` - CI/CD environment

#### Create Custom Profile

Create a new profile at `/usr/local/etc/hops/profiles/custom.toml`:

```toml
name = "custom"
version = "1.0.0"
description = "Custom sandbox profile"

[capabilities]
network = "disabled"
filesystem = ["read", "execute"]
allowed_paths = ["/usr/lib", "/System/Library"]
denied_paths = ["/etc/shadow"]

[capabilities.resource_limits]
cpus = 2
memory_bytes = 536870912
max_processes = 100

[sandbox]
root_path = "/"
working_directory = "/"

[[sandbox.mounts]]
source = "/usr"
destination = "/usr"
type = "bind"
mode = "ro"
```

### Profile Format Reference

#### Network Capabilities
- `disabled` - No network access (default)
- `loopback` - Loopback interface only (127.0.0.1)
- `outbound` - Outbound connections allowed
- `full` - Full network access

#### Filesystem Capabilities
Array of: `read`, `write`, `execute`

#### Paths
- `allowed_paths` - Explicitly allowed filesystem paths
- `denied_paths` - Explicitly denied filesystem paths (takes precedence)

#### Resource Limits
- `cpus` - Maximum CPU cores
- `memory_bytes` - Maximum memory in bytes
- `max_processes` - Maximum number of processes

#### Mount Types
- `bind` - Bind mount from host
- `tmpfs` - Temporary filesystem in memory
- `overlay` - Overlay filesystem

#### Mount Modes
- `ro` - Read-only
- `rw` - Read-write

## Kernel Configuration (Required for Apple Containerization)

Apple's Containerization framework requires kernel extensions and initfs configuration.

### 1. Enable System Integrity Protection (SIP) Modifications

**WARNING**: This reduces system security. Only proceed if you understand the implications.

Reboot into Recovery Mode (hold Power button → Options → Recovery):

```bash
csrutil enable --without kext
```

Reboot normally.

### 2. Verify Containerization Framework

```bash
ls /System/Library/PrivateFrameworks/Containerization.framework
```

If not present, your macOS version may not support Containerization.

### 3. Grant Full Disk Access

System Settings → Privacy & Security → Full Disk Access → Add:
- `/usr/local/bin/hopsd`
- `/usr/local/bin/hops`

## Usage Examples

### Basic Usage

```bash
hops run /path/to/project -- python script.py
```

### With Profile

```bash
hops run --profile build /path/to/project -- cargo build
```

### With Custom Resources

```bash
hops run --cpus 4 --memory 2G /path/to/project -- npm test
```

### Interactive Shell

```bash
hops run --profile development /path/to/project -- /bin/bash
```

## Troubleshooting

### Daemon Won't Start

Check logs:
```bash
tail -f /usr/local/var/log/hops/hopsd.log
tail -f /usr/local/var/log/hops/hopsd.error.log
```

Verify socket permissions:
```bash
ls -la /var/run/hops/
```

Reload daemon:
```bash
sudo launchctl unload /Library/LaunchDaemons/com.hops.daemon.plist
sudo launchctl load /Library/LaunchDaemons/com.hops.daemon.plist
```

### Socket Connection Failed

Ensure daemon is running:
```bash
ps aux | grep hopsd
```

Check socket exists:
```bash
ls -la /var/run/hops/hops.sock
```

Verify socket path matches daemon configuration:
```bash
hopsd --socket /var/run/hops/hops.sock
```

### Permission Denied Errors

Grant Full Disk Access (see Kernel Configuration section).

Verify directory ownership:
```bash
ls -la /var/run/hops
ls -la /usr/local/var/log/hops
```

### Containerization Framework Not Available

Verify macOS version:
```bash
sw_vers
```

Requires macOS 14+ on Apple Silicon.

Check framework:
```bash
ls -la /System/Library/PrivateFrameworks/Containerization.framework
```

### Profile Not Found

List available profiles:
```bash
hops profile list
```

Verify profile path:
```bash
ls -la /usr/local/etc/hops/profiles/
```

Check profile syntax:
```bash
hops profile validate /usr/local/etc/hops/profiles/custom.toml
```

### Resource Limits Not Enforced

Verify profile has resource_limits section:
```toml
[capabilities.resource_limits]
cpus = 2
memory_bytes = 536870912
max_processes = 100
```

Check daemon logs for validation errors.

### Network Access Not Working

Verify network capability:
```toml
[capabilities]
network = "outbound"
```

Check DNS resolution mounts:
```toml
[[sandbox.mounts]]
source = "/etc/resolv.conf"
destination = "/etc/resolv.conf"
type = "bind"
mode = "ro"
```

Verify SSL certificate access:
```toml
[[sandbox.mounts]]
source = "/etc/ssl"
destination = "/etc/ssl"
type = "bind"
mode = "ro"
```

## Uninstallation

```bash
sudo launchctl unload /Library/LaunchDaemons/com.hops.daemon.plist
sudo rm /Library/LaunchDaemons/com.hops.daemon.plist
sudo rm /usr/local/bin/hops
sudo rm /usr/local/bin/hopsd
sudo rm -rf /var/run/hops
sudo rm -rf /usr/local/var/log/hops
sudo rm -rf /usr/local/etc/hops
```

## Security Considerations

- Always use the most restrictive profile that meets your needs
- Review allowed_paths and denied_paths carefully
- Minimize network capabilities
- Set appropriate resource limits to prevent DoS
- Regularly audit sandbox configurations
- Never run untrusted code with `network = "full"` or unrestricted filesystem access
- Keep denied_paths updated with sensitive system files
- Use tmpfs mounts for temporary data to prevent persistence

## Advanced Configuration

### Multiple Sandboxes

Run multiple isolated sandboxes simultaneously:

```bash
hops run --profile untrusted /path/to/untrusted -- python malware.py &
hops run --profile build /path/to/project -- cargo build &
```

### Custom Mount Overlays

Create overlay filesystem for copy-on-write:

```toml
[[sandbox.mounts]]
source = "/usr/local"
destination = "/usr/local"
type = "overlay"
mode = "rw"
options = ["lowerdir=/usr/local", "upperdir=/tmp/overlay-upper", "workdir=/tmp/overlay-work"]
```

### Environment Variable Injection

```toml
[sandbox.environment]
PATH = "/usr/local/bin:/usr/bin:/bin"
RUST_BACKTRACE = "1"
CARGO_HOME = "/tmp/cargo"
```

### Hostname Isolation

```toml
[sandbox]
hostname = "isolated-sandbox"
```

## Performance Tuning

### Memory Limits

Set appropriate memory_bytes based on workload:
- Light scripts: 134217728 (128 MB)
- Standard processes: 536870912 (512 MB)
- Build processes: 4294967296 (4 GB)
- Heavy compilation: 8589934592 (8 GB)

### CPU Allocation

Balance between isolation and performance:
- Untrusted code: 1-2 cores
- Development: 4-8 cores
- Build processes: 8+ cores

### Process Limits

Prevent fork bombs:
- Untrusted: 5-10 processes
- Standard: 100 processes
- Development: 500 processes
- Build: 512+ processes

## Next Steps

- Read the [Architecture Guide](architecture.md) to understand Hops internals
- Explore [Example Profiles](../config/examples/) for different use cases
- Review [Security Best Practices](security.md) for production deployments
- Contribute to [Hops Development](../CONTRIBUTING.md)
