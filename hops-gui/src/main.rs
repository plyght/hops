mod app;
mod grpc_client;
mod models;
mod utils;
mod views;

use app::{HopsGui, Message};
use iced::keyboard;
use iced::Event;
use iced::{Element, Subscription, Task};

fn main() -> iced::Result {
    iced::application("Hops - Profile Management", update, view)
        .subscription(subscription)
        .run_with(|| {
            let (app, task) = HopsGui::new();
            (app, task)
        })
}

fn update(state: &mut HopsGui, message: Message) -> Task<Message> {
    state.update(message)
}

fn view(state: &HopsGui) -> Element<'_, Message> {
    state.view()
}

fn subscription(_state: &HopsGui) -> Subscription<Message> {
    iced::event::listen_with(|event, _status, _id| match event {
        Event::Keyboard(keyboard::Event::KeyPressed {
            key: keyboard::Key::Character(c),
            modifiers,
            ..
        }) => {
            let is_cmd_or_ctrl = if cfg!(target_os = "macos") {
                modifiers.command()
            } else {
                modifiers.control()
            };

            if is_cmd_or_ctrl {
                match c.as_str() {
                    "s" | "S" => Some(Message::SaveProfile),
                    "n" | "N" => Some(Message::CreateNewProfile),
                    _ => None,
                }
            } else {
                None
            }
        }
        _ => None,
    })
}
