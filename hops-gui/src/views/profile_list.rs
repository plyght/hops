use crate::app::Message;
use crate::models::policy::Policy;
use iced::widget::{button, column, container, scrollable, text, Column};
use iced::{Element, Length};

pub fn view(profiles: &[Policy]) -> Element<'static, Message> {
    let title = text("Hops Profiles").size(32);

    let profile_list: Column<Message> =
        profiles
            .iter()
            .enumerate()
            .fold(Column::new().spacing(10), |col, (idx, profile)| {
                col.push(
                    button(text(&profile.name))
                        .on_press(Message::ProfileSelected(idx))
                        .width(Length::Fill),
                )
            });

    let new_profile_btn = button(text("+ Create New Profile"))
        .on_press(Message::CreateNewProfile)
        .width(Length::Fill);

    let content = column![title, scrollable(profile_list), new_profile_btn]
        .spacing(20)
        .padding(20);

    container(content)
        .width(Length::Fill)
        .height(Length::Fill)
        .into()
}
