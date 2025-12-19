#![cfg_attr(
    all(not(debug_assertions), target_os = "windows"),
    windows_subsystem = "windows"
)]

use serde::{Deserialize, Serialize};
use std::sync::Mutex;
use tauri::{CustomMenuItem, Manager, SystemTray, SystemTrayEvent, SystemTrayMenu};

mod server;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServerConfig {
    pub url: String,
    pub token: String,
    pub name: String,
}

#[derive(Debug, Default)]
pub struct AppState {
    pub servers: Vec<ServerConfig>,
    pub connected: bool,
}

#[tauri::command]
fn get_servers(state: tauri::State<Mutex<AppState>>) -> Vec<ServerConfig> {
    let state = state.lock().unwrap();
    state.servers.clone()
}

#[tauri::command]
fn add_server(
    state: tauri::State<Mutex<AppState>>,
    url: String,
    token: String,
    name: String,
) -> Result<(), String> {
    let mut state = state.lock().unwrap();
    state.servers.push(ServerConfig { url, token, name });
    Ok(())
}

#[tauri::command]
fn remove_server(state: tauri::State<Mutex<AppState>>, index: usize) -> Result<(), String> {
    let mut state = state.lock().unwrap();
    if index < state.servers.len() {
        state.servers.remove(index);
        Ok(())
    } else {
        Err("Invalid index".to_string())
    }
}

#[tauri::command]
async fn connect_to_server(url: String, token: String) -> Result<String, String> {
    server::connect(&url, &token)
        .await
        .map_err(|e| e.to_string())
}

fn main() {
    let tray_menu = SystemTrayMenu::new()
        .add_item(CustomMenuItem::new("show", "Show Window"))
        .add_item(CustomMenuItem::new("quit", "Quit"));

    let system_tray = SystemTray::new().with_menu(tray_menu);

    tauri::Builder::default()
        .manage(Mutex::new(AppState::default()))
        .system_tray(system_tray)
        .on_system_tray_event(|app, event| match event {
            SystemTrayEvent::LeftClick { .. } => {
                if let Some(window) = app.get_window("main") {
                    window.show().unwrap();
                    window.set_focus().unwrap();
                }
            }
            SystemTrayEvent::MenuItemClick { id, .. } => match id.as_str() {
                "show" => {
                    if let Some(window) = app.get_window("main") {
                        window.show().unwrap();
                        window.set_focus().unwrap();
                    }
                }
                "quit" => {
                    std::process::exit(0);
                }
                _ => {}
            },
            _ => {}
        })
        .invoke_handler(tauri::generate_handler![
            get_servers,
            add_server,
            remove_server,
            connect_to_server
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
