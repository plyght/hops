use hyper_util::rt::TokioIo;
use prost_types::Timestamp;
use std::path::PathBuf;
use tonic::transport::{Endpoint, Uri};
use tower::service_fn;

pub mod hops {
    tonic::include_proto!("hops");
}

use hops::hops_service_client::HopsServiceClient;
use hops::{
    ListRequest, RunRequest, SandboxInfo, SandboxStatus, StatusRequest, StopRequest,
};

#[derive(Debug)]
pub enum GrpcError {
    ConnectionFailed(String),
    RequestFailed(String),
    InvalidResponse(String),
}

impl std::fmt::Display for GrpcError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            GrpcError::ConnectionFailed(msg) => write!(f, "Connection failed: {}", msg),
            GrpcError::RequestFailed(msg) => write!(f, "Request failed: {}", msg),
            GrpcError::InvalidResponse(msg) => write!(f, "Invalid response: {}", msg),
        }
    }
}

impl std::error::Error for GrpcError {}

#[derive(Debug)]
pub struct GrpcClient {
    client: HopsServiceClient<tonic::transport::Channel>,
}

impl GrpcClient {
    pub async fn connect() -> Result<Self, GrpcError> {
        let socket_path = dirs::home_dir()
            .ok_or_else(|| GrpcError::ConnectionFailed("Cannot determine home directory".into()))?
            .join(".hops")
            .join("hops.sock");

        if !socket_path.exists() {
            return Err(GrpcError::ConnectionFailed(
                "Daemon socket not found. Is hopsd running?".into(),
            ));
        }

        let channel = Endpoint::try_from("http://[::]:50051")
            .map_err(|e| GrpcError::ConnectionFailed(format!("Invalid endpoint: {}", e)))?
            .connect_with_connector(service_fn(move |_: Uri| {
                let path = socket_path.clone();
                async move {
                    let stream = tokio::net::UnixStream::connect(path).await?;
                    Ok::<_, std::io::Error>(TokioIo::new(stream))
                }
            }))
            .await
            .map_err(|e| GrpcError::ConnectionFailed(format!("Failed to connect: {}", e)))?;

        Ok(Self {
            client: HopsServiceClient::new(channel),
        })
    }

    pub async fn run_sandbox(
        &mut self,
        policy: &crate::models::policy::Policy,
        command: Vec<String>,
        working_dir: Option<String>,
    ) -> Result<RunSandboxResponse, GrpcError> {
        let proto_policy = convert_policy_to_proto(policy);

        let request = tonic::Request::new(RunRequest {
            command,
            policy_path: None,
            inline_policy: Some(proto_policy),
            environment: std::collections::HashMap::new(),
            working_directory: working_dir,
            keep: false,
            allocate_tty: false,
        });

        let response = self
            .client
            .run_sandbox(request)
            .await
            .map_err(|e| GrpcError::RequestFailed(format!("RunSandbox RPC failed: {}", e)))?
            .into_inner();

        Ok(RunSandboxResponse {
            sandbox_id: response.sandbox_id,
            pid: response.pid,
            success: response.success,
            error: response.error,
        })
    }

    pub async fn stop_sandbox(
        &mut self,
        sandbox_id: String,
        force: bool,
    ) -> Result<StopSandboxResponse, GrpcError> {
        let request = tonic::Request::new(StopRequest { sandbox_id, force });

        let response = self
            .client
            .stop_sandbox(request)
            .await
            .map_err(|e| GrpcError::RequestFailed(format!("StopSandbox RPC failed: {}", e)))?
            .into_inner();

        Ok(StopSandboxResponse {
            success: response.success,
            error: response.error,
        })
    }

    pub async fn list_sandboxes(
        &mut self,
        include_stopped: bool,
    ) -> Result<Vec<SandboxInfo>, GrpcError> {
        let request = tonic::Request::new(ListRequest { include_stopped });

        let response = self
            .client
            .list_sandboxes(request)
            .await
            .map_err(|e| GrpcError::RequestFailed(format!("ListSandboxes RPC failed: {}", e)))?
            .into_inner();

        Ok(response.sandboxes)
    }

    pub async fn get_status(&mut self, sandbox_id: String) -> Result<SandboxStatus, GrpcError> {
        let request = tonic::Request::new(StatusRequest { sandbox_id });

        let response = self
            .client
            .get_status(request)
            .await
            .map_err(|e| GrpcError::RequestFailed(format!("GetStatus RPC failed: {}", e)))?
            .into_inner();

        Ok(response)
    }
}

#[derive(Debug, Clone)]
pub struct RunSandboxResponse {
    pub sandbox_id: String,
    pub pid: i32,
    pub success: bool,
    pub error: Option<String>,
}

#[derive(Debug, Clone)]
pub struct StopSandboxResponse {
    pub success: bool,
    pub error: Option<String>,
}

fn convert_policy_to_proto(policy: &crate::models::policy::Policy) -> hops::Policy {
    use crate::models::capability::{FilesystemCapability, NetworkCapability};

    let network_access = match policy.capabilities.network {
        NetworkCapability::Disabled => hops::NetworkAccess::Disabled as i32,
        NetworkCapability::Outbound => hops::NetworkAccess::Outbound as i32,
        NetworkCapability::Loopback => hops::NetworkAccess::Loopback as i32,
        NetworkCapability::Full => hops::NetworkAccess::Full as i32,
    };

    let mut fs_read = Vec::new();
    let mut fs_write = Vec::new();
    let mut fs_execute = Vec::new();

    for cap in &policy.capabilities.filesystem {
        match cap {
            FilesystemCapability::Read => {
                fs_read.extend(policy.capabilities.allowed_paths.clone())
            }
            FilesystemCapability::Write => {
                fs_write.extend(policy.capabilities.allowed_paths.clone())
            }
            FilesystemCapability::Execute => {
                fs_execute.extend(policy.capabilities.allowed_paths.clone())
            }
        }
    }

    let filesystem = hops::FilesystemCapabilities {
        read: fs_read,
        write: fs_write,
        execute: fs_execute,
    };

    let capabilities = hops::Capabilities {
        network: network_access,
        filesystem: Some(filesystem),
    };

    let resources = hops::ResourceLimits {
        cpus: policy.capabilities.resource_limits.cpus.unwrap_or(0) as i32,
        memory: format_memory(policy.capabilities.resource_limits.memory_bytes),
        max_processes: policy.capabilities.resource_limits.max_processes.unwrap_or(0) as i32,
    };

    let sandbox = hops::SandboxConfig {
        root: policy.sandbox.root_path.clone(),
    };

    hops::Policy {
        sandbox: Some(sandbox),
        capabilities: Some(capabilities),
        resources: Some(resources),
    }
}

fn format_memory(bytes: Option<u64>) -> String {
    match bytes {
        Some(b) => {
            if b >= 1024 * 1024 * 1024 {
                format!("{}G", b / (1024 * 1024 * 1024))
            } else if b >= 1024 * 1024 {
                format!("{}M", b / (1024 * 1024))
            } else if b >= 1024 {
                format!("{}K", b / 1024)
            } else {
                format!("{}", b)
            }
        }
        None => "0".to_string(),
    }
}
