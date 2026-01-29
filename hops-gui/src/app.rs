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
pub enum PathType {
    Allowed,
    Denied,
}

#[derive(Debug, Clone)]
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
    MaxProcessesChanged(String),
    NameChanged(String),
    SaveProfile,
    SwitchView(ViewMode),
    HistoryFilterChanged(String),
}

impl HopsGui {
    pub fn new() -> (Self, Task<Message>) {
        let profiles = config::load_profiles().unwrap_or_default();
        let run_history = vec![
            RunRecord {
                id: "sbx_a1b2c3d4".to_string(),
                profile_name: "default".to_string(),
                start_time: "2026-01-29 14:23:15".to_string(),
                duration: "2m 34s".to_string(),
                exit_code: 0,
                denied_capabilities: vec![],
            },
            RunRecord {
                id: "sbx_e5f6g7h8".to_string(),
                profile_name: "restrictive".to_string(),
                start_time: "2026-01-29 13:45:22".to_string(),
                duration: "0m 12s".to_string(),
                exit_code: 1,
                denied_capabilities: vec![
                    "Network: Attempted outbound connection to 8.8.8.8:443".to_string(),
                    "Filesystem: Write denied to /etc/hosts".to_string(),
                ],
            },
            RunRecord {
                id: "sbx_i9j0k1l2".to_string(),
                profile_name: "build".to_string(),
                start_time: "2026-01-29 12:10:05".to_string(),
                duration: "15m 48s".to_string(),
                exit_code: 0,
                denied_capabilities: vec![],
            },
        ];
        (
            Self {
                profiles,
                selected_profile: None,
                view_mode: ViewMode::ProfileList,
                path_inputs: PathInputs::default(),
                validation_errors: ValidationErrors::default(),
                run_history,
                history_filter: String::new(),
            },
            Task::none(),
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
            }
            Message::CreateNewProfile => {
                let mut new_policy = Policy::default();
                new_policy.name = format!("profile-{}", self.profiles.len() + 1);
                self.profiles.push(new_policy);
                self.selected_profile = Some(self.profiles.len() - 1);
                self.view_mode = ViewMode::ProfileEditor;
                self.path_inputs = PathInputs::default();
                self.validation_errors = ValidationErrors::default();
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
                if let Some(idx) = self.selected_profile {
                    if let Some(profile) = self.profiles.get_mut(idx) {
                        if let Ok(bytes) = value.parse::<u64>() {
                            profile.capabilities.resource_limits.memory_bytes = Some(bytes);
                            self.validation_errors.fields.remove("memory_bytes");
                        } else {
                            self.validation_errors.fields.insert(
                                "memory_bytes".to_string(),
                                "Must be a number (bytes)".to_string(),
                            );
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
                }
            }
            Message::HistoryFilterChanged(filter) => {
                self.history_filter = filter;
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
                        profile_editor::view(profile, &self.path_inputs, &self.validation_errors)
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

        let profiles_btn = button(text("Profiles"))
            .on_press(Message::SwitchView(ViewMode::ProfileList))
            .width(Length::Fill);

        let history_btn = button(text("Run History"))
            .on_press(Message::SwitchView(ViewMode::RunHistory))
            .width(Length::Fill);

        let sidebar_content = column![title, profiles_btn, history_btn]
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
