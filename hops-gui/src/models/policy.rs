use crate::models::capability::{Capabilities, Resources, Sandbox};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Policy {
    #[serde(skip)]
    pub name: String,
    pub sandbox: Sandbox,
    pub capabilities: Capabilities,
    pub resources: Resources,
}

impl Default for Policy {
    fn default() -> Self {
        Self {
            name: String::from("default"),
            sandbox: Sandbox {
                root: String::from("."),
            },
            capabilities: Capabilities::default(),
            resources: Resources::default(),
        }
    }
}
