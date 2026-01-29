mod app;
mod grpc_client;
mod models;
mod utils;
mod views;

use app::{HopsGui, Message};
use iced::{Element, Task};

fn main() -> iced::Result {
    iced::application("Hops - Profile Management", update, view).run_with(|| {
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
