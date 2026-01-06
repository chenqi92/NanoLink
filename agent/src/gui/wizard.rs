//! Configuration wizard for NanoLink Agent

use crate::config::{Config, ServerConfig};
use eframe::egui;
use std::path::PathBuf;

/// Permission levels for server connections
const PERMISSION_LEVELS: &[(&str, u8)] = &[
    ("READ_ONLY (0) - View metrics only", 0),
    ("BASIC_WRITE (1) - Basic operations", 1),
    ("SERVICE_CONTROL (2) - Manage services", 2),
    ("SYSTEM_ADMIN (3) - Full control", 3),
];

/// Wizard state
#[derive(Default)]
struct WizardState {
    // Server configuration
    host: String,
    port: String,
    token: String,
    permission: usize,
    tls_enabled: bool,
    tls_verify: bool,

    // UI state
    current_step: usize,
    error_message: Option<String>,
    show_token: bool,

    // Result
    config_saved: bool,
    config_path: Option<PathBuf>,
}

impl WizardState {
    fn new() -> Self {
        Self {
            host: String::new(),
            port: "39100".to_string(),
            permission: 0,
            tls_verify: true,
            ..Default::default()
        }
    }

    fn validate_server_config(&self) -> Result<(), String> {
        if self.host.trim().is_empty() {
            return Err("Server host is required".to_string());
        }

        if self.port.trim().is_empty() {
            return Err("Port is required".to_string());
        }

        let port: u16 = self
            .port
            .trim()
            .parse()
            .map_err(|_| "Port must be a valid number (1-65535)".to_string())?;

        if port == 0 {
            return Err("Port must be greater than 0".to_string());
        }

        if self.token.trim().is_empty() {
            return Err("Authentication token is required".to_string());
        }

        Ok(())
    }

    fn save_config(&mut self) -> Result<PathBuf, String> {
        self.validate_server_config()?;

        let server = ServerConfig {
            host: self.host.trim().to_string(),
            port: self.port.trim().parse().unwrap(),
            token: self.token.clone(),
            permission: PERMISSION_LEVELS[self.permission].1,
            tls_enabled: self.tls_enabled,
            tls_verify: self.tls_verify,
        };

        let mut config = Config::sample();
        config.servers = vec![server];

        // Determine config path
        let config_path = if let Ok(exe_path) = std::env::current_exe() {
            if let Some(exe_dir) = exe_path.parent() {
                exe_dir.join("nanolink.yaml")
            } else {
                PathBuf::from("nanolink.yaml")
            }
        } else {
            PathBuf::from("nanolink.yaml")
        };

        // Save configuration
        let yaml = serde_yaml::to_string(&config)
            .map_err(|e| format!("Failed to serialize config: {}", e))?;

        std::fs::write(&config_path, yaml)
            .map_err(|e| format!("Failed to write config file: {}", e))?;

        Ok(config_path)
    }
}

/// Configuration wizard application
struct WizardApp {
    state: WizardState,
}

impl WizardApp {
    fn new(_cc: &eframe::CreationContext<'_>) -> Self {
        Self {
            state: WizardState::new(),
        }
    }
}

impl eframe::App for WizardApp {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        // Set dark theme
        ctx.set_visuals(egui::Visuals::dark());

        egui::CentralPanel::default().show(ctx, |ui| {
            ui.vertical_centered(|ui| {
                ui.add_space(20.0);

                // Title
                ui.heading(
                    egui::RichText::new("NanoLink Agent Configuration")
                        .size(24.0)
                        .strong(),
                );

                ui.add_space(10.0);
                ui.label(
                    egui::RichText::new(format!("Version {}", env!("CARGO_PKG_VERSION")))
                        .color(egui::Color32::GRAY),
                );

                ui.add_space(30.0);
            });

            if self.state.config_saved {
                self.show_success_page(ui);
            } else {
                match self.state.current_step {
                    0 => self.show_welcome_page(ui),
                    1 => self.show_server_config_page(ui),
                    _ => {}
                }
            }
        });
    }
}

impl WizardApp {
    fn show_welcome_page(&mut self, ui: &mut egui::Ui) {
        ui.vertical_centered(|ui| {
            ui.add_space(20.0);

            ui.label(egui::RichText::new("Welcome to NanoLink Agent!").size(18.0));

            ui.add_space(20.0);

            ui.label("No configuration file was found.");
            ui.label("This wizard will help you set up the agent.");

            ui.add_space(40.0);

            if ui
                .button(egui::RichText::new("  Start Configuration  ").size(16.0))
                .clicked()
            {
                self.state.current_step = 1;
            }

            ui.add_space(20.0);

            if ui.small_button("Exit").clicked() {
                std::process::exit(0);
            }
        });
    }

    fn show_server_config_page(&mut self, ui: &mut egui::Ui) {
        ui.vertical_centered(|ui| {
            ui.label(
                egui::RichText::new("Server Configuration")
                    .size(18.0)
                    .strong(),
            );
            ui.add_space(10.0);
            ui.label("Enter the NanoLink server details:");
        });

        ui.add_space(20.0);

        // Form
        egui::Grid::new("server_config_grid")
            .num_columns(2)
            .spacing([20.0, 10.0])
            .show(ui, |ui| {
                // Host
                ui.label("Server Host:");
                ui.add(
                    egui::TextEdit::singleline(&mut self.state.host)
                        .hint_text("e.g., 192.168.1.100 or server.example.com")
                        .desired_width(300.0),
                );
                ui.end_row();

                // Port
                ui.label("Port:");
                ui.add(
                    egui::TextEdit::singleline(&mut self.state.port)
                        .hint_text("39100")
                        .desired_width(100.0),
                );
                ui.end_row();

                // Token
                ui.label("Auth Token:");
                ui.horizontal(|ui| {
                    if self.state.show_token {
                        ui.add(
                            egui::TextEdit::singleline(&mut self.state.token)
                                .hint_text("Enter your authentication token")
                                .desired_width(260.0),
                        );
                    } else {
                        ui.add(
                            egui::TextEdit::singleline(&mut self.state.token)
                                .hint_text("Enter your authentication token")
                                .password(true)
                                .desired_width(260.0),
                        );
                    }
                    if ui
                        .small_button(if self.state.show_token {
                            "Hide"
                        } else {
                            "Show"
                        })
                        .clicked()
                    {
                        self.state.show_token = !self.state.show_token;
                    }
                });
                ui.end_row();

                // Permission
                ui.label("Permission Level:");
                egui::ComboBox::from_id_salt("permission_combo")
                    .selected_text(PERMISSION_LEVELS[self.state.permission].0)
                    .width(300.0)
                    .show_ui(ui, |ui| {
                        for (i, (label, _)) in PERMISSION_LEVELS.iter().enumerate() {
                            ui.selectable_value(&mut self.state.permission, i, *label);
                        }
                    });
                ui.end_row();

                // TLS Options
                ui.label("TLS:");
                ui.horizontal(|ui| {
                    ui.checkbox(&mut self.state.tls_enabled, "Enable TLS");
                    if self.state.tls_enabled {
                        ui.checkbox(&mut self.state.tls_verify, "Verify Certificate");
                    }
                });
                ui.end_row();
            });

        ui.add_space(20.0);

        // Error message
        if let Some(error) = &self.state.error_message {
            ui.colored_label(egui::Color32::RED, error);
            ui.add_space(10.0);
        }

        // Buttons
        ui.horizontal(|ui| {
            ui.add_space(ui.available_width() / 2.0 - 100.0);

            if ui.button("  Back  ").clicked() {
                self.state.current_step = 0;
                self.state.error_message = None;
            }

            ui.add_space(20.0);

            if ui
                .button(egui::RichText::new("  Save & Start Agent  ").strong())
                .clicked()
            {
                match self.state.save_config() {
                    Ok(path) => {
                        self.state.config_path = Some(path);
                        self.state.config_saved = true;
                        self.state.error_message = None;
                    }
                    Err(e) => {
                        self.state.error_message = Some(e);
                    }
                }
            }
        });
    }

    fn show_success_page(&mut self, ui: &mut egui::Ui) {
        ui.vertical_centered(|ui| {
            ui.add_space(20.0);

            ui.label(
                egui::RichText::new("Configuration Saved!")
                    .size(20.0)
                    .color(egui::Color32::GREEN)
                    .strong(),
            );

            ui.add_space(20.0);

            if let Some(path) = &self.state.config_path {
                ui.label(format!("Config file: {}", path.display()));
            }

            ui.add_space(20.0);

            ui.label("You can now start the agent by running:");
            ui.add_space(10.0);

            ui.code("nanolink-agent");

            ui.add_space(10.0);

            ui.label("Or install as a Windows Service:");
            ui.code("nanolink-agent service install");
            ui.code("nanolink-agent service start");

            ui.add_space(30.0);

            if ui
                .button(egui::RichText::new("  Close  ").size(14.0))
                .clicked()
            {
                std::process::exit(0);
            }
        });
    }
}

/// Run the configuration wizard
pub fn run_wizard() -> anyhow::Result<()> {
    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_inner_size([500.0, 450.0])
            .with_min_inner_size([400.0, 350.0])
            .with_title("NanoLink Agent - Configuration Wizard"),
        centered: true,
        ..Default::default()
    };

    eframe::run_native(
        "NanoLink Agent Configuration",
        options,
        Box::new(|cc| Ok(Box::new(WizardApp::new(cc)))),
    )
    .map_err(|e| anyhow::anyhow!("Failed to run wizard: {}", e))?;

    Ok(())
}
