use crate::models::policy::Policy;
use crate::utils::config;
use crate::views::{profile_editor, profile_list, run_history};
use iced::{widget::container, Application, Command, Element, Length, Theme};

pub struct HopsGui {
    pub profiles: Vec<Policy>,
    pub selected_profile: Option<usize>,
    pub view_mode: ViewMode,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum ViewMode {
    ProfileList,
    ProfileEditor,
    RunHistory,
}

#[derive(Debug, Clone)]
pub enum Message {
    ProfilesLoaded(Vec<Policy>),
    ProfileSelected(usize),
    CreateNewProfile,
    NetworkCapabilityChanged(String),
    FilesystemReadAdded(String),
    FilesystemWriteAdded(String),
    FilesystemExecuteAdded(String),
    CpuChanged(f32),
    MemoryChanged(String),
    MaxProcessesChanged(u32),
    SaveProfile,
    SwitchView(ViewMode),
}

impl Application for HopsGui {
    type Message = Message;
    type Theme = Theme;
    type Executor = iced::executor::Default;
    type Flags = ();

    fn new(_flags: Self::Flags) -> (Self, Command<Self::Message>) {
        let profiles = config::load_profiles().unwrap_or_default();
        (
            Self {
                profiles,
                selected_profile: None,
                view_mode: ViewMode::ProfileList,
            },
            Command::none(),
        )
    }

    fn title(&self) -> String {
        String::from("Hops - Profile Management")
    }

    fn update(&mut self, message: Self::Message) -> Command<Self::Message> {
        match message {
            Message::ProfilesLoaded(profiles) => {
                self.profiles = profiles;
            }
            Message::ProfileSelected(index) => {
                self.selected_profile = Some(index);
                self.view_mode = ViewMode::ProfileEditor;
            }
            Message::CreateNewProfile => {
                let new_policy = Policy::default();
                self.profiles.push(new_policy);
                self.selected_profile = Some(self.profiles.len() - 1);
                self.view_mode = ViewMode::ProfileEditor;
            }
            Message::NetworkCapabilityChanged(value) => {
                if let Some(idx) = self.selected_profile {
                    if let Some(profile) = self.profiles.get_mut(idx) {
                        profile.capabilities.network = value;
                    }
                }
            }
            Message::FilesystemReadAdded(path) => {
                if let Some(idx) = self.selected_profile {
                    if let Some(profile) = self.profiles.get_mut(idx) {
                        profile.capabilities.filesystem.read.push(path);
                    }
                }
            }
            Message::FilesystemWriteAdded(path) => {
                if let Some(idx) = self.selected_profile {
                    if let Some(profile) = self.profiles.get_mut(idx) {
                        profile.capabilities.filesystem.write.push(path);
                    }
                }
            }
            Message::FilesystemExecuteAdded(path) => {
                if let Some(idx) = self.selected_profile {
                    if let Some(profile) = self.profiles.get_mut(idx) {
                        profile.capabilities.filesystem.execute.push(path);
                    }
                }
            }
            Message::CpuChanged(cpus) => {
                if let Some(idx) = self.selected_profile {
                    if let Some(profile) = self.profiles.get_mut(idx) {
                        profile.resources.cpus = cpus as u32;
                    }
                }
            }
            Message::MemoryChanged(memory) => {
                if let Some(idx) = self.selected_profile {
                    if let Some(profile) = self.profiles.get_mut(idx) {
                        profile.resources.memory = memory;
                    }
                }
            }
            Message::MaxProcessesChanged(max) => {
                if let Some(idx) = self.selected_profile {
                    if let Some(profile) = self.profiles.get_mut(idx) {
                        profile.resources.max_processes = max;
                    }
                }
            }
            Message::SaveProfile => {
                if let Some(idx) = self.selected_profile {
                    if let Some(profile) = self.profiles.get(idx) {
                        let _ = config::save_profile(&profile.name, profile);
                    }
                }
            }
            Message::SwitchView(mode) => {
                self.view_mode = mode;
            }
        }
        Command::none()
    }

    fn view(&self) -> Element<Self::Message> {
        let content = match self.view_mode {
            ViewMode::ProfileList => profile_list::view(&self.profiles),
            ViewMode::ProfileEditor => {
                if let Some(idx) = self.selected_profile {
                    if let Some(profile) = self.profiles.get(idx) {
                        profile_editor::view(profile)
                    } else {
                        profile_list::view(&self.profiles)
                    }
                } else {
                    profile_list::view(&self.profiles)
                }
            }
            ViewMode::RunHistory => run_history::view(),
        };

        container(content)
            .width(Length::Fill)
            .height(Length::Fill)
            .center_x(Length::Fill)
            .center_y(Length::Fill)
            .into()
    }
}
