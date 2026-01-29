use crate::models::capability::{CapabilityGrant, SandboxConfig};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Policy {
    #[serde(skip)]
    pub name: String,
    #[serde(default = "default_version")]
    pub version: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    pub capabilities: CapabilityGrant,
    pub sandbox: SandboxConfig,
    #[serde(default)]
    pub metadata: HashMap<String, String>,
}

fn default_version() -> String {
    String::from("1.0.0")
}

impl Default for Policy {
    fn default() -> Self {
        Self {
            name: String::from("default"),
            version: String::from("1.0.0"),
            description: None,
            capabilities: CapabilityGrant::default(),
            sandbox: SandboxConfig::default(),
            metadata: HashMap::new(),
        }
    }
}
