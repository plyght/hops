# Hops Configuration Format

TOML-based configuration files for defining sandbox profiles.

## Directory Structure

```
config/
├── default.toml           # Default profile
├── examples/
│   ├── minimal.toml      # Absolute minimum permissions
│   ├── untrusted.toml    # Maximum security for untrusted code
│   ├── development.toml  # Development environment
│   ├── network-allowed.toml # Network-enabled sandbox
│   ├── build.toml        # Build environment
│   └── ci.toml           # CI/CD environment
└── README.md             # This file
```

## Profile Format

### Required Fields

```toml
name = "profile-name"
version = "1.0.0"
description = "Profile description"
```

### Capabilities Section

```toml
[capabilities]
network = "disabled"  # disabled | loopback | outbound | full
filesystem = ["read", "write", "execute"]  # Array of capabilities
allowed_paths = ["/usr", "/System"]  # Explicitly allowed paths
denied_paths = ["/etc/shadow"]       # Explicitly denied paths (takes precedence)
```

#### Network Capabilities

| Value | Description |
|-------|-------------|
| `disabled` | No network access (default, most secure) |
| `loopback` | Loopback interface only (127.0.0.1) |
| `outbound` | Outbound connections allowed |
| `full` | Full network access (least secure) |

#### Filesystem Capabilities

Array containing any combination of:
- `read` - Read file contents, list directories
- `write` - Modify files, create/delete files
- `execute` - Execute binaries and scripts

If empty array `[]`, no filesystem access is granted.

#### Path Allow/Deny Lists

**allowed_paths**: Paths that processes in the sandbox can access (subject to filesystem capabilities).

**denied_paths**: Paths that are explicitly forbidden, overriding allowed_paths.

Path matching rules:
- Paths must be absolute (start with `/`)
- Subdirectories are implicitly included
- More specific paths take precedence
- denied_paths always override allowed_paths

Examples:
```toml
allowed_paths = [
    "/usr",           # Allows /usr and all subdirectories
    "/System/Library" # Allows /System/Library and subdirectories
]

denied_paths = [
    "/etc/shadow",        # Explicitly deny sensitive files
    "/usr/local/secrets"  # Deny even if /usr is allowed
]
```

### Resource Limits Section

```toml
[capabilities.resource_limits]
cpus = 2                     # Maximum CPU cores
memory_bytes = 536870912     # Maximum memory in bytes
max_processes = 100          # Maximum number of processes
```

#### Memory Size Reference

| Size | Bytes | Use Case |
|------|-------|----------|
| 128 MB | 134217728 | Minimal scripts |
| 256 MB | 268435456 | Light processes |
| 512 MB | 536870912 | Standard processes |
| 1 GB | 1073741824 | Network applications |
| 2 GB | 2147483648 | Development tools |
| 4 GB | 4294967296 | Build processes |
| 8 GB | 8589934592 | Heavy compilation |

### Sandbox Section

```toml
[sandbox]
root_path = "/"                    # Sandbox root directory
working_directory = "/"            # Initial working directory
hostname = "sandbox-hostname"      # Optional custom hostname
```

### Mounts Section

Define filesystem mounts for the sandbox:

```toml
[[sandbox.mounts]]
source = "/usr"           # Source path on host
destination = "/usr"      # Destination path in sandbox
type = "bind"             # Mount type: bind | tmpfs | overlay
mode = "ro"               # Mount mode: ro (read-only) | rw (read-write)
options = []              # Optional mount options
```

#### Mount Types

| Type | Description |
|------|-------------|
| `bind` | Bind mount from host filesystem |
| `tmpfs` | Temporary filesystem in memory (volatile) |
| `overlay` | Overlay filesystem (copy-on-write) |

#### Mount Modes

| Mode | Description |
|------|-------------|
| `ro` | Read-only mount (secure, recommended for system paths) |
| `rw` | Read-write mount (use with caution) |

#### Common Mount Patterns

**System libraries** (read-only):
```toml
[[sandbox.mounts]]
source = "/usr"
destination = "/usr"
type = "bind"
mode = "ro"
```

**Temporary storage** (memory-backed):
```toml
[[sandbox.mounts]]
source = "tmpfs"
destination = "/tmp"
type = "tmpfs"
mode = "rw"
```

**SSL certificates** (required for HTTPS):
```toml
[[sandbox.mounts]]
source = "/etc/ssl"
destination = "/etc/ssl"
type = "bind"
mode = "ro"
```

**DNS resolution** (required for network):
```toml
[[sandbox.mounts]]
source = "/etc/resolv.conf"
destination = "/etc/resolv.conf"
type = "bind"
mode = "ro"
```

**Overlay filesystem** (copy-on-write):
```toml
[[sandbox.mounts]]
source = "/usr/local"
destination = "/usr/local"
type = "overlay"
mode = "rw"
options = [
    "lowerdir=/usr/local",
    "upperdir=/tmp/overlay-upper",
    "workdir=/tmp/overlay-work"
]
```

### Environment Section

Define environment variables for processes in the sandbox:

```toml
[sandbox.environment]
PATH = "/usr/local/bin:/usr/bin:/bin"
HOME = "/sandbox"
TMPDIR = "/tmp"
RUST_BACKTRACE = "1"
```

## Complete Example

```toml
name = "web-service"
version = "1.0.0"
description = "Isolated web service with network access"

[capabilities]
network = "outbound"
filesystem = ["read", "execute"]
allowed_paths = [
    "/usr/lib",
    "/System/Library",
    "/etc/ssl",
    "/etc/resolv.conf"
]
denied_paths = [
    "/etc/shadow",
    "/etc/master.passwd",
    "/Users"
]

[capabilities.resource_limits]
cpus = 4
memory_bytes = 2147483648
max_processes = 200

[sandbox]
root_path = "/"
working_directory = "/app"
hostname = "web-sandbox"

[[sandbox.mounts]]
source = "/usr"
destination = "/usr"
type = "bind"
mode = "ro"

[[sandbox.mounts]]
source = "/System"
destination = "/System"
type = "bind"
mode = "ro"

[[sandbox.mounts]]
source = "/etc/ssl"
destination = "/etc/ssl"
type = "bind"
mode = "ro"

[[sandbox.mounts]]
source = "tmpfs"
destination = "/tmp"
type = "tmpfs"
mode = "rw"

[[sandbox.mounts]]
source = "tmpfs"
destination = "/app"
type = "tmpfs"
mode = "rw"

[sandbox.environment]
PATH = "/usr/local/bin:/usr/bin:/bin"
PORT = "8080"
```

## Profile Selection

### System-Wide Profiles

Installed at: `/usr/local/etc/hops/profiles/`

```bash
hops run --profile build /path/to/project -- make
```

### User-Specific Profiles

Installed at: `~/.hops/profiles/`

```bash
hops run --profile custom /path/to/project -- npm test
```

### Inline Profile

Use a profile file directly:

```bash
hops run --config /path/to/custom.toml /path/to/project -- python script.py
```

## Validation

Profiles are validated on load for:
- Required fields (name, version)
- Valid capability values
- Absolute paths (allowed_paths, denied_paths)
- Path conflicts (allowed vs denied)
- Valid mount configurations
- Resource limit sanity

Invalid profiles will fail with descriptive errors.

## Security Best Practices

1. **Start restrictive**: Begin with `minimal.toml` or `untrusted.toml`
2. **Principle of least privilege**: Only grant necessary capabilities
3. **Network isolation**: Use `network = "disabled"` unless required
4. **Path restrictions**: Minimize allowed_paths, maximize denied_paths
5. **Resource limits**: Set appropriate limits to prevent DoS
6. **Read-only mounts**: Use `mode = "ro"` for system paths
7. **Deny sensitive files**: Always deny `/etc/shadow`, `/etc/master.passwd`, `/var/db/dslocal`
8. **Use tmpfs**: Prefer tmpfs for temporary data (no persistence)
9. **Review regularly**: Audit profiles periodically
10. **Version control**: Track profile changes in git

## Common Patterns

### Untrusted Code Execution

```toml
network = "disabled"
filesystem = []
allowed_paths = []
denied_paths = ["/"]
memory_bytes = 268435456
max_processes = 10
```

### Web Development

```toml
network = "loopback"
filesystem = ["read", "write", "execute"]
allowed_paths = ["/usr", "/System", "/usr/local"]
memory_bytes = 4294967296
max_processes = 500
```

### Package Building

```toml
network = "outbound"
filesystem = ["read", "write", "execute"]
allowed_paths = ["/usr", "/usr/local", "/opt", "/tmp"]
memory_bytes = 8589934592
max_processes = 512
```

### CI/CD Testing

```toml
network = "outbound"
filesystem = ["read", "execute"]
allowed_paths = ["/usr", "/System"]
memory_bytes = 4294967296
max_processes = 256
```

## Troubleshooting

### Profile Not Found

Check profile paths:
```bash
ls -la /usr/local/etc/hops/profiles/
ls -la ~/.hops/profiles/
```

### Validation Errors

Common issues:
- Relative paths in allowed_paths/denied_paths (must be absolute)
- Invalid network capability value
- Invalid filesystem capability value
- Missing required fields (name, version)

### Permission Denied

Ensure allowed_paths includes necessary directories and filesystem capabilities include required operations.

### Network Not Working

For network access, ensure:
- `network = "outbound"` or higher
- Mount `/etc/resolv.conf` for DNS
- Mount `/etc/ssl` for HTTPS

## See Also

- [Setup Guide](../docs/setup.md) - Installation and configuration
- [Example Profiles](examples/) - Pre-configured profiles
- [PolicyParser.swift](../Sources/HopsCore/PolicyParser.swift) - TOML parser implementation
- [PolicyValidator.swift](../Sources/HopsCore/PolicyValidator.swift) - Validation rules
