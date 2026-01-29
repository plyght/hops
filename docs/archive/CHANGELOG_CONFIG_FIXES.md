# Configuration and Launchd Fixes

## Summary

Fixed critical configuration format mismatches, launchd path issues, and added comprehensive documentation and example configurations.

## Critical Fixes

### 1. Launchd Plist Path Issues (CRITICAL)

**Problem**: `com.hops.daemon.plist` used `~` which doesn't expand in launchd context.

**Fixed Paths**:
- Socket: `~/.hops/hops.sock` → `/var/run/hops/hops.sock`
- Stdout: `~/.hops/logs/hopsd.log` → `/usr/local/var/log/hops/hopsd.log`
- Stderr: `~/.hops/logs/hopsd.error.log` → `/usr/local/var/log/hops/hopsd.error.log`
- Config: `~/.hops` → `/usr/local/etc/hops`

**Rationale**: Uses standard macOS system paths for services. Socket at `/var/run/` follows Unix conventions, logs at `/usr/local/var/log/` match Homebrew patterns.

### 2. Config Format Mismatch (CRITICAL)

**Problem**: Example configs used nested structure incompatible with PolicyParser:
```toml
[capabilities.filesystem]
read = ["."]
write = []
execute = ["."]
```

**Fixed Format** (matches PolicyParser expectations):
```toml
[capabilities]
filesystem = ["read", "write", "execute"]
allowed_paths = ["/usr", "/System"]
denied_paths = ["/etc/shadow"]
```

**Impact**: ALL example configs were invalid and would fail parsing. Now fixed to match PolicyParser.swift implementation.

## New Files

### Launchd Directory (`launchd/`)

1. **`install.sh`** (executable)
   - Automated system-wide installation script
   - Creates directories, sets permissions, loads daemon
   - Verifies installation success

2. **`install-user.sh`** (executable)
   - Automated user-specific installation script
   - No root required, runs in user space
   - Expands `$HOME` in plist template

3. **`com.hops.daemon.user.plist`**
   - User-specific LaunchAgent alternative
   - Uses `$HOME/.hops/` paths (requires expansion)
   - Runs without elevated privileges

4. **`README.md`**
   - Complete launchd documentation
   - System-wide vs user-specific comparison
   - Management commands, troubleshooting
   - Advanced configuration examples

### Configuration Directory (`config/`)

1. **`build.toml`** (NEW)
   - Build environment with network access
   - 8 GB memory, 8 CPUs, 512 processes
   - Outbound network for package downloads
   - Read-write access to `/usr/local` and `/opt`

2. **`ci.toml`** (NEW)
   - CI/CD testing environment
   - 4 GB memory, 4 CPUs, 256 processes
   - Outbound network, isolated filesystem
   - CI environment variables

3. **`minimal.toml`** (NEW)
   - Absolute minimum permissions
   - 128 MB memory, 1 CPU, 5 processes
   - No network, no filesystem access
   - Tmpfs-only sandbox

4. **`README.md`**
   - Comprehensive format documentation
   - Complete field reference
   - Security best practices
   - Common patterns and troubleshooting

### Documentation Directory (`docs/`)

1. **`setup.md`** (NEW)
   - Complete installation guide
   - Prerequisites and build instructions
   - System directory setup
   - Launchd installation and management
   - Kernel configuration for Containerization.framework
   - Full Disk Access requirements
   - Usage examples
   - Extensive troubleshooting section
   - Security considerations
   - Advanced configuration patterns
   - Performance tuning guidelines

## Updated Files

### `config/default.toml`

**Before**: Minimal config with invalid format
```toml
[capabilities.filesystem]
read = ["."]
```

**After**: Comprehensive default with correct format
```toml
[capabilities]
filesystem = ["read", "execute"]
allowed_paths = ["/usr/lib", "/usr/local/lib", "/System/Library"]
denied_paths = ["/etc/shadow", "/etc/master.passwd"]

[capabilities.resource_limits]
cpus = 2
memory_bytes = 536870912
max_processes = 100
```

Added name, version, description, mounts, and environment sections.

### `config/examples/untrusted.toml`

**Changes**:
- Fixed format to match PolicyParser
- Changed from nested `capabilities.filesystem` to flat `capabilities.filesystem` array
- Added proper allowed_paths/denied_paths
- Added name, version, description
- Added comprehensive mounts section
- Set `denied_paths = ["/"]` for maximum security

### `config/examples/development.toml`

**Changes**:
- Fixed format to match PolicyParser
- Expanded allowed_paths to include all development tools
- Added comprehensive mount configurations
- Maintained generous resource limits (8 GB, 8 CPUs, 500 processes)

### `config/examples/network-allowed.toml`

**Changes**:
- Fixed format to match PolicyParser
- Added SSL and DNS paths for network functionality
- Proper mount configurations for network requirements
- Denied sensitive paths while allowing network

## Format Alignment

Verified all configs now match PolicyParser.swift expectations:

| Parser Field | TOML Path | Type | Example |
|--------------|-----------|------|---------|
| `network` | `capabilities.network` | String | `"disabled"` |
| `filesystem` | `capabilities.filesystem` | Array | `["read", "write"]` |
| `allowedPaths` | `capabilities.allowed_paths` | Array | `["/usr", "/System"]` |
| `deniedPaths` | `capabilities.denied_paths` | Array | `["/etc/shadow"]` |
| `resourceLimits` | `capabilities.resource_limits` | Table | See below |
| `cpus` | `capabilities.resource_limits.cpus` | Integer | `4` |
| `memoryBytes` | `capabilities.resource_limits.memory_bytes` | Integer | `4294967296` |
| `maxProcesses` | `capabilities.resource_limits.max_processes` | Integer | `256` |

## Security Improvements

All configs now include:
- Explicit denied_paths for sensitive files
- Absolute paths only (no relative paths)
- Read-only mounts for system directories
- Tmpfs for temporary data (no persistence)
- Appropriate resource limits per use case
- Network restrictions by default

Sensitive paths now denied in all profiles:
- `/etc/shadow`
- `/etc/master.passwd`
- `/var/db/dslocal`
- `/private/var/db/dslocal`

## Installation Options

Users now have two installation paths:

### System-Wide (Recommended)
- Daemon: `/Library/LaunchDaemons/`
- Socket: `/var/run/hops/hops.sock`
- Logs: `/usr/local/var/log/hops/`
- Configs: `/usr/local/etc/hops/profiles/`
- Survives user logout
- Requires sudo

### User-Specific
- Agent: `~/Library/LaunchAgents/`
- Socket: `~/.hops/hops.sock`
- Logs: `~/.hops/logs/`
- Configs: `~/.hops/profiles/`
- Stops on logout
- No sudo required

## Testing Recommendations

Before deployment, test each config:

```bash
hops profile validate config/examples/build.toml
hops profile validate config/examples/ci.toml
hops profile validate config/examples/minimal.toml
hops profile validate config/examples/untrusted.toml
hops profile validate config/examples/development.toml
hops profile validate config/examples/network-allowed.toml
```

Test launchd installation:
```bash
sudo launchd/install.sh
ps aux | grep hopsd
ls -la /var/run/hops/hops.sock
tail -f /usr/local/var/log/hops/hopsd.log
```

Test profile execution:
```bash
hops run --profile minimal . -- /bin/echo "test"
hops run --profile untrusted . -- /bin/ls
hops run --profile build . -- /usr/bin/env
```

## Breaking Changes

**IMPORTANT**: Old config format is no longer valid.

**Before** (BROKEN):
```toml
[capabilities.filesystem]
read = ["."]
write = []
execute = ["."]
```

**After** (CORRECT):
```toml
[capabilities]
filesystem = ["read", "write", "execute"]
allowed_paths = ["."]
denied_paths = []
```

Any existing user configs must be migrated to the new format.

## Migration Guide

For users with existing configs:

1. Add required fields:
   ```toml
   name = "my-profile"
   version = "1.0.0"
   description = "My custom profile"
   ```

2. Flatten filesystem capabilities:
   ```toml
   [capabilities]
   filesystem = ["read", "write", "execute"]  # Array, not nested table
   ```

3. Add path lists:
   ```toml
   [capabilities]
   allowed_paths = ["/path1", "/path2"]
   denied_paths = ["/etc/shadow"]
   ```

4. Rename resource section:
   ```toml
   [capabilities.resource_limits]  # was [resources]
   cpus = 2
   memory_bytes = 536870912        # was memory = "512M"
   max_processes = 100
   ```

5. Add sandbox configuration:
   ```toml
   [sandbox]
   root_path = "/"
   working_directory = "/"
   ```

6. Add mounts:
   ```toml
   [[sandbox.mounts]]
   source = "/usr"
   destination = "/usr"
   type = "bind"
   mode = "ro"
   ```

## Documentation Coverage

New documentation provides:
- Installation procedures (system and user)
- Directory structure requirements
- Launchd service management
- Kernel configuration for Containerization
- Full Disk Access setup
- Profile creation and management
- Complete TOML format reference
- Security best practices
- Troubleshooting guides
- Performance tuning
- Common usage patterns

## Next Steps

Recommended for other agents:
1. Update CLI to use new default socket path (`/var/run/hops/hops.sock`)
2. Add `hops profile validate` command using PolicyParser
3. Add `hops profile migrate` command for old → new format
4. Update error messages to reference new documentation
5. Add tests for all example configs
6. Consider adding profile templates to `hops profile create`

## Files Modified

- `launchd/com.hops.daemon.plist` - Fixed paths
- `config/default.toml` - Complete rewrite
- `config/examples/untrusted.toml` - Format fix
- `config/examples/development.toml` - Format fix
- `config/examples/network-allowed.toml` - Format fix

## Files Created

- `launchd/com.hops.daemon.user.plist` - User agent
- `launchd/install.sh` - System installer
- `launchd/install-user.sh` - User installer
- `launchd/README.md` - Launchd documentation
- `config/examples/build.toml` - Build profile
- `config/examples/ci.toml` - CI profile
- `config/examples/minimal.toml` - Minimal profile
- `config/README.md` - Config documentation
- `docs/setup.md` - Setup guide
- `CHANGELOG_CONFIG_FIXES.md` - This file

## Summary Statistics

- **Files modified**: 5
- **Files created**: 9
- **Total files affected**: 14
- **Lines of documentation**: ~700
- **Example configs**: 6 (3 new + 3 fixed)
- **Installation scripts**: 2
- **Critical bugs fixed**: 2
