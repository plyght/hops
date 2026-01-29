use crate::app::{Message, RunRecord};
use iced::widget::{column, container, row, scrollable, text, text_input, Column};
use iced::{Border, Color, Element, Length};

pub fn view<'a>(records: &'a [RunRecord], filter: &'a str) -> Element<'a, Message> {
    let title = text("RUN HISTORY").size(32);

    let filter_input = row![
        text("Filter:").width(Length::Fixed(60.0)),
        text_input("Search by ID, profile, or status", filter)
            .on_input(Message::HistoryFilterChanged)
            .padding(10)
            .width(Length::Fill),
    ]
    .spacing(10);

    let filtered_records: Vec<&RunRecord> = if filter.is_empty() {
        records.iter().collect()
    } else {
        records
            .iter()
            .filter(|r| {
                r.id.contains(filter)
                    || r.profile_name.contains(filter)
                    || r.exit_code.to_string().contains(filter)
            })
            .collect()
    };

    let history_list: Column<Message> =
        filtered_records
            .iter()
            .fold(Column::new().spacing(15), |col, record| {
                let status_badge = if record.exit_code == 0 {
                    container(text("✓ SUCCESS").size(12).color(Color::WHITE))
                        .padding([4, 12])
                        .style(|_theme| container::Style {
                            background: Some(iced::Background::Color(Color::from_rgb(
                                0.2, 0.6, 0.2,
                            ))),
                            border: Border {
                                color: Color::from_rgb(0.3, 0.7, 0.3),
                                width: 1.0,
                                radius: 12.0.into(),
                            },
                            ..Default::default()
                        })
                } else {
                    container(
                        text(format!("✗ FAILED ({})", record.exit_code))
                            .size(12)
                            .color(Color::WHITE),
                    )
                    .padding([4, 12])
                    .style(|_theme| container::Style {
                        background: Some(iced::Background::Color(Color::from_rgb(0.8, 0.2, 0.2))),
                        border: Border {
                            color: Color::from_rgb(0.9, 0.3, 0.3),
                            width: 1.0,
                            radius: 12.0.into(),
                        },
                        ..Default::default()
                    })
                };

                let header = row![
                    text(&record.id).size(16).width(Length::Fixed(200.0)),
                    text(format!("📦 {}", record.profile_name))
                        .size(14)
                        .color(Color::from_rgb(0.7, 0.7, 0.7))
                        .width(Length::Fill),
                    status_badge,
                ]
                .spacing(15)
                .align_y(iced::alignment::Vertical::Center);

                let details = row![
                    text(format!("🕒 {}", record.start_time))
                        .size(12)
                        .color(Color::from_rgb(0.65, 0.65, 0.7)),
                    text(format!("⏱ {}", record.duration))
                        .size(12)
                        .color(Color::from_rgb(0.65, 0.65, 0.7)),
                ]
                .spacing(25);

                let denied_section = if record.denied_capabilities.is_empty() {
                    column![text("No denied capabilities")
                        .size(12)
                        .color(Color::from_rgb(0.5, 0.5, 0.5))]
                } else {
                    let denied_list: Column<Message> = record.denied_capabilities.iter().fold(
                        Column::new().spacing(4),
                        |col, denied| {
                            col.push(
                                text(format!("  ⚠ {}", denied))
                                    .size(12)
                                    .color(Color::from_rgb(0.9, 0.5, 0.2)),
                            )
                        },
                    );
                    column![
                        text("Denied Capabilities:")
                            .size(12)
                            .color(Color::from_rgb(0.9, 0.5, 0.2)),
                        denied_list,
                    ]
                    .spacing(6)
                };

                let has_denials = !record.denied_capabilities.is_empty();
                let failed = record.exit_code != 0;
                let border_color = if has_denials {
                    Color::from_rgb(0.9, 0.5, 0.2)
                } else if failed {
                    Color::from_rgb(0.6, 0.25, 0.25)
                } else {
                    Color::from_rgb(0.35, 0.35, 0.4)
                };

                let card = container(
                    column![header, details, denied_section]
                        .spacing(12)
                        .padding(20),
                )
                .width(Length::Fill)
                .style(move |_theme| container::Style {
                    background: Some(iced::Background::Color(Color::from_rgb(0.16, 0.16, 0.18))),
                    border: Border {
                        color: border_color,
                        width: 1.0,
                        radius: 8.0.into(),
                    },
                    shadow: iced::Shadow {
                        color: Color::from_rgba(0.0, 0.0, 0.0, 0.3),
                        offset: iced::Vector::new(0.0, 4.0),
                        blur_radius: 12.0,
                    },
                    ..Default::default()
                });

                col.push(card)
            });

    let empty_state = if records.is_empty() {
        column![text("No sandbox runs recorded yet.")
            .size(16)
            .color(Color::from_rgb(0.6, 0.6, 0.6))]
    } else if filtered_records.is_empty() {
        column![text("No matching records found.")
            .size(16)
            .color(Color::from_rgb(0.6, 0.6, 0.6))]
    } else {
        column![]
    };

    let summary = if !records.is_empty() {
        let total = records.len();
        let successful = records.iter().filter(|r| r.exit_code == 0).count();
        let failed = total - successful;
        let denied = records
            .iter()
            .filter(|r| !r.denied_capabilities.is_empty())
            .count();

        container(
            row![
                container(
                    text(format!("📊 Total: {}", total))
                        .size(14)
                        .color(Color::from_rgb(0.9, 0.9, 0.95))
                )
                .padding([6, 12])
                .style(|_theme| container::Style {
                    background: Some(iced::Background::Color(Color::from_rgb(0.25, 0.25, 0.3))),
                    border: Border {
                        color: Color::from_rgb(0.4, 0.4, 0.45),
                        width: 1.0,
                        radius: 6.0.into(),
                    },
                    ..Default::default()
                }),
                container(
                    text(format!("✓ Success: {}", successful))
                        .size(14)
                        .color(Color::from_rgb(0.9, 0.95, 0.9))
                )
                .padding([6, 12])
                .style(|_theme| container::Style {
                    background: Some(iced::Background::Color(Color::from_rgb(0.15, 0.4, 0.15))),
                    border: Border {
                        color: Color::from_rgb(0.3, 0.6, 0.3),
                        width: 1.0,
                        radius: 6.0.into(),
                    },
                    ..Default::default()
                }),
                container(
                    text(format!("✗ Failed: {}", failed))
                        .size(14)
                        .color(Color::from_rgb(0.95, 0.9, 0.9))
                )
                .padding([6, 12])
                .style(|_theme| container::Style {
                    background: Some(iced::Background::Color(Color::from_rgb(0.5, 0.15, 0.15))),
                    border: Border {
                        color: Color::from_rgb(0.7, 0.25, 0.25),
                        width: 1.0,
                        radius: 6.0.into(),
                    },
                    ..Default::default()
                }),
                container(
                    text(format!("⚠ Denials: {}", denied))
                        .size(14)
                        .color(Color::from_rgb(0.95, 0.95, 0.9))
                )
                .padding([6, 12])
                .style(|_theme| container::Style {
                    background: Some(iced::Background::Color(Color::from_rgb(0.5, 0.3, 0.1))),
                    border: Border {
                        color: Color::from_rgb(0.7, 0.4, 0.15),
                        width: 1.0,
                        radius: 6.0.into(),
                    },
                    ..Default::default()
                }),
            ]
            .spacing(15),
        )
        .padding([10, 0])
    } else {
        container(row![])
    };

    let content = column![
        title,
        filter_input,
        summary,
        empty_state,
        scrollable(history_list),
    ]
    .spacing(20)
    .padding(30);

    container(content)
        .width(Length::Fill)
        .height(Length::Fill)
        .into()
}
