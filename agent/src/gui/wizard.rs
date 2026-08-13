//! Configuration wizard for NanoLink Agent

use crate::config::{Config, ServerConfig};
use crate::i18n::{Lang, t};
use eframe::egui;
use std::path::PathBuf;

/// Permission levels for server connections
const PERMISSION_LEVELS: &[(&str, u8)] = &[
    ("permission.read_only", 0),
    ("permission.basic_write", 1),
    ("permission.service_control", 2),
    ("permission.system_admin", 3),
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
    lang: Lang,

    // Result
    config_saved: bool,
    config_path: Option<PathBuf>,
}

impl WizardState {
    fn new(lang: Lang) -> Self {
        Self {
            host: String::new(),
            port: "39100".to_string(),
            permission: 0,
            tls_verify: true,
            lang,
            ..Default::default()
        }
    }

    fn validate_server_config(&self) -> Result<(), String> {
        if self.host.trim().is_empty() {
            return Err(t("gui.error.host_required", self.lang).to_string());
        }

        if self.port.trim().is_empty() {
            return Err(t("gui.error.port_required", self.lang).to_string());
        }

        let port: u16 = self
            .port
            .trim()
            .parse()
            .map_err(|_| t("gui.error.port_invalid", self.lang).to_string())?;

        if port == 0 {
            return Err(t("gui.error.port_zero", self.lang).to_string());
        }

        if self.token.trim().is_empty() {
            return Err(t("gui.error.token_required", self.lang).to_string());
        }

        Ok(())
    }

    fn save_config(&mut self) -> Result<PathBuf, String> {
        self.validate_server_config()?;

        // validate_server_config already verified the port parses; we re-parse
        // here defensively (rather than unwrap) so a future code change that
        // skips validation can't turn a malformed input into a process-wide
        // panic in the GUI thread.
        let port: u16 = self
            .port
            .trim()
            .parse()
            .map_err(|_| t("gui.error.port_invalid", self.lang).to_string())?;

        let server = ServerConfig {
            host: self.host.trim().to_string(),
            port,
            token: self.token.clone(),
            management_token: None,
            permission: PERMISSION_LEVELS[self.permission].1,
            tls_enabled: self.tls_enabled,
            tls_verify: self.tls_verify,
            tls_ca_cert: None,
            tls_server_name: None,
            tls_client_cert: None,
            tls_client_key: None,
        };

        let mut config = Config::sample();
        config.agent.language = Some(self.lang.as_str().to_string());
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
            .map_err(|e| format!("{}: {e}", t("gui.error.serialize_failed", self.lang)))?;

        std::fs::write(&config_path, yaml)
            .map_err(|e| format!("{}: {e}", t("gui.error.write_failed", self.lang)))?;

        Ok(config_path)
    }
}

/// Configuration wizard application
struct WizardApp {
    state: WizardState,
}

impl WizardApp {
    fn new(_cc: &eframe::CreationContext<'_>, lang: Lang) -> Self {
        Self {
            state: WizardState::new(lang),
        }
    }
}

impl eframe::App for WizardApp {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        // Set dark theme
        ctx.set_visuals(egui::Visuals::dark());

        egui::CentralPanel::default().show(ctx, |ui| {
            ui.horizontal(|ui| {
                ui.selectable_value(&mut self.state.lang, Lang::En, "English");
                ui.selectable_value(&mut self.state.lang, Lang::Zh, "中文");
            });
            ui.vertical_centered(|ui| {
                ui.add_space(20.0);

                // Title
                ui.heading(
                    egui::RichText::new(t("gui.title", self.state.lang))
                        .size(24.0)
                        .strong(),
                );

                ui.add_space(10.0);
                ui.label(
                    egui::RichText::new(format!(
                        "{} {}",
                        t("gui.version", self.state.lang),
                        env!("CARGO_PKG_VERSION")
                    ))
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

            ui.label(egui::RichText::new(t("gui.welcome", self.state.lang)).size(18.0));

            ui.add_space(20.0);

            ui.label(t("gui.no_config", self.state.lang));
            ui.label(t("gui.help", self.state.lang));

            ui.add_space(40.0);

            if ui
                .button(
                    egui::RichText::new(format!("  {}  ", t("gui.start_config", self.state.lang)))
                        .size(16.0),
                )
                .clicked()
            {
                self.state.current_step = 1;
            }

            ui.add_space(20.0);

            if ui.small_button(t("menu.exit", self.state.lang)).clicked() {
                std::process::exit(0);
            }
        });
    }

    fn show_server_config_page(&mut self, ui: &mut egui::Ui) {
        ui.vertical_centered(|ui| {
            ui.label(
                egui::RichText::new(t("gui.server_config", self.state.lang))
                    .size(18.0)
                    .strong(),
            );
            ui.add_space(10.0);
            ui.label(t("gui.enter_details", self.state.lang));
        });

        ui.add_space(20.0);

        // Form
        egui::Grid::new("server_config_grid")
            .num_columns(2)
            .spacing([20.0, 10.0])
            .show(ui, |ui| {
                // Host
                ui.label(t("gui.server_host", self.state.lang));
                ui.add(
                    egui::TextEdit::singleline(&mut self.state.host)
                        .hint_text(t("gui.server_host_hint", self.state.lang))
                        .desired_width(300.0),
                );
                ui.end_row();

                // Port
                ui.label(t("gui.port", self.state.lang));
                ui.add(
                    egui::TextEdit::singleline(&mut self.state.port)
                        .hint_text("39100")
                        .desired_width(100.0),
                );
                ui.end_row();

                // Token
                ui.label(t("gui.auth_token", self.state.lang));
                ui.horizontal(|ui| {
                    if self.state.show_token {
                        ui.add(
                            egui::TextEdit::singleline(&mut self.state.token)
                                .hint_text(t("gui.auth_token_hint", self.state.lang))
                                .desired_width(260.0),
                        );
                    } else {
                        ui.add(
                            egui::TextEdit::singleline(&mut self.state.token)
                                .hint_text(t("gui.auth_token_hint", self.state.lang))
                                .password(true)
                                .desired_width(260.0),
                        );
                    }
                    if ui
                        .small_button(if self.state.show_token {
                            t("gui.hide", self.state.lang)
                        } else {
                            t("gui.show", self.state.lang)
                        })
                        .clicked()
                    {
                        self.state.show_token = !self.state.show_token;
                    }
                });
                ui.end_row();

                // Permission
                ui.label(t("gui.permission", self.state.lang));
                egui::ComboBox::from_id_salt("permission_combo")
                    .selected_text(t(
                        PERMISSION_LEVELS[self.state.permission].0,
                        self.state.lang,
                    ))
                    .width(300.0)
                    .show_ui(ui, |ui| {
                        for (i, (key, _)) in PERMISSION_LEVELS.iter().enumerate() {
                            ui.selectable_value(
                                &mut self.state.permission,
                                i,
                                t(key, self.state.lang),
                            );
                        }
                    });
                ui.end_row();

                // TLS Options
                ui.label(t("gui.tls", self.state.lang));
                ui.horizontal(|ui| {
                    ui.checkbox(
                        &mut self.state.tls_enabled,
                        t("gui.enable_tls", self.state.lang),
                    );
                    if self.state.tls_enabled {
                        self.state.tls_verify = true;
                        ui.label(t("gui.tls_required", self.state.lang));
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

            if ui
                .button(format!("  {}  ", t("server.back", self.state.lang)))
                .clicked()
            {
                self.state.current_step = 0;
                self.state.error_message = None;
            }

            ui.add_space(20.0);

            if ui
                .button(
                    egui::RichText::new(format!("  {}  ", t("gui.save_start", self.state.lang)))
                        .strong(),
                )
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
                egui::RichText::new(t("gui.saved", self.state.lang))
                    .size(20.0)
                    .color(egui::Color32::GREEN)
                    .strong(),
            );

            ui.add_space(20.0);

            if let Some(path) = &self.state.config_path {
                ui.label(format!(
                    "{}: {}",
                    t("gui.config_file", self.state.lang),
                    path.display()
                ));
            }

            ui.add_space(20.0);

            ui.label(t("gui.start_hint", self.state.lang));
            ui.add_space(10.0);

            ui.code("nanolink-agent");

            ui.add_space(10.0);

            ui.label(t("gui.service_hint", self.state.lang));
            ui.code("nanolink-agent service install");
            ui.code("nanolink-agent service start");

            ui.add_space(30.0);

            if ui
                .button(
                    egui::RichText::new(format!("  {}  ", t("gui.close", self.state.lang)))
                        .size(14.0),
                )
                .clicked()
            {
                std::process::exit(0);
            }
        });
    }
}

/// Run the configuration wizard
pub fn run_wizard(lang: Lang) -> anyhow::Result<()> {
    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_inner_size([500.0, 450.0])
            .with_min_inner_size([400.0, 350.0])
            .with_title(t("gui.window_title", lang)),
        centered: true,
        ..Default::default()
    };

    eframe::run_native(
        t("gui.title", lang),
        options,
        Box::new(move |cc| Ok(Box::new(WizardApp::new(cc, lang)))),
    )
    .map_err(|e| anyhow::anyhow!("{}: {e}", t("gui.error.run_failed", lang)))?;

    Ok(())
}
