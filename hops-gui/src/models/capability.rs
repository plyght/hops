use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Sandbox {
    pub root: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Capabilities {
    pub network: String,
    pub filesystem: FilesystemCapability,
}

impl Default for Capabilities {
    fn default() -> Self {
        Self {
            network: String::from("disabled"),
            filesystem: FilesystemCapability::default(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FilesystemCapability {
    pub read: Vec<String>,
    pub write: Vec<String>,
    pub execute: Vec<String>,
}

impl Default for FilesystemCapability {
    fn default() -> Self {
        Self {
            read: vec![String::from(".")],
            write: vec![],
            execute: vec![String::from(".")],
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Resources {
    pub cpus: u32,
    pub memory: String,
    pub max_processes: u32,
}

impl Default for Resources {
    fn default() -> Self {
        Self {
            cpus: 2,
            memory: String::from("512M"),
            max_processes: 100,
        }
    }
}
