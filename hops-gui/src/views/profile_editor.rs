use crate::app::{MemoryUnit, Message, PathInputs, PathType, ValidationErrors};
use crate::models::capability::{FilesystemCapability, NetworkCapability};
use crate::models::policy::Policy;
use iced::widget::{
    button, checkbox, column, container, pick_list, progress_bar, row, scrollable, slider, text,
    text_input, tooltip, Column,
};
use iced::{Border, Color, Element, Length};

const NETWORK_OPTIONS: &[NetworkCapability] = &[
    NetworkCapability::Disabled,
    NetworkCapability::Loopback,
    NetworkCapability::Outbound,
    NetworkCapability::Full,
];

pub fn view<'a>(
    policy: &'a Policy,
    path_inputs: &'a PathInputs,
    validation_errors: &'a ValidationErrors,
    memory_unit: &'a MemoryUnit,
    memory_display_value: &'a str,
) -> Element<'a, Message> {
    let title = text(format!("PROFILE: {}", policy.name.to_uppercase())).size(32);

    let name_section = column![
        text("Profile Name").size(14),
        text_input("Enter profile name", &policy.name)
            .on_input(Message::NameChanged)
            .padding(10)
            .width(Length::Fill),
        if let Some(error) = validation_errors.fields.get("name") {
            container(
                row![
                    text("⚠").size(14).color(Color::from_rgb(1.0, 0.7, 0.0)),
                    text(error).size(12).color(Color::from_rgb(1.0, 0.95, 0.95))
                ]
                .spacing(8)
                .padding(8),
            )
            .style(|_theme| container::Style {
                background: Some(iced::Background::Color(Color::from_rgb(0.6, 0.15, 0.15))),
                border: Border {
                    color: Color::from_rgb(0.8, 0.3, 0.3),
                    width: 1.0,
                    radius: 4.0.into(),
                },
                ..Default::default()
            })
        } else {
            container(text(""))
        }
    ]
    .spacing(8);

    let network_display: Vec<String> = NETWORK_OPTIONS.iter().map(|c| format!("{:?}", c)).collect();
    let current_display = format!("{:?}", policy.capabilities.network);

    let network_section = column![
        text("NETWORK CAPABILITY").size(14),
        tooltip(
            pick_list(network_display, Some(current_display), |selected| {
                let capability = match selected.as_str() {
                    "Loopback" => NetworkCapability::Loopback,
                    "Outbound" => NetworkCapability::Outbound,
                    "Full" => NetworkCapability::Full,
                    _ => NetworkCapability::Disabled,
                };
                Message::NetworkCapabilityChanged(capability)
            })
            .padding(10)
            .width(Length::Fill),
            "Disabled: No network • Loopback: localhost only • Outbound: Can connect out • Full: Bidirectional access",
            tooltip::Position::Top
        ),
        text(match policy.capabilities.network {
            NetworkCapability::Disabled => "All network access blocked",
            NetworkCapability::Loopback => "Only localhost connections allowed",
            NetworkCapability::Outbound => "Outbound connections allowed",
            NetworkCapability::Full => "Full network access",
        })
        .size(12)
        .color(Color::from_rgb(0.6, 0.6, 0.6))
    ]
    .spacing(8);

    let filesystem_checkboxes = column![
        text("FILESYSTEM PERMISSIONS").size(14),
        checkbox(
            "Read",
            policy
                .capabilities
                .filesystem
                .contains(&FilesystemCapability::Read)
        )
        .on_toggle(|_| Message::FilesystemCapabilityToggled(FilesystemCapability::Read)),
        checkbox(
            "Write",
            policy
                .capabilities
                .filesystem
                .contains(&FilesystemCapability::Write)
        )
        .on_toggle(|_| Message::FilesystemCapabilityToggled(FilesystemCapability::Write)),
        checkbox(
            "Execute",
            policy
                .capabilities
                .filesystem
                .contains(&FilesystemCapability::Execute)
        )
        .on_toggle(|_| Message::FilesystemCapabilityToggled(FilesystemCapability::Execute)),
    ]
    .spacing(10);

    let allowed_paths_section = build_path_section(
        "ALLOWED PATHS",
        &policy.capabilities.allowed_paths,
        &path_inputs.allowed_input,
        PathType::Allowed,
        validation_errors,
    );

    let denied_paths_section = build_path_section(
        "DENIED PATHS",
        &policy.capabilities.denied_paths,
        &path_inputs.denied_input,
        PathType::Denied,
        validation_errors,
    );

    let cpu_value = policy.capabilities.resource_limits.cpus.unwrap_or(2);
    let cpu_slider = slider(1.0..=16.0, cpu_value as f32, Message::CpuChanged).width(Length::Fill);

    let max_processes_value = policy
        .capabilities
        .resource_limits
        .max_processes
        .map(|p| p.to_string())
        .unwrap_or_default();

    let memory_unit_options: Vec<String> =
        MemoryUnit::all().iter().map(|u| u.to_string()).collect();
    let current_unit = memory_unit.to_string();

    let resources_section = column![
        text("RESOURCE LIMITS").size(18),
        column![
            row![
                text("CPU Cores:").width(Length::Fixed(140.0)),
                text(format!("{} / 16", cpu_value)).width(Length::Fixed(80.0))
            ]
            .spacing(10),
            tooltip(
                cpu_slider,
                "Number of CPU cores allocated to the sandbox. More cores = better performance but higher resource usage",
                tooltip::Position::Top
            ),
            progress_bar(0.0..=16.0, cpu_value as f32)
                .height(8)
                .style(|_theme| progress_bar::Style {
                    background: iced::Background::Color(Color::from_rgb(0.2, 0.2, 0.2)),
                    bar: iced::Background::Color(Color::from_rgb(0.3, 0.6, 0.9)),
                    border: Border {
                        color: Color::from_rgb(0.4, 0.4, 0.4),
                        width: 1.0,
                        radius: 2.0.into(),
                    },
                }),
        ]
        .spacing(8),
        column![
            text("Memory").size(14),
            tooltip(
                row![
                    text_input("e.g., 512", memory_display_value)
                        .on_input(Message::MemoryBytesChanged)
                        .padding(10)
                        .width(Length::FillPortion(3)),
                    pick_list(memory_unit_options, Some(current_unit), |selected| {
                        match selected.as_str() {
                            "KB" => Message::MemoryUnitChanged(MemoryUnit::KB),
                            "MB" => Message::MemoryUnitChanged(MemoryUnit::MB),
                            "GB" => Message::MemoryUnitChanged(MemoryUnit::GB),
                            _ => Message::MemoryUnitChanged(MemoryUnit::Bytes),
                        }
                    })
                    .padding(10)
                    .width(Length::FillPortion(1)),
                ]
                .spacing(10),
                "Maximum memory the sandbox can use. Enter a numeric value and select the unit (Bytes, KB, MB, GB)",
                tooltip::Position::Top
            ),
            {
                if let Some(bytes) = policy.capabilities.resource_limits.memory_bytes {
                    let max_bytes = 32.0 * 1024.0 * 1024.0 * 1024.0;
                    let percentage = (bytes as f64 / max_bytes * 100.0).min(100.0);
                    column![
                        progress_bar(0.0..=100.0, percentage as f32)
                            .height(8)
                            .style(|_theme| progress_bar::Style {
                                background: iced::Background::Color(Color::from_rgb(0.2, 0.2, 0.2)),
                                bar: iced::Background::Color(Color::from_rgb(0.2, 0.7, 0.4)),
                                border: Border {
                                    color: Color::from_rgb(0.4, 0.4, 0.4),
                                    width: 1.0,
                                    radius: 2.0.into(),
                                },
                            }),
                        text(format!("{}% of 32GB", percentage as u32))
                            .size(10)
                            .color(Color::from_rgb(0.6, 0.6, 0.6))
                    ]
                    .spacing(4)
                } else {
                    column![]
                }
            },
            if let Some(error) = validation_errors.fields.get("memory_bytes") {
                container(
                    row![
                        text("⚠").size(14).color(Color::from_rgb(1.0, 0.7, 0.0)),
                        text(error).size(12).color(Color::from_rgb(1.0, 0.95, 0.95))
                    ]
                    .spacing(8)
                    .padding(8)
                )
                .style(|_theme| container::Style {
                    background: Some(iced::Background::Color(Color::from_rgb(0.6, 0.15, 0.15))),
                    border: Border {
                        color: Color::from_rgb(0.8, 0.3, 0.3),
                        width: 1.0,
                        radius: 4.0.into(),
                    },
                    ..Default::default()
                })
            } else {
                container(text(""))
            }
        ]
        .spacing(8),
        column![
            text("Max Processes").size(14),
            tooltip(
                text_input("Maximum number of processes", &max_processes_value)
                    .on_input(Message::MaxProcessesChanged)
                    .padding(10)
                    .width(Length::Fill),
                "Maximum number of concurrent processes allowed in the sandbox. Limits fork bombs and resource exhaustion",
                tooltip::Position::Top
            ),
            if let Some(error) = validation_errors.fields.get("max_processes") {
                container(
                    row![
                        text("⚠").size(14).color(Color::from_rgb(1.0, 0.7, 0.0)),
                        text(error).size(12).color(Color::from_rgb(1.0, 0.95, 0.95))
                    ]
                    .spacing(8)
                    .padding(8)
                )
                .style(|_theme| container::Style {
                    background: Some(iced::Background::Color(Color::from_rgb(0.6, 0.15, 0.15))),
                    border: Border {
                        color: Color::from_rgb(0.8, 0.3, 0.3),
                        width: 1.0,
                        radius: 4.0.into(),
                    },
                    ..Default::default()
                })
            } else {
                container(text(""))
            }
        ]
        .spacing(8),
    ]
    .spacing(20);

    let shortcut_hint = if cfg!(target_os = "macos") {
        "Save profile (⌘S)"
    } else {
        "Save profile (Ctrl+S)"
    };

    let save_button = tooltip(
        button(
            text("💾 SAVE PROFILE")
                .width(Length::Fill)
                .align_x(iced::alignment::Horizontal::Center),
        )
        .on_press(Message::SaveProfile)
        .width(Length::Fill)
        .padding(14)
        .style(|_theme, status| {
            let base_color = Color::from_rgb(0.2, 0.6, 0.2);
            let hover_color = Color::from_rgb(0.25, 0.65, 0.25);
            button::Style {
                background: Some(iced::Background::Color(
                    if matches!(status, button::Status::Hovered) {
                        hover_color
                    } else {
                        base_color
                    },
                )),
                text_color: Color::WHITE,
                border: Border {
                    color: Color::from_rgb(0.3, 0.7, 0.3),
                    width: 1.0,
                    radius: 6.0.into(),
                },
                shadow: if matches!(status, button::Status::Hovered) {
                    iced::Shadow {
                        color: Color::from_rgba(0.2, 0.6, 0.2, 0.4),
                        offset: iced::Vector::new(0.0, 2.0),
                        blur_radius: 10.0,
                    }
                } else {
                    iced::Shadow::default()
                },
                ..Default::default()
            }
        }),
        shortcut_hint,
        tooltip::Position::Top,
    );

    let back_button = button(
        text("← BACK")
            .width(Length::Fill)
            .align_x(iced::alignment::Horizontal::Center),
    )
    .on_press(Message::SwitchView(crate::app::ViewMode::ProfileList))
    .width(Length::Fill)
    .padding(14)
    .style(|_theme, status| {
        let base_color = Color::from_rgb(0.4, 0.4, 0.45);
        let hover_color = Color::from_rgb(0.45, 0.45, 0.5);
        button::Style {
            background: Some(iced::Background::Color(
                if matches!(status, button::Status::Hovered) {
                    hover_color
                } else {
                    base_color
                },
            )),
            text_color: Color::WHITE,
            border: Border {
                color: Color::from_rgb(0.5, 0.5, 0.55),
                width: 1.0,
                radius: 6.0.into(),
            },
            shadow: if matches!(status, button::Status::Hovered) {
                iced::Shadow {
                    color: Color::from_rgba(0.4, 0.4, 0.45, 0.4),
                    offset: iced::Vector::new(0.0, 2.0),
                    blur_radius: 8.0,
                }
            } else {
                iced::Shadow::default()
            },
            ..Default::default()
        }
    });

    let content = column![
        title,
        name_section,
        network_section,
        filesystem_checkboxes,
        allowed_paths_section,
        denied_paths_section,
        resources_section,
        row![back_button, save_button].spacing(10),
    ]
    .spacing(30)
    .padding(30);

    container(scrollable(content))
        .width(Length::Fill)
        .height(Length::Fill)
        .into()
}

fn build_path_section<'a>(
    title: &'a str,
    paths: &'a [String],
    input_value: &'a str,
    path_type: PathType,
    validation_errors: &'a ValidationErrors,
) -> Element<'a, Message> {
    let path_list: Column<Message> =
        paths
            .iter()
            .enumerate()
            .fold(Column::new().spacing(8), |col, (idx, path)| {
                col.push(
                    row![
                        text(path).width(Length::Fill),
                        button(text("×").size(16))
                            .on_press(Message::RemovePath {
                                path_type,
                                index: idx
                            })
                            .padding(8)
                            .style(|_theme, _status| button::Style {
                                background: Some(iced::Background::Color(Color::from_rgb(
                                    0.8, 0.2, 0.2,
                                ))),
                                text_color: Color::WHITE,
                                border: Border {
                                    color: Color::from_rgb(0.9, 0.3, 0.3),
                                    width: 1.0,
                                    radius: 2.0.into(),
                                },
                                ..Default::default()
                            }),
                    ]
                    .spacing(10)
                    .padding(8),
                )
            });

    let add_input = row![
        text_input("Enter path", input_value)
            .on_input(move |value| Message::PathInputChanged { path_type, value })
            .padding(10)
            .width(Length::Fill),
        button(text("+").size(20))
            .on_press(Message::AddPath { path_type })
            .padding([8, 16])
            .style(|_theme, _status| button::Style {
                background: Some(iced::Background::Color(Color::from_rgb(0.2, 0.5, 0.8))),
                text_color: Color::WHITE,
                border: Border {
                    color: Color::from_rgb(0.3, 0.6, 0.9),
                    width: 1.0,
                    radius: 2.0.into(),
                },
                ..Default::default()
            }),
    ]
    .spacing(10);

    let field_name = format!("{:?}_path", path_type);
    let error_msg = if let Some(error) = validation_errors.fields.get(&field_name) {
        container(
            row![
                text("⚠").size(14).color(Color::from_rgb(1.0, 0.7, 0.0)),
                text(error).size(12).color(Color::from_rgb(1.0, 0.95, 0.95))
            ]
            .spacing(8)
            .padding(8),
        )
        .style(|_theme| container::Style {
            background: Some(iced::Background::Color(Color::from_rgb(0.6, 0.15, 0.15))),
            border: Border {
                color: Color::from_rgb(0.8, 0.3, 0.3),
                width: 1.0,
                radius: 4.0.into(),
            },
            ..Default::default()
        })
    } else {
        container(text(""))
    };

    column![
        text(title).size(14),
        if paths.is_empty() {
            column![text("No paths configured")
                .size(12)
                .color(Color::from_rgb(0.5, 0.5, 0.5))]
        } else {
            path_list
        },
        add_input,
        error_msg,
    ]
    .spacing(10)
    .into()
}
