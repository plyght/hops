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
                let header = row![
                    text(&record.id).size(16).width(Length::Fixed(150.0)),
                    text(format!("Profile: {}", record.profile_name))
                        .size(14)
                        .color(Color::from_rgb(0.7, 0.7, 0.7))
                        .width(Length::Fill),
                    text(format!("Exit: {}", record.exit_code)).size(14).color(
                        if record.exit_code == 0 {
                            Color::from_rgb(0.3, 0.8, 0.3)
                        } else {
                            Color::from_rgb(0.9, 0.3, 0.3)
                        }
                    ),
                ]
                .spacing(15);

                let details = row![
                    text(format!("Started: {}", record.start_time))
                        .size(12)
                        .color(Color::from_rgb(0.6, 0.6, 0.6)),
                    text(format!("Duration: {}", record.duration))
                        .size(12)
                        .color(Color::from_rgb(0.6, 0.6, 0.6)),
                ]
                .spacing(20);

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

                let card = container(
                    column![header, details, denied_section]
                        .spacing(10)
                        .padding(15),
                )
                .width(Length::Fill)
                .style(|_theme| container::Style {
                    background: Some(iced::Background::Color(Color::from_rgb(0.15, 0.15, 0.15))),
                    border: Border {
                        color: if record.denied_capabilities.is_empty() {
                            Color::from_rgb(0.3, 0.3, 0.3)
                        } else {
                            Color::from_rgb(0.9, 0.5, 0.2)
                        },
                        width: 1.0,
                        radius: 2.0.into(),
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
        let denied = records
            .iter()
            .filter(|r| !r.denied_capabilities.is_empty())
            .count();

        row![
            text(format!("Total: {}", total))
                .size(14)
                .color(Color::from_rgb(0.7, 0.7, 0.7)),
            text(format!("Successful: {}", successful))
                .size(14)
                .color(Color::from_rgb(0.3, 0.8, 0.3)),
            text(format!("With Denials: {}", denied))
                .size(14)
                .color(Color::from_rgb(0.9, 0.5, 0.2)),
        ]
        .spacing(20)
    } else {
        row![]
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
