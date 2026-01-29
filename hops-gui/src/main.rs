mod app;
mod models;
mod utils;
mod views;

use app::HopsGui;
use iced::{Application, Settings};

fn main() -> iced::Result {
    HopsGui::run(Settings::default())
}
