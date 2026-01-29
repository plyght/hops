# Rust GUI Model Synchronization Status

## ✅ COMPLETED - Model Layer Aligned with Swift Core

All Rust model structures have been updated to match Swift Core types.

### Files Modified

1. **hops-gui/src/models/capability.rs** - Complete restructure
   - Added `NetworkCapability` enum (Disabled, Outbound, Loopback, Full)
   - Added `FilesystemCapability` enum (Read, Write, Execute)
   - Replaced `Capabilities` with `CapabilityGrant`
   - Replaced `Resources` with `ResourceLimits` (optional fields)
   - Replaced `Sandbox` with `SandboxConfig` (full fields)
   - Added `MountConfig`, `MountType`, `MountMode` structs/enums
   - Added helper methods: `NetworkCapability::as_str()`, `NetworkCapability::from_str()`

2. **hops-gui/src/models/policy.rs** - Extended structure
   - Added `version`, `description`, `metadata` fields
   - Updated to use `CapabilityGrant` and `SandboxConfig`

3. **hops-gui/src/views/profile_editor.rs** - Line 8 only
   - Updated `NETWORK_OPTIONS` constant to include all 4 network capability values

### Model Structure Alignment

#### NetworkCapability Enum
```rust
pub enum NetworkCapability {
    Disabled,   // ✅ matches Swift
    Outbound,   // ✅ matches Swift
    Loopback,   // ✅ matches Swift
    Full,       // ✅ matches Swift
}
```

#### FilesystemCapability Enum
```rust
pub enum FilesystemCapability {
    Read,       // ✅ matches Swift
    Write,      // ✅ matches Swift
    Execute,    // ✅ matches Swift
}
```

#### CapabilityGrant Struct
```rust
pub struct CapabilityGrant {
    pub network: NetworkCapability,             // ✅ enum type
    pub filesystem: HashSet<FilesystemCapability>, // ✅ set of enums
    pub allowed_paths: Vec<String>,             // ✅ added
    pub denied_paths: Vec<String>,              // ✅ added
    pub resource_limits: ResourceLimits,        // ✅ nested struct
}
```

#### ResourceLimits Struct
```rust
pub struct ResourceLimits {
    pub cpus: Option<u32>,           // ✅ optional, matches Swift UInt?
    pub memory_bytes: Option<u64>,   // ✅ optional, matches Swift UInt64?
    pub max_processes: Option<u32>,  // ✅ optional, matches Swift UInt?
}
```

#### SandboxConfig Struct
```rust
pub struct SandboxConfig {
    pub root_path: String,                       // ✅ matches Swift rootPath
    pub mounts: Vec<MountConfig>,                // ✅ matches Swift mounts
    pub hostname: Option<String>,                // ✅ matches Swift hostname
    pub working_directory: String,               // ✅ matches Swift workingDirectory
    pub environment: HashMap<String, String>,    // ✅ matches Swift environment
}
```

#### MountConfig Struct
```rust
pub struct MountConfig {
    pub source: String,          // ✅ matches Swift
    pub destination: String,     // ✅ matches Swift
    pub mount_type: MountType,   // ✅ matches Swift type
    pub mode: MountMode,         // ✅ matches Swift mode
    pub options: Vec<String>,    // ✅ matches Swift options
}
```

#### Policy Struct
```rust
pub struct Policy {
    pub name: String,                          // ✅ matches Swift
    pub version: String,                       // ✅ matches Swift
    pub description: Option<String>,           // ✅ matches Swift
    pub capabilities: CapabilityGrant,         // ✅ matches Swift
    pub sandbox: SandboxConfig,                // ✅ matches Swift
    pub metadata: HashMap<String, String>,     // ✅ matches Swift
}
```

### TOML Compatibility

All serde attributes configured for correct TOML parsing:
- ✅ Field name mappings (snake_case with renames)
- ✅ Enum lowercase serialization
- ✅ Optional field handling
- ✅ Default values

### Known Integration Points for Agent 6 (UI/UX)

The following files need updates to work with the new model structure:

1. **app.rs** - Message handlers access old model structure:
   - Line 174: `network` field now enum, needs `NetworkCapability::from_str()`
   - Lines 203-213: `filesystem.read/write/execute` no longer exist, use `allowed_paths`
   - Lines 224-236: Same as above
   - Lines 245, 252, 260: `resources` moved to `capabilities.resource_limits`
   - Resource fields now optional (Option<T>)

2. **profile_editor.rs** - View accesses old model:
   - Line 17: `network.as_str()` already works (added helper)
   - Lines 23-48: `filesystem.read/write/execute` no longer exist
   - Lines 63-67: `resources.*` moved to `capabilities.resource_limits.*`

3. **profile_list.rs** - May access model fields

### Testing

TOML parsing should work correctly with the new models. Example config:

```toml
name = "test"
version = "1.0.0"
description = "Test profile"

[capabilities]
network = "outbound"
filesystem = ["read", "write"]
allowed_paths = ["/usr", "/lib"]
denied_paths = ["/etc/shadow"]

[capabilities.resource_limits]
cpus = 4
memory_bytes = 4294967296
max_processes = 256

[sandbox]
root_path = "/"
hostname = "test-sandbox"
working_directory = "/"

[[sandbox.mounts]]
source = "/usr"
destination = "/usr"
type = "bind"
mode = "ro"
```

---

**Status**: Model layer sync ✅ COMPLETE
**Next**: Agent 6 to update view layer and app message handlers
