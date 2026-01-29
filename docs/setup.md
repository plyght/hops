# Hops Setup Guide

Complete installation and configuration guide for Hops sandboxing system.

## Prerequisites

- macOS 26 (Sequoia) or later
- Apple Silicon (M1/M2/M3/M4)
- Xcode Command Line Tools
- Swift 6.0+
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

## Kernel and Initfs Configuration

Apple's Containerization framework requires a Linux kernel image (vmlinux) and an initial filesystem (initfs) to boot lightweight VMs for each container. These files must be present before the daemon can start.

### Overview

The `hopsd` daemon expects to find:
- **Kernel**: `~/.hops/vmlinux` - Linux ARM64 kernel image
- **Initfs**: `~/.hops/initfs` - Initial root filesystem (ext4 block device)

Without these files, the daemon will fail to start with an error message indicating the missing file path.

### Option 1: Download Pre-Built Kernel and Initfs (Recommended)

The Apple Container project provides pre-built kernel and initfs images as release artifacts.

#### Download from Apple Container Releases

1. Visit [Apple Container Releases](https://github.com/apple/container/releases)
2. Download the latest release artifacts:
   - `vmlinux` (Linux kernel for ARM64)
   - `init.block` (initial filesystem)

3. Create Hops directory and install files:

```bash
mkdir -p ~/.hops
mv ~/Downloads/vmlinux ~/.hops/vmlinux
mv ~/Downloads/init.block ~/.hops/initfs
chmod 644 ~/.hops/vmlinux
chmod 644 ~/.hops/initfs
```

4. Verify files are in place:

```bash
ls -lh ~/.hops/vmlinux ~/.hops/initfs
file ~/.hops/vmlinux
file ~/.hops/initfs
```

Expected output:
```
~/.hops/vmlinux: Linux kernel ARM64 boot executable Image
~/.hops/initfs: Linux rev 1.0 ext4 filesystem data
```

### Option 2: Build Kernel and Initfs from Source

If you need custom kernel configuration, you can build from the Apple Containerization framework source.

#### Prerequisites

- **macOS 26+** (Sequoia or later)
- **Xcode Command Line Tools**: `xcode-select --install`
- **Swift 6.0+**: `swift --version`
- **Cross-compilation toolchain**: Downloaded automatically
- **Disk space**: ~5 GB for build artifacts
- **Time**: ~30-45 minutes on Apple Silicon

#### Build Steps

1. Clone the Apple Containerization repository:

```bash
cd ~/src
git clone https://github.com/apple/containerization.git
cd containerization
```

2. Build the kernel (uses kernel/config-arm64 configuration):

```bash
cd kernel
make
```

This will:
- Download the Linux kernel source (if not present)
- Download the ARM64 cross-compilation toolchain
- Build the kernel with the configuration in `config-arm64`
- Output: `vmlinux` in the kernel/ directory

3. Build the initfs filesystem:

```bash
cd ..
make init.block
```

This will:
- Build the `vminitd` init system (Swift-based init daemon)
- Create an ext4 filesystem image containing vminitd and essential binaries
- Output: `bin/init.block`

4. Install to Hops:

```bash
mkdir -p ~/.hops
cp kernel/vmlinux ~/.hops/vmlinux
cp bin/init.block ~/.hops/initfs
chmod 644 ~/.hops/vmlinux
chmod 644 ~/.hops/initfs
```

5. Verify installation:

```bash
ls -lh ~/.hops/vmlinux ~/.hops/initfs
```

Expected sizes:
- `vmlinux`: ~30-50 MB
- `initfs`: ~500 MB (512 MB ext4 block device)

#### Custom Kernel Configuration

To enable additional kernel features (e.g., Landlock LSM):

1. Edit the kernel configuration:

```bash
cd ~/src/containerization/kernel
make menuconfig
```

2. Enable desired features:
   - Security options → Landlock support
   - File systems → Overlay filesystem support
   - Network options → Advanced routing

3. Save configuration:

```bash
make savedefconfig
mv defconfig config-arm64
```

4. Rebuild kernel:

```bash
make clean
make
```

5. Reinstall to Hops:

```bash
cp vmlinux ~/.hops/vmlinux
```

### Verification

After installing the kernel and initfs, verify the daemon can start:

```bash
hopsd --socket ~/.hops/hops.sock
```

Expected output:
```
Sandbox manager initialized
VirtualMachineManager initialized
hopsd listening on unix:///Users/YOUR_USERNAME/.hops/hops.sock
```

If the daemon fails to start:

**Missing vmlinux**:
```
Error: vmlinux not found at /Users/YOUR_USERNAME/.hops/vmlinux
See docs/setup.md for kernel installation instructions.
```

**Missing initfs**:
```
Error: initfs not found at /Users/YOUR_USERNAME/.hops/initfs
See docs/setup.md for initfs installation instructions.
```

### Troubleshooting

#### Kernel file is corrupted or wrong architecture

```bash
file ~/.hops/vmlinux
```

Must show: `Linux kernel ARM64 boot executable Image`

If not, re-download or rebuild the kernel.

#### Initfs is not a valid ext4 filesystem

```bash
file ~/.hops/initfs
```

Must show: `Linux rev 1.0 ext4 filesystem data`

Verify with:
```bash
hdiutil attach -readonly ~/.hops/initfs
ls /Volumes/initfs
hdiutil detach /Volumes/initfs
```

Should contain: `/sbin/init`, `/bin/`, `/lib/`, `/etc/`

#### Kernel build fails

Common issues:
- **Out of disk space**: Kernel build requires ~5 GB. Free up space and retry.
- **Network issues downloading kernel source**: Check network connection and retry.
- **Missing build tools**: Install Xcode Command Line Tools: `xcode-select --install`

Check kernel build logs:
```bash
cd ~/src/containerization/kernel
make clean
make V=1 2>&1 | tee build.log
```

### Alternative Kernel Locations

By default, Hops expects kernel/initfs at `~/.hops/`. If you want to use a different location, you can:

1. Create symlinks:

```bash
ln -s /path/to/custom/vmlinux ~/.hops/vmlinux
ln -s /path/to/custom/initfs ~/.hops/initfs
```

2. Modify SandboxManager initialization (requires rebuilding Hops):

Edit `Sources/hopsd/SandboxManager.swift` lines 27-28 to point to custom paths.

### Security Considerations

- **Kernel updates**: Regularly update your kernel to receive security patches
- **Custom kernels**: Only use custom kernels if you understand the security implications
- **File permissions**: Keep kernel/initfs files readable only by your user (644 or 600)
- **Verification**: Always verify checksums of downloaded kernel/initfs files from Apple releases

### Grant Full Disk Access (Required)

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

Requires macOS 26+ on Apple Silicon.

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
