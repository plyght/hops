use crate::grpc_client::{GrpcClient, GrpcError};
use crate::models::capability::{FilesystemCapability, NetworkCapability};
use crate::models::policy::Policy;
use crate::utils::config;
use crate::views::{profile_editor, profile_list, run_history};
use iced::{
    widget::{container, row},
    Element, Length, Task, Theme,
};
use std::collections::HashMap;

pub struct HopsGui {
    pub profiles: Vec<Policy>,
    pub selected_profile: Option<usize>,
    pub view_mode: ViewMode,
    pub path_inputs: PathInputs,
    pub validation_errors: ValidationErrors,
    pub run_history: Vec<RunRecord>,
    pub history_filter: String,
    pub grpc_client: Option<GrpcClient>,
    pub daemon_status: DaemonStatus,
    pub loading_state: LoadingState,
    pub memory_unit: MemoryUnit,
    pub memory_display_value: String,
}

#[derive(Debug, Clone, Default)]
pub struct PathInputs {
    pub allowed_input: String,
    pub denied_input: String,
}

#[derive(Debug, Clone, Default)]
pub struct ValidationErrors {
    pub fields: HashMap<String, String>,
}

#[derive(Debug, Clone)]
pub struct RunRecord {
    pub id: String,
    pub profile_name: String,
    pub start_time: String,
    pub duration: String,
    pub exit_code: i32,
    pub denied_capabilities: Vec<String>,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum ViewMode {
    ProfileList,
    ProfileEditor,
    RunHistory,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum DaemonStatus {
    Unknown,
    Connected,
    Offline,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum LoadingState {
    Idle,
    LoadingHistory,
    RunningSandbox,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum PathType {
    Allowed,
    Denied,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum MemoryUnit {
    Bytes,
    KB,
    MB,
    GB,
}

impl MemoryUnit {
    pub fn all() -> Vec<MemoryUnit> {
        vec![
            MemoryUnit::Bytes,
            MemoryUnit::KB,
            MemoryUnit::MB,
            MemoryUnit::GB,
        ]
    }

    pub fn to_bytes(&self, value: f64) -> u64 {
        match self {
            MemoryUnit::Bytes => value as u64,
            MemoryUnit::KB => (value * 1024.0) as u64,
            MemoryUnit::MB => (value * 1024.0 * 1024.0) as u64,
            MemoryUnit::GB => (value * 1024.0 * 1024.0 * 1024.0) as u64,
        }
    }

    pub fn from_bytes(&self, bytes: u64) -> f64 {
        match self {
            MemoryUnit::Bytes => bytes as f64,
            MemoryUnit::KB => bytes as f64 / 1024.0,
            MemoryUnit::MB => bytes as f64 / (1024.0 * 1024.0),
            MemoryUnit::GB => bytes as f64 / (1024.0 * 1024.0 * 1024.0),
        }
    }
}

impl std::fmt::Display for MemoryUnit {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            MemoryUnit::Bytes => write!(f, "Bytes"),
            MemoryUnit::KB => write!(f, "KB"),
            MemoryUnit::MB => write!(f, "MB"),
            MemoryUnit::GB => write!(f, "GB"),
        }
    }
}

#[derive(Debug)]
pub enum Message {
    ProfilesLoaded(Vec<Policy>),
    ProfileSelected(usize),
    CreateNewProfile,
    DeleteProfile(usize),
    DuplicateProfile(usize),
    NetworkCapabilityChanged(NetworkCapability),
    FilesystemCapabilityToggled(FilesystemCapability),
    PathInputChanged { path_type: PathType, value: String },
    AddPath { path_type: PathType },
    RemovePath { path_type: PathType, index: usize },
    CpuChanged(f32),
    MemoryBytesChanged(String),
    MemoryUnitChanged(MemoryUnit),
    MaxProcessesChanged(String),
    NameChanged(String),
    SaveProfile,
    SwitchView(ViewMode),
    HistoryFilterChanged(String),
    GrpcClientConnected(Result<GrpcClient, String>),
    RunSandbox { profile_idx: usize, command: String },
    RunSandboxResult(Result<String, String>, GrpcClient),
    StopSandbox { sandbox_id: String },
    StopSandboxResult(Result<(), String>, GrpcClient),
    HistoryLoaded(Result<Vec<RunRecord>, String>, GrpcClient),
}

impl Clone for Message {
    fn clone(&self) -> Self {
        match self {
            Message::ProfilesLoaded(p) => Message::ProfilesLoaded(p.clone()),
            Message::ProfileSelected(i) => Message::ProfileSelected(*i),
            Message::CreateNewProfile => Message::CreateNewProfile,
            Message::DeleteProfile(i) => Message::DeleteProfile(*i),
            Message::DuplicateProfile(i) => Message::DuplicateProfile(*i),
            Message::NetworkCapabilityChanged(c) => Message::NetworkCapabilityChanged(*c),
            Message::FilesystemCapabilityToggled(c) => Message::FilesystemCapabilityToggled(*c),
            Message::PathInputChanged { path_type, value } => Message::PathInputChanged {
                path_type: *path_type,
                value: value.clone(),
            },
            Message::AddPath { path_type } => Message::AddPath {
                path_type: *path_type,
            },
            Message::RemovePath { path_type, index } => Message::RemovePath {
                path_type: *path_type,
                index: *index,
            },
            Message::CpuChanged(f) => Message::CpuChanged(*f),
            Message::MemoryBytesChanged(s) => Message::MemoryBytesChanged(s.clone()),
            Message::MemoryUnitChanged(u) => Message::MemoryUnitChanged(*u),
            Message::MaxProcessesChanged(s) => Message::MaxProcessesChanged(s.clone()),
            Message::NameChanged(s) => Message::NameChanged(s.clone()),
            Message::SaveProfile => Message::SaveProfile,
            Message::SwitchView(v) => Message::SwitchView(*v),
            Message::HistoryFilterChanged(s) => Message::HistoryFilterChanged(s.clone()),
            Message::RunSandbox {
                profile_idx,
                command,
            } => Message::RunSandbox {
                profile_idx: *profile_idx,
                command: command.clone(),
            },
            Message::StopSandbox { sandbox_id } => Message::StopSandbox {
                sandbox_id: sandbox_id.clone(),
            },
            _ => panic!("Cannot clone Message with GrpcClient"),
        }
    }
}

impl HopsGui {
    pub fn new() -> (Self, Task<Message>) {
        let profiles = config::load_profiles().unwrap_or_default();
        (
            Self {
                profiles,
                selected_profile: None,
                view_mode: ViewMode::ProfileList,
                path_inputs: PathInputs::default(),
                validation_errors: ValidationErrors::default(),
                run_history: vec![],
                history_filter: String::new(),
                grpc_client: None,
                daemon_status: DaemonStatus::Unknown,
                loading_state: LoadingState::Idle,
                memory_unit: MemoryUnit::MB,
                memory_display_value: String::new(),
            },
            Task::perform(
                async {
                    match GrpcClient::connect().await {
                        Ok(client) => Ok(client),
                        Err(e) => Err(e.to_string()),
                    }
                },
                Message::GrpcClientConnected,
            ),
        )
    }

    pub fn title(&self) -> String {
        String::from("Hops - Profile Management")
    }

    pub fn update(&mut self, message: Message) -> Task<Message> {
        match message {
            Message::ProfilesLoaded(profiles) => {
                self.profiles = profiles;
            }
            Message::ProfileSelected(index) => {
                self.selected_profile = Some(index);
                self.view_mode = ViewMode::ProfileEditor;
                self.path_inputs = PathInputs::default();
                self.validation_errors = ValidationErrors::default();
                if let Some(profile) = self.profiles.get(index) {
                    if let Some(bytes) = profile.capabilities.resource_limits.memory_bytes {
                        self.memory_display_value = self.memory_unit.from_bytes(bytes).to_string();
                    } else {
                        self.memory_display_value = String::new();
                    }
                }
            }
            Message::CreateNewProfile => {
                let mut new_policy = Policy::default();
                new_policy.name = format!("profile-{}", self.profiles.len() + 1);
                self.profiles.push(new_policy);
                self.selected_profile = Some(self.profiles.len() - 1);
                self.view_mode = ViewMode::ProfileEditor;
                self.path_inputs = PathInputs::default();
                self.validation_errors = ValidationErrors::default();
                self.memory_display_value = String::new();
            }
            Message::DeleteProfile(index) => {
                if index < self.profiles.len() {
                    self.profiles.remove(index);
                    if let Some(selected) = self.selected_profile {
                        if selected == index {
                            self.selected_profile = None;
                            self.view_mode = ViewMode::ProfileList;
                        } else if selected > index {
                            self.selected_profile = Some(selected - 1);
                        }
                    }
                }
            }
            Message::DuplicateProfile(index) => {
                if let Some(profile) = self.profiles.get(index).cloned() {
                    let mut new_profile = profile;
                    new_profile.name = format!("{}-copy", new_profile.name);
                    self.profiles.push(new_profile);
                }
            }
            Message::NetworkCapabilityChanged(capability) => {
                if let Some(idx) = self.selected_profile {
                    if let Some(profile) = self.profiles.get_mut(idx) {
                        profile.capabilities.network = capability;
                    }
                }
            }
            Message::FilesystemCapabilityToggled(capability) => {
                if let Some(idx) = self.selected_profile {
                    if let Some(profile) = self.profiles.get_mut(idx) {
                        if profile.capabilities.filesystem.contains(&capability) {
                            profile.capabilities.filesystem.remove(&capability);
                        } else {
                            profile.capabilities.filesystem.insert(capability);
                        }
                    }
                }
            }
            Message::PathInputChanged { path_type, value } => match path_type {
                PathType::Allowed => self.path_inputs.allowed_input = value,
                PathType::Denied => self.path_inputs.denied_input = value,
            },
            Message::AddPath { path_type } => {
                let path = match path_type {
                    PathType::Allowed => &self.path_inputs.allowed_input,
                    PathType::Denied => &self.path_inputs.denied_input,
                };

                if path.trim().is_empty() {
                    let field_name = format!("{:?}_path", path_type);
                    self.validation_errors
                        .fields
                        .insert(field_name, "Path cannot be empty".to_string());
                } else {
                    let field_name = format!("{:?}_path", path_type);
                    self.validation_errors.fields.remove(&field_name);

                    if let Some(idx) = self.selected_profile {
                        if let Some(profile) = self.profiles.get_mut(idx) {
                            match path_type {
                                PathType::Allowed => {
                                    profile.capabilities.allowed_paths.push(path.clone());
                                    self.path_inputs.allowed_input.clear();
                                }
                                PathType::Denied => {
                                    profile.capabilities.denied_paths.push(path.clone());
                                    self.path_inputs.denied_input.clear();
                                }
                            }
                        }
                    }
                }
            }
            Message::RemovePath { path_type, index } => {
                if let Some(idx) = self.selected_profile {
                    if let Some(profile) = self.profiles.get_mut(idx) {
                        match path_type {
                            PathType::Allowed => {
                                if index < profile.capabilities.allowed_paths.len() {
                                    profile.capabilities.allowed_paths.remove(index);
                                }
                            }
                            PathType::Denied => {
                                if index < profile.capabilities.denied_paths.len() {
                                    profile.capabilities.denied_paths.remove(index);
                                }
                            }
                        }
                    }
                }
            }
            Message::CpuChanged(cpus) => {
                if let Some(idx) = self.selected_profile {
                    if let Some(profile) = self.profiles.get_mut(idx) {
                        profile.capabilities.resource_limits.cpus = Some(cpus as u32);
                    }
                }
            }
            Message::MemoryBytesChanged(value) => {
                self.memory_display_value = value.clone();
                if let Some(idx) = self.selected_profile {
                    if let Some(profile) = self.profiles.get_mut(idx) {
                        if let Ok(numeric_value) = value.parse::<f64>() {
                            let bytes = self.memory_unit.to_bytes(numeric_value);
                            profile.capabilities.resource_limits.memory_bytes = Some(bytes);
                            self.validation_errors.fields.remove("memory_bytes");
                        } else if value.is_empty() {
                            profile.capabilities.resource_limits.memory_bytes = None;
                            self.validation_errors.fields.remove("memory_bytes");
                        } else {
                            self.validation_errors.fields.insert(
                                "memory_bytes".to_string(),
                                "Must be a number".to_string(),
                            );
                        }
                    }
                }
            }
            Message::MemoryUnitChanged(unit) => {
                self.memory_unit = unit;
                if let Some(idx) = self.selected_profile {
                    if let Some(profile) = self.profiles.get(idx) {
                        if let Some(bytes) = profile.capabilities.resource_limits.memory_bytes {
                            self.memory_display_value = unit.from_bytes(bytes).to_string();
                        }
                    }
                }
            }
            Message::MaxProcessesChanged(value) => {
                if let Some(idx) = self.selected_profile {
                    if let Some(profile) = self.profiles.get_mut(idx) {
                        if let Ok(max) = value.parse::<u32>() {
                            profile.capabilities.resource_limits.max_processes = Some(max);
                            self.validation_errors.fields.remove("max_processes");
                        } else {
                            self.validation_errors.fields.insert(
                                "max_processes".to_string(),
                                "Must be a positive number".to_string(),
                            );
                        }
                    }
                }
            }
            Message::NameChanged(name) => {
                if let Some(idx) = self.selected_profile {
                    if let Some(profile) = self.profiles.get_mut(idx) {
                        if name.trim().is_empty() {
                            self.validation_errors
                                .fields
                                .insert("name".to_string(), "Name cannot be empty".to_string());
                        } else {
                            self.validation_errors.fields.remove("name");
                            profile.name = name;
                        }
                    }
                }
            }
            Message::SaveProfile => {
                if self.validation_errors.fields.is_empty() {
                    if let Some(idx) = self.selected_profile {
                        if let Some(profile) = self.profiles.get(idx) {
                            let _ = config::save_profile(&profile.name, profile);
                        }
                    }
                }
            }
            Message::SwitchView(mode) => {
                self.view_mode = mode;
                if mode == ViewMode::ProfileList {
                    self.selected_profile = None;
                } else if mode == ViewMode::RunHistory && self.grpc_client.is_some() {
                    self.loading_state = LoadingState::LoadingHistory;
                    let mut client = self.grpc_client.take().unwrap();
                    return Task::perform(
                        async move {
                            let result = client.list_sandboxes(true).await;
                            (client, result)
                        },
                        move |(client, result)| match result {
                            Ok(sandboxes) => {
                                let records: Vec<RunRecord> = sandboxes
                                    .into_iter()
                                    .map(|s| RunRecord {
                                        id: s.sandbox_id.clone(),
                                        profile_name: "unknown".to_string(),
                                        start_time: format_timestamp(0),
                                        duration: "unknown".to_string(),
                                        exit_code: 0,
                                        denied_capabilities: vec![],
                                    })
                                    .collect();
                                Message::HistoryLoaded(Ok(records), client)
                            }
                            Err(e) => Message::HistoryLoaded(Err(e.to_string()), client),
                        },
                    );
                }
            }
            Message::HistoryFilterChanged(filter) => {
                self.history_filter = filter;
            }
            Message::GrpcClientConnected(result) => match result {
                Ok(client) => {
                    self.grpc_client = Some(client);
                    self.daemon_status = DaemonStatus::Connected;
                }
                Err(_) => {
                    self.daemon_status = DaemonStatus::Offline;
                }
            },
            Message::RunSandbox {
                profile_idx,
                command,
            } => {
                if let Some(profile) = self.profiles.get(profile_idx) {
                    if let Some(mut client) = self.grpc_client.take() {
                        self.loading_state = LoadingState::RunningSandbox;
                        let policy = profile.clone();
                        let cmd_parts: Vec<String> =
                            command.split_whitespace().map(|s| s.to_string()).collect();
                        return Task::perform(
                            async move {
                                let result = client
                                    .run_sandbox(&policy, cmd_parts, Some("/".to_string()))
                                    .await;
                                (client, result)
                            },
                            |(client, result)| {
                                Message::RunSandboxResult(
                                    result.map(|r| r.sandbox_id).map_err(|e| e.to_string()),
                                    client,
                                )
                            },
                        );
                    }
                }
            }
            Message::RunSandboxResult(result, client) => {
                self.grpc_client = Some(client);
                self.loading_state = LoadingState::Idle;
                match result {
                    Ok(_sandbox_id) => {}
                    Err(_) => {}
                }
            }
            Message::StopSandbox { sandbox_id } => {
                if let Some(mut client) = self.grpc_client.take() {
                    return Task::perform(
                        async move {
                            let result = client.stop_sandbox(sandbox_id, false).await;
                            (client, result)
                        },
                        |(client, result)| {
                            Message::StopSandboxResult(
                                result.map(|_| ()).map_err(|e| e.to_string()),
                                client,
                            )
                        },
                    );
                }
            }
            Message::StopSandboxResult(result, client) => {
                self.grpc_client = Some(client);
                match result {
                    Ok(_) => {}
                    Err(_) => {}
                }
            }
            Message::HistoryLoaded(result, client) => {
                self.grpc_client = Some(client);
                self.loading_state = LoadingState::Idle;
                match result {
                    Ok(history) => {
                        self.run_history = history;
                    }
                    Err(_) => {}
                }
            }
        }
        Task::none()
    }

    pub fn view(&self) -> Element<'_, Message> {
        let sidebar = self.view_sidebar();

        let content = match self.view_mode {
            ViewMode::ProfileList => profile_list::view(&self.profiles),
            ViewMode::ProfileEditor => {
                if let Some(idx) = self.selected_profile {
                    if let Some(profile) = self.profiles.get(idx) {
                        profile_editor::view(
                            profile,
                            &self.path_inputs,
                            &self.validation_errors,
                            &self.memory_unit,
                            &self.memory_display_value,
                        )
                    } else {
                        profile_list::view(&self.profiles)
                    }
                } else {
                    profile_list::view(&self.profiles)
                }
            }
            ViewMode::RunHistory => run_history::view(&self.run_history, &self.history_filter),
        };

        row![sidebar, content]
            .width(Length::Fill)
            .height(Length::Fill)
            .into()
    }

    fn view_sidebar(&self) -> Element<'_, Message> {
        use iced::widget::{button, column, text};

        let title = text("HOPS").size(28);

        let status_text = match self.daemon_status {
            DaemonStatus::Connected => text("● Connected").style(|_theme: &Theme| {
                iced::widget::text::Style {
                    color: Some(iced::Color::from_rgb(0.0, 0.8, 0.0)),
                }
            }),
            DaemonStatus::Offline => text("● Offline").style(|_theme: &Theme| {
                iced::widget::text::Style {
                    color: Some(iced::Color::from_rgb(0.8, 0.0, 0.0)),
                }
            }),
            DaemonStatus::Unknown => text("● Unknown").style(|_theme: &Theme| {
                iced::widget::text::Style {
                    color: Some(iced::Color::from_rgb(0.6, 0.6, 0.0)),
                }
            }),
        };

        let profiles_btn = button(text("📋 Profiles"))
            .on_press(Message::SwitchView(ViewMode::ProfileList))
            .width(Length::Fill)
            .padding(12)
            .style(move |_theme, status| {
                let is_active = self.view_mode == ViewMode::ProfileList;
                let base_color = if is_active {
                    iced::Color::from_rgb(0.25, 0.45, 0.65)
                } else {
                    iced::Color::from_rgb(0.18, 0.18, 0.2)
                };
                let hover_color = if is_active {
                    iced::Color::from_rgb(0.3, 0.5, 0.7)
                } else {
                    iced::Color::from_rgb(0.22, 0.22, 0.25)
                };
                iced::widget::button::Style {
                    background: Some(iced::Background::Color(
                        if matches!(status, iced::widget::button::Status::Hovered) {
                            hover_color
                        } else {
                            base_color
                        }
                    )),
                    text_color: iced::Color::WHITE,
                    border: iced::Border {
                        color: iced::Color::from_rgb(0.35, 0.35, 0.4),
                        width: 1.0,
                        radius: 4.0.into(),
                    },
                    ..Default::default()
                }
            });

        let history_btn = button(text("📜 Run History"))
            .on_press(Message::SwitchView(ViewMode::RunHistory))
            .width(Length::Fill)
            .padding(12)
            .style(move |_theme, status| {
                let is_active = self.view_mode == ViewMode::RunHistory;
                let base_color = if is_active {
                    iced::Color::from_rgb(0.25, 0.45, 0.65)
                } else {
                    iced::Color::from_rgb(0.18, 0.18, 0.2)
                };
                let hover_color = if is_active {
                    iced::Color::from_rgb(0.3, 0.5, 0.7)
                } else {
                    iced::Color::from_rgb(0.22, 0.22, 0.25)
                };
                iced::widget::button::Style {
                    background: Some(iced::Background::Color(
                        if matches!(status, iced::widget::button::Status::Hovered) {
                            hover_color
                        } else {
                            base_color
                        }
                    )),
                    text_color: iced::Color::WHITE,
                    border: iced::Border {
                        color: iced::Color::from_rgb(0.35, 0.35, 0.4),
                        width: 1.0,
                        radius: 4.0.into(),
                    },
                    ..Default::default()
                }
            });

        let sidebar_content = column![title, status_text, profiles_btn, history_btn]
            .spacing(15)
            .padding(20)
            .width(200);

        container(sidebar_content)
            .width(Length::Fixed(200.0))
            .height(Length::Fill)
            .style(|_theme: &Theme| container::Style {
                background: Some(iced::Background::Color(iced::Color::from_rgb(
                    0.12, 0.12, 0.12,
                ))),
                border: iced::Border {
                    color: iced::Color::from_rgb(0.25, 0.25, 0.25),
                    width: 0.0,
                    radius: 0.0.into(),
                },
                ..Default::default()
            })
            .into()
    }
}

fn format_timestamp(unix_seconds: i64) -> String {
    if unix_seconds == 0 {
        return "N/A".to_string();
    }
    "timestamp".to_string()
}
