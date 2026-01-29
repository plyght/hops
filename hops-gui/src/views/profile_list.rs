use crate::app::Message;
use crate::models::policy::Policy;
use iced::widget::{button, column, container, row, scrollable, text, Column};
use iced::{Border, Color, Element, Length};

pub fn view<'a>(profiles: &'a [Policy]) -> Element<'a, Message> {
    let title = text("PROFILES").size(32);

    let profile_list: Column<Message> =
        profiles
            .iter()
            .enumerate()
            .fold(Column::new().spacing(15), |col, (idx, profile)| {
                let profile_header = text(&profile.name).size(18);

                let network_badge = text(format!("Network: {:?}", profile.capabilities.network))
                    .size(12)
                    .color(Color::from_rgb(0.6, 0.6, 0.6));

                let filesystem_perms: Vec<String> = profile
                    .capabilities
                    .filesystem
                    .iter()
                    .map(|cap| format!("{:?}", cap))
                    .collect();
                let filesystem_summary = text(format!(
                    "Filesystem: {}",
                    if filesystem_perms.is_empty() {
                        "None".to_string()
                    } else {
                        filesystem_perms.join(", ")
                    }
                ))
                .size(12)
                .color(Color::from_rgb(0.6, 0.6, 0.6));

                let paths_summary = text(format!(
                    "Paths: {} allowed, {} denied",
                    profile.capabilities.allowed_paths.len(),
                    profile.capabilities.denied_paths.len()
                ))
                .size(12)
                .color(Color::from_rgb(0.6, 0.6, 0.6));

                let resources_summary = text(format!(
                    "Resources: {} CPUs, {} memory, {} max processes",
                    profile
                        .capabilities
                        .resource_limits
                        .cpus
                        .map(|c| c.to_string())
                        .unwrap_or_else(|| "unlimited".to_string()),
                    profile
                        .capabilities
                        .resource_limits
                        .memory_bytes
                        .map(|m| format!("{} bytes", m))
                        .unwrap_or_else(|| "unlimited".to_string()),
                    profile
                        .capabilities
                        .resource_limits
                        .max_processes
                        .map(|p| p.to_string())
                        .unwrap_or_else(|| "unlimited".to_string())
                ))
                .size(12)
                .color(Color::from_rgb(0.6, 0.6, 0.6));

                let info_column = column![
                    profile_header,
                    network_badge,
                    filesystem_summary,
                    paths_summary,
                    resources_summary,
                ]
                .spacing(4)
                .width(Length::Fill);

                let edit_btn = button(text("Edit").size(14))
                    .on_press(Message::ProfileSelected(idx))
                    .padding(8)
                    .style(|_theme, _status| button::Style {
                        background: Some(iced::Background::Color(Color::from_rgb(0.2, 0.5, 0.8))),
                        text_color: Color::WHITE,
                        border: Border {
                            color: Color::from_rgb(0.3, 0.6, 0.9),
                            width: 1.0,
                            radius: 2.0.into(),
                        },
                        ..Default::default()
                    });

                let duplicate_btn = button(text("Duplicate").size(14))
                    .on_press(Message::DuplicateProfile(idx))
                    .padding(8);

                let delete_btn = button(text("Delete").size(14))
                    .on_press(Message::DeleteProfile(idx))
                    .padding(8)
                    .style(|_theme, _status| button::Style {
                        background: Some(iced::Background::Color(Color::from_rgb(0.8, 0.2, 0.2))),
                        text_color: Color::WHITE,
                        border: Border {
                            color: Color::from_rgb(0.9, 0.3, 0.3),
                            width: 1.0,
                            radius: 2.0.into(),
                        },
                        ..Default::default()
                    });

                let button_row = row![edit_btn, duplicate_btn, delete_btn].spacing(10);

                let profile_card = container(
                    column![row![info_column, button_row].spacing(15)]
                        .spacing(10)
                        .padding(15),
                )
                .width(Length::Fill)
                .style(|_theme| container::Style {
                    background: Some(iced::Background::Color(Color::from_rgb(0.15, 0.15, 0.15))),
                    border: Border {
                        color: Color::from_rgb(0.3, 0.3, 0.3),
                        width: 1.0,
                        radius: 2.0.into(),
                    },
                    ..Default::default()
                });

                col.push(profile_card)
            });

    let new_profile_btn = button(
        text("+ CREATE NEW PROFILE")
            .width(Length::Fill)
            .align_x(iced::alignment::Horizontal::Center),
    )
    .on_press(Message::CreateNewProfile)
    .width(Length::Fill)
    .padding(15)
    .style(|_theme, _status| button::Style {
        background: Some(iced::Background::Color(Color::from_rgb(0.2, 0.6, 0.2))),
        text_color: Color::WHITE,
        border: Border {
            color: Color::from_rgb(0.3, 0.7, 0.3),
            width: 1.0,
            radius: 2.0.into(),
        },
        ..Default::default()
    });

    let empty_state = if profiles.is_empty() {
        column![
            text("No profiles yet. Create your first profile to get started.")
                .size(16)
                .color(Color::from_rgb(0.6, 0.6, 0.6))
        ]
        .spacing(10)
    } else {
        column![]
    };

    let content = column![
        title,
        empty_state,
        scrollable(profile_list),
        new_profile_btn,
    ]
    .spacing(20)
    .padding(30);

    container(content)
        .width(Length::Fill)
        .height(Length::Fill)
        .into()
}
