use serde::{Deserialize, Serialize};
use std::collections::HashSet;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SandboxConfig {
    #[serde(rename = "root_path")]
    pub root_path: String,
    #[serde(default)]
    pub mounts: Vec<MountConfig>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub hostname: Option<String>,
    #[serde(default = "default_working_directory")]
    pub working_directory: String,
    #[serde(default)]
    pub environment: std::collections::HashMap<String, String>,
}

fn default_working_directory() -> String {
    String::from("/")
}

impl Default for SandboxConfig {
    fn default() -> Self {
        Self {
            root_path: String::from("/"),
            mounts: vec![],
            hostname: None,
            working_directory: String::from("/"),
            environment: std::collections::HashMap::new(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MountConfig {
    pub source: String,
    pub destination: String,
    #[serde(rename = "type")]
    pub mount_type: MountType,
    #[serde(default = "default_mount_mode")]
    pub mode: MountMode,
    #[serde(default)]
    pub options: Vec<String>,
}

fn default_mount_mode() -> MountMode {
    MountMode::ReadOnly
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum MountType {
    Bind,
    Tmpfs,
    Devtmpfs,
    Proc,
    Sysfs,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum MountMode {
    #[serde(rename = "ro")]
    ReadOnly,
    #[serde(rename = "rw")]
    ReadWrite,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CapabilityGrant {
    pub network: NetworkCapability,
    #[serde(default)]
    pub filesystem: HashSet<FilesystemCapability>,
    #[serde(rename = "allowed_paths", default)]
    pub allowed_paths: Vec<String>,
    #[serde(rename = "denied_paths", default)]
    pub denied_paths: Vec<String>,
    #[serde(rename = "resource_limits", default)]
    pub resource_limits: ResourceLimits,
}

impl Default for CapabilityGrant {
    fn default() -> Self {
        Self {
            network: NetworkCapability::Disabled,
            filesystem: HashSet::new(),
            allowed_paths: vec![],
            denied_paths: vec![],
            resource_limits: ResourceLimits::default(),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum NetworkCapability {
    Disabled,
    Outbound,
    Loopback,
    Full,
}

impl NetworkCapability {
    pub fn as_str(&self) -> &'static str {
        match self {
            NetworkCapability::Disabled => "disabled",
            NetworkCapability::Outbound => "outbound",
            NetworkCapability::Loopback => "loopback",
            NetworkCapability::Full => "full",
        }
    }

    pub fn from_str(s: &str) -> Self {
        match s {
            "outbound" => NetworkCapability::Outbound,
            "loopback" => NetworkCapability::Loopback,
            "full" => NetworkCapability::Full,
            _ => NetworkCapability::Disabled,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum FilesystemCapability {
    Read,
    Write,
    Execute,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ResourceLimits {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cpus: Option<u32>,
    #[serde(rename = "memory_bytes", skip_serializing_if = "Option::is_none")]
    pub memory_bytes: Option<u64>,
    #[serde(rename = "max_processes", skip_serializing_if = "Option::is_none")]
    pub max_processes: Option<u32>,
}

impl Default for ResourceLimits {
    fn default() -> Self {
        Self {
            cpus: None,
            memory_bytes: None,
            max_processes: None,
        }
    }
}
