use crate::app::Message;
use crate::models::policy::Policy;
use iced::widget::{
    button, column, container, pick_list, row, scrollable, text, text_input, Column,
};
use iced::{Element, Length};

const NETWORK_OPTIONS: &[&str] = &["disabled", "local", "full"];

pub fn view(policy: &Policy) -> Element<'static, Message> {
    let title = text(format!("Editing: {}", policy.name)).size(24);

    let network_section = column![
        text("Network Capability").size(18),
        pick_list(
            NETWORK_OPTIONS,
            Some(policy.capabilities.network.as_str()),
            |selected| Message::NetworkCapabilityChanged(selected.to_string())
        )
    ]
    .spacing(10);

    let fs_read_list: Column<Message> = policy
        .capabilities
        .filesystem
        .read
        .iter()
        .fold(Column::new().spacing(5), |col, path| {
            col.push(text(format!("  - {}", path)))
        });

    let fs_write_list: Column<Message> = policy
        .capabilities
        .filesystem
        .write
        .iter()
        .fold(Column::new().spacing(5), |col, path| {
            col.push(text(format!("  - {}", path)))
        });

    let fs_execute_list: Column<Message> = policy
        .capabilities
        .filesystem
        .execute
        .iter()
        .fold(Column::new().spacing(5), |col, path| {
            col.push(text(format!("  - {}", path)))
        });

    let filesystem_section = column![
        text("Filesystem Capabilities").size(18),
        text("Read paths:"),
        fs_read_list,
        text("Write paths:"),
        fs_write_list,
        text("Execute paths:"),
        fs_execute_list,
    ]
    .spacing(10);

    let resources_section = column![
        text("Resource Limits").size(18),
        row![text("CPUs:"), text(format!("{}", policy.resources.cpus))].spacing(10),
        row![text("Memory:"), text(&policy.resources.memory)].spacing(10),
        row![
            text("Max Processes:"),
            text(format!("{}", policy.resources.max_processes))
        ]
        .spacing(10),
    ]
    .spacing(10);

    let save_button = button(text("Save Profile"))
        .on_press(Message::SaveProfile)
        .width(Length::Fill);

    let back_button = button(text("Back to List"))
        .on_press(Message::SwitchView(crate::app::ViewMode::ProfileList))
        .width(Length::Fill);

    let content = column![
        title,
        network_section,
        filesystem_section,
        resources_section,
        save_button,
        back_button,
    ]
    .spacing(20)
    .padding(20);

    container(scrollable(content))
        .width(Length::Fill)
        .height(Length::Fill)
        .into()
}
