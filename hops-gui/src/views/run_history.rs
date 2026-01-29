use crate::app::Message;
use iced::widget::{button, column, container, text};
use iced::{Element, Length};

pub fn view() -> Element<'static, Message> {
    let title = text("Run History").size(32);
    let placeholder = text("Past sandbox runs and denied capability attempts will appear here.");

    let back_button = button(text("Back to List"))
        .on_press(Message::SwitchView(crate::app::ViewMode::ProfileList))
        .width(Length::Fill);

    let content = column![title, placeholder, back_button]
        .spacing(20)
        .padding(20);

    container(content)
        .width(Length::Fill)
        .height(Length::Fill)
        .into()
}
