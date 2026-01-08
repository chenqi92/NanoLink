mod buffer;
mod collector;
mod config;
mod connection;
mod executor;
#[cfg(feature = "gui")]
mod gui;
mod i18n;
mod management;
mod platform;
mod security;
mod tui;
mod utils;

#[allow(clippy::large_enum_variant)]
pub mod proto {
    include!(concat!(env!("OUT_DIR"), "/nanolink.rs"));
}

use anyhow::Result;
use clap::{Parser, Subcommand};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use tokio::sync::{RwLock, broadcast};
use tracing::{Level, info};
use tracing_subscriber::FmtSubscriber;

use crate::buffer::RingBuffer;
use crate::collector::MetricsCollector;
use crate::config::Config;
use crate::connection::ConnectionManager;
use crate::management::ManagementServer;

/// Default config file search paths (in order of priority)
const CONFIG_SEARCH_PATHS: &[&str] = &[
    "nanolink.yaml",
    "nanolink.toml",
    "/etc/nanolink/nanolink.yaml",
    "/etc/nanolink/nanolink.toml",
    "/etc/nanolink.yaml",
    "/etc/nanolink.toml",
];

#[derive(Parser, Debug)]
#[command(name = "nanolink-agent")]
#[command(author = "NanoLink Team")]
#[command(version = "0.3.9")]
#[command(about = "Lightweight server monitoring agent", long_about = None)]
struct Args {
    /// Path to configuration file (auto-detected if not specified)
    #[arg(short, long, global = true)]
    config: Option<PathBuf>,

    /// Log level (trace, debug, info, warn, error)
    #[arg(short, long, default_value = "info", global = true)]
    log_level: String,

    /// Run in foreground (don't daemonize)
    #[arg(short, long)]
    foreground: bool,

    /// Generate sample configuration file
    #[arg(long)]
    generate_config: bool,

    #[command(subcommand)]
    command: Option<Commands>,
}

#[derive(Subcommand, Debug)]
enum Commands {
    /// Manage server connections
    Server {
        #[command(subcommand)]
        action: ServerAction,
    },
    /// Windows Service management (Windows only)
    #[cfg(target_os = "windows")]
    Service {
        #[command(subcommand)]
        action: ServiceAction,
    },
    /// Initialize a new configuration file
    Init {
        /// Output path for config file (default: ./nanolink.yaml)
        #[arg(short, long, default_value = "nanolink.yaml")]
        output: PathBuf,
        /// Use TOML format instead of YAML
        #[arg(long)]
        toml: bool,
    },
    /// Show agent status and configuration
    Status,
}

/// Windows Service actions
#[cfg(target_os = "windows")]
#[derive(Subcommand, Debug)]
enum ServiceAction {
    /// Install as Windows Service
    Install,
    /// Uninstall Windows Service
    Uninstall,
    /// Start the Windows Service
    Start,
    /// Stop the Windows Service
    Stop,
    /// Query Windows Service status
    Status,
    /// Run as Windows Service (called by SCM)
    Run,
}

#[derive(Subcommand, Debug)]
enum ServerAction {
    /// Add a new server (interactive if host/token not provided)
    Add {
        /// Server hostname or IP address (supports host:port format)
        #[arg(long)]
        host: Option<String>,
        /// gRPC port (default: 39100, ignored if port specified in host)
        #[arg(long, default_value = "39100")]
        port: u16,
        /// Authentication token
        #[arg(long)]
        token: Option<String>,
        /// Permission level (0-3)
        #[arg(long)]
        permission: Option<u8>,
        /// Enable TLS
        #[arg(long)]
        tls_enabled: Option<bool>,
        /// Enable TLS certificate verification
        #[arg(long)]
        tls_verify: Option<bool>,
    },
    /// Remove a server (interactive if host not provided)
    Remove {
        /// Server hostname to remove (supports host:port format)
        #[arg(long)]
        host: Option<String>,
        /// Server port to remove
        #[arg(long, default_value = "39100")]
        port: u16,
    },
    /// List all configured servers
    List,
    /// Update a server configuration (interactive if host not provided)
    Update {
        /// Server hostname (supports host:port format)
        #[arg(long)]
        host: Option<String>,
        /// Server port
        #[arg(long, default_value = "39100")]
        port: u16,
        /// New authentication token
        #[arg(long)]
        token: Option<String>,
        /// New permission level (0-3)
        #[arg(long)]
        permission: Option<u8>,
        /// Enable TLS
        #[arg(long)]
        tls_enabled: Option<bool>,
        /// Enable TLS certificate verification
        #[arg(long)]
        tls_verify: Option<bool>,
    },
}

/// Permission level options for interactive selection
const PERMISSION_OPTIONS: &[(&str, u8)] = &[
    ("READ_ONLY (0) - View metrics only", 0),
    ("BASIC_WRITE (1) - Basic operations", 1),
    ("SERVICE_CONTROL (2) - Manage services", 2),
    ("SYSTEM_ADMIN (3) - Full control", 3),
];

/// Parse host string that may contain port (e.g., "192.168.0.174:39100")
fn parse_host_port(input: &str, default_port: u16) -> (String, u16) {
    // Handle IPv6 addresses in brackets like [::1]:8080
    if input.starts_with('[') {
        if let Some(bracket_end) = input.find(']') {
            let host = &input[1..bracket_end];
            if let Some(port_str) = input.get(bracket_end + 2..) {
                if let Ok(port) = port_str.parse::<u16>() {
                    return (host.to_string(), port);
                }
            }
            return (host.to_string(), default_port);
        }
    }

    // Handle regular host:port format
    if let Some((host, port_str)) = input.rsplit_once(':') {
        if let Ok(port) = port_str.parse::<u16>() {
            return (host.to_string(), port);
        }
    }
    (input.to_string(), default_port)
}

/// Find configuration file from search paths
fn find_config() -> Option<PathBuf> {
    // First, check paths relative to current directory
    for path in CONFIG_SEARCH_PATHS {
        let p = PathBuf::from(path);
        if p.exists() {
            return Some(p);
        }
    }

    // Check paths relative to executable directory
    if let Ok(exe_path) = std::env::current_exe() {
        if let Some(exe_dir) = exe_path.parent() {
            for name in &["nanolink.yaml", "nanolink.toml"] {
                let p = exe_dir.join(name);
                if p.exists() {
                    return Some(p);
                }
            }
        }
    }

    None
}

/// Get config path from args or auto-detect
fn get_config_path(args: &Args) -> Option<PathBuf> {
    if let Some(path) = &args.config {
        Some(path.clone())
    } else {
        find_config()
    }
}

/// Print help message when no config is found
fn print_no_config_help() {
    eprintln!("Error: No configuration file found.");
    eprintln!();
    eprintln!("Searched locations:");
    for path in CONFIG_SEARCH_PATHS {
        eprintln!("  - {path}");
    }
    if let Ok(exe_path) = std::env::current_exe() {
        if let Some(exe_dir) = exe_path.parent() {
            eprintln!("  - {}/nanolink.yaml", exe_dir.display());
            eprintln!("  - {}/nanolink.toml", exe_dir.display());
        }
    }
    eprintln!();
    eprintln!("Quick start:");
    eprintln!("  1. Initialize a new config:  nanolink-agent init");
    eprintln!(
        "  2. Add a server:             nanolink-agent server add --host <HOST> --token <TOKEN>"
    );
    eprintln!("  3. Run the agent:            nanolink-agent");
    eprintln!();
    eprintln!("Or specify a config file:      nanolink-agent -c /path/to/config.yaml");
    eprintln!();
    eprintln!("Generate sample config:        nanolink-agent --generate-config > nanolink.yaml");
}

fn main() -> Result<()> {
    let args = Args::parse();

    // Initialize logging
    let log_level = match args.log_level.to_lowercase().as_str() {
        "trace" => Level::TRACE,
        "debug" => Level::DEBUG,
        "info" => Level::INFO,
        "warn" => Level::WARN,
        "error" => Level::ERROR,
        _ => Level::INFO,
    };

    FmtSubscriber::builder()
        .with_max_level(log_level)
        .with_target(false)
        .with_thread_ids(false)
        .with_file(false)
        .with_line_number(false)
        .compact()
        .init();

    // Generate sample config if requested
    if args.generate_config {
        let sample_config = Config::sample();
        let yaml = serde_yaml::to_string(&sample_config)?;
        println!("{yaml}");
        return Ok(());
    }

    // Handle subcommands - need async runtime
    if let Some(command) = &args.command {
        let rt = tokio::runtime::Runtime::new()?;
        return rt.block_on(handle_command(command, &args));
    }

    // If no subcommand and not foreground mode, enter interactive mode
    // But only if we're in a TTY (interactive terminal)
    // Note: interactive_main_menu creates its own runtime when needed
    if !args.foreground {
        // Check if stdin is a TTY - if not, we're likely running as a service
        if atty::is(atty::Stream::Stdin) {
            return interactive_main_menu(&args);
        }
        // Non-interactive environment (systemd, etc.) - run in foreground mode
    }

    // Run the agent - requires config file
    let config_path = match get_config_path(&args) {
        Some(path) => path,
        None => {
            // If GUI feature is enabled, launch the configuration wizard
            #[cfg(feature = "gui")]
            {
                info!("No configuration file found. Launching configuration wizard...");
                return gui::run_wizard();
            }

            #[cfg(not(feature = "gui"))]
            {
                print_no_config_help();
                std::process::exit(1);
            }
        }
    };

    // Create runtime for foreground agent mode
    let rt = tokio::runtime::Runtime::new()?;
    rt.block_on(run_agent(config_path))
}

async fn handle_command(command: &Commands, args: &Args) -> Result<()> {
    match command {
        #[cfg(target_os = "windows")]
        Commands::Service { action } => {
            use crate::platform::{
                install_service, query_service_status, run_as_service, start_service, stop_service,
                uninstall_service,
            };

            match action {
                ServiceAction::Install => {
                    let config_path = get_config_path(args);
                    install_service(config_path).map_err(|e| anyhow::anyhow!(e))?;
                }
                ServiceAction::Uninstall => {
                    uninstall_service().map_err(|e| anyhow::anyhow!(e))?;
                }
                ServiceAction::Start => {
                    start_service().map_err(|e| anyhow::anyhow!(e))?;
                }
                ServiceAction::Stop => {
                    stop_service().map_err(|e| anyhow::anyhow!(e))?;
                }
                ServiceAction::Status => {
                    let status = query_service_status().map_err(|e| anyhow::anyhow!(e))?;
                    println!("{status}");
                }
                ServiceAction::Run => {
                    run_as_service().map_err(|e| anyhow::anyhow!(e))?;
                }
            }
            return Ok(());
        }

        Commands::Init { output, toml } => {
            let sample_config = Config::sample();
            let content = if *toml {
                toml::to_string_pretty(&sample_config)?
            } else {
                serde_yaml::to_string(&sample_config)?
            };

            if output.exists() {
                anyhow::bail!(
                    "Config file already exists: {}. Use --output to specify a different path.",
                    output.display()
                );
            }

            std::fs::write(output, &content)?;
            println!("Configuration file created: {}", output.display());
            println!();
            println!("Next steps:");
            println!("  1. Add a server: nanolink-agent server add --host <HOST> --token <TOKEN>");
            println!("  2. Run agent:    nanolink-agent");
            return Ok(());
        }

        Commands::Status => {
            println!("NanoLink Agent v{}", env!("CARGO_PKG_VERSION"));
            println!();

            match get_config_path(args) {
                Some(config_path) => {
                    println!("Config file: {}", config_path.display());

                    match Config::load(&config_path) {
                        Ok(config) => {
                            println!();
                            println!("Configured servers:");
                            if config.servers.is_empty() {
                                println!("  (none)");
                            } else {
                                for (i, server) in config.servers.iter().enumerate() {
                                    println!("  {}. {}:{}", i + 1, server.host, server.port);
                                    println!(
                                        "     Permission: {} ({})",
                                        server.permission,
                                        permission_name(server.permission)
                                    );
                                    println!(
                                        "     TLS: {}, Verify: {}",
                                        server.tls_enabled, server.tls_verify
                                    );
                                }
                            }

                            println!();
                            println!("Settings:");
                            println!(
                                "  Realtime interval: {}ms",
                                config.collector.realtime_interval_ms
                            );
                            println!("  Buffer capacity: {}", config.buffer.capacity);
                            println!(
                                "  Management API: {} (port {})",
                                if config.management.enabled {
                                    "enabled"
                                } else {
                                    "disabled"
                                },
                                config.management.port
                            );
                        }
                        Err(e) => {
                            println!("  Error loading config: {e}");
                        }
                    }
                }
                None => {
                    println!("Config file: (not found)");
                    println!();
                    print_no_config_help();
                }
            }
            return Ok(());
        }

        Commands::Server { action } => {
            let config_path = match get_config_path(args) {
                Some(path) => path,
                None => {
                    print_no_config_help();
                    std::process::exit(1);
                }
            };

            let mut config = Config::load(&config_path)?;

            match action {
                ServerAction::Add {
                    host,
                    port,
                    token,
                    permission,
                    tls_enabled,
                    tls_verify,
                } => {
                    handle_server_add(
                        &mut config,
                        &config_path,
                        host.clone(),
                        *port,
                        token.clone(),
                        *permission,
                        *tls_enabled,
                        *tls_verify,
                    )?;
                }
                ServerAction::Remove { host, port } => {
                    handle_server_remove(&mut config, &config_path, host.clone(), *port)?;
                }
                ServerAction::List => {
                    println!("Configured servers:");
                    for (i, server) in config.servers.iter().enumerate() {
                        println!("  {}. {}:{}", i + 1, server.host, server.port);
                        println!(
                            "     Permission: {} ({})",
                            server.permission,
                            permission_name(server.permission)
                        );
                        println!(
                            "     TLS: {}, Verify: {}",
                            server.tls_enabled, server.tls_verify
                        );
                    }
                }
                ServerAction::Update {
                    host,
                    port,
                    token,
                    permission,
                    tls_enabled,
                    tls_verify,
                } => {
                    handle_server_update(
                        &mut config,
                        &config_path,
                        host.clone(),
                        *port,
                        token.clone(),
                        *permission,
                        *tls_enabled,
                        *tls_verify,
                    )?;
                }
            }
        }
    }

    Ok(())
}

/// Handle server add command with interactive support
#[allow(clippy::too_many_arguments)]
fn handle_server_add(
    config: &mut Config,
    config_path: &Path,
    host: Option<String>,
    default_port: u16,
    token: Option<String>,
    permission: Option<u8>,
    tls_enabled: Option<bool>,
    tls_verify: Option<bool>,
) -> Result<()> {
    use crate::config::ServerConfig;
    use dialoguer::{Confirm, Input, Password, Select};

    // Determine if we need interactive mode
    let needs_interactive = host.is_none() || token.is_none();

    let (final_host, final_port) = if let Some(h) = &host {
        parse_host_port(h, default_port)
    } else {
        // Interactive: prompt for host
        let host_input: String = Input::new()
            .with_prompt("Server address (host:port)")
            .interact_text()?;
        parse_host_port(&host_input, default_port)
    };

    // Check if server already exists
    if config
        .servers
        .iter()
        .any(|s| s.host == final_host && s.port == final_port)
    {
        anyhow::bail!(
            "Server {final_host}:{final_port} already exists. Use 'server update' to modify."
        );
    }

    let final_token = if let Some(t) = token {
        t
    } else {
        // Interactive: prompt for token
        Password::new()
            .with_prompt("Authentication token")
            .interact()?
    };

    let final_permission = if let Some(p) = permission {
        p
    } else if needs_interactive {
        // Interactive: select permission
        let options: Vec<&str> = PERMISSION_OPTIONS.iter().map(|(s, _)| *s).collect();
        let selection = Select::new()
            .with_prompt("Permission level")
            .items(&options)
            .default(0)
            .interact()?;
        PERMISSION_OPTIONS[selection].1
    } else {
        0 // Default to READ_ONLY
    };

    let final_tls_enabled = if let Some(te) = tls_enabled {
        te
    } else if needs_interactive {
        Confirm::new()
            .with_prompt("Enable TLS?")
            .default(false)
            .interact()?
    } else {
        false
    };

    let final_tls_verify = if let Some(tv) = tls_verify {
        tv
    } else if needs_interactive && final_tls_enabled {
        Confirm::new()
            .with_prompt("Verify TLS certificate?")
            .default(true)
            .interact()?
    } else {
        true
    };

    config.servers.push(ServerConfig {
        host: final_host.clone(),
        port: final_port,
        token: final_token,
        management_token: None,
        permission: final_permission,
        tls_enabled: final_tls_enabled,
        tls_verify: final_tls_verify,
    });

    save_config(config, config_path)?;
    println!("Server {final_host}:{final_port} added successfully.");
    println!("Restart the agent to apply changes, or use the management API for hot-reload.");
    Ok(())
}

/// Handle server remove command with interactive support
fn handle_server_remove(
    config: &mut Config,
    config_path: &Path,
    host: Option<String>,
    default_port: u16,
) -> Result<()> {
    use dialoguer::{Confirm, Select};

    let is_interactive = host.is_none();

    let (final_host, final_port) = if let Some(h) = &host {
        parse_host_port(h, default_port)
    } else {
        // Interactive: show server list for selection
        if config.servers.is_empty() {
            anyhow::bail!("No servers configured.");
        }

        let options: Vec<String> = config
            .servers
            .iter()
            .map(|s| format!("{}:{} ({})", s.host, s.port, permission_name(s.permission)))
            .collect();

        let selection = Select::new()
            .with_prompt("Select server to remove")
            .items(&options)
            .interact()?;

        let server = &config.servers[selection];
        (server.host.clone(), server.port)
    };

    // Confirm removal in interactive mode
    if is_interactive {
        let confirm = Confirm::new()
            .with_prompt(format!("Confirm removal of {final_host}:{final_port}?"))
            .default(false)
            .interact()?;

        if !confirm {
            println!("Cancelled.");
            return Ok(());
        }
    }

    let original_len = config.servers.len();
    config
        .servers
        .retain(|s| !(s.host == final_host && s.port == final_port));

    if config.servers.len() == original_len {
        anyhow::bail!("Server {final_host}:{final_port} not found.");
    }

    if config.servers.is_empty() {
        anyhow::bail!("Cannot remove the last server.");
    }

    save_config(config, config_path)?;
    println!("Server {final_host}:{final_port} removed successfully.");
    println!("Restart the agent to apply changes.");
    Ok(())
}

/// Handle server update command with interactive support
#[allow(clippy::too_many_arguments)]
fn handle_server_update(
    config: &mut Config,
    config_path: &Path,
    host: Option<String>,
    default_port: u16,
    token: Option<String>,
    permission: Option<u8>,
    tls_enabled: Option<bool>,
    tls_verify: Option<bool>,
) -> Result<()> {
    use dialoguer::{Confirm, Password, Select};

    let is_interactive = host.is_none();

    let (final_host, final_port) = if let Some(h) = &host {
        parse_host_port(h, default_port)
    } else {
        // Interactive: show server list for selection
        if config.servers.is_empty() {
            anyhow::bail!("No servers configured.");
        }

        let options: Vec<String> = config
            .servers
            .iter()
            .map(|s| format!("{}:{} ({})", s.host, s.port, permission_name(s.permission)))
            .collect();

        let selection = Select::new()
            .with_prompt("Select server to update")
            .items(&options)
            .interact()?;

        let server = &config.servers[selection];
        (server.host.clone(), server.port)
    };

    let server = config
        .servers
        .iter_mut()
        .find(|s| s.host == final_host && s.port == final_port);

    match server {
        Some(s) => {
            let needs_interactive = is_interactive;

            // Update token
            if let Some(t) = token {
                s.token = t;
            } else if needs_interactive {
                let update_token = Confirm::new()
                    .with_prompt("Update authentication token?")
                    .default(false)
                    .interact()?;
                if update_token {
                    s.token = Password::new()
                        .with_prompt("New authentication token")
                        .interact()?;
                }
            }

            // Update permission
            if let Some(p) = permission {
                s.permission = p;
            } else if needs_interactive {
                let update_perm = Confirm::new()
                    .with_prompt("Update permission level?")
                    .default(false)
                    .interact()?;
                if update_perm {
                    let options: Vec<&str> =
                        PERMISSION_OPTIONS.iter().map(|(label, _)| *label).collect();
                    let current_idx = PERMISSION_OPTIONS
                        .iter()
                        .position(|(_, v)| *v == s.permission)
                        .unwrap_or(0);
                    let selection = Select::new()
                        .with_prompt("Permission level")
                        .items(&options)
                        .default(current_idx)
                        .interact()?;
                    s.permission = PERMISSION_OPTIONS[selection].1;
                }
            }

            // Update TLS settings
            if let Some(te) = tls_enabled {
                s.tls_enabled = te;
            } else if needs_interactive {
                let update_tls = Confirm::new()
                    .with_prompt("Update TLS settings?")
                    .default(false)
                    .interact()?;
                if update_tls {
                    s.tls_enabled = Confirm::new()
                        .with_prompt("Enable TLS?")
                        .default(s.tls_enabled)
                        .interact()?;
                }
            }

            if let Some(tv) = tls_verify {
                s.tls_verify = tv;
            } else if needs_interactive && s.tls_enabled {
                s.tls_verify = Confirm::new()
                    .with_prompt("Verify TLS certificate?")
                    .default(s.tls_verify)
                    .interact()?;
            }

            save_config(config, config_path)?;
            println!("Server {final_host}:{final_port} updated successfully.");
            println!("Restart the agent to apply changes.");
        }
        None => {
            anyhow::bail!("Server {final_host}:{final_port} not found.");
        }
    }
    Ok(())
}

fn permission_name(level: u8) -> &'static str {
    match level {
        0 => "READ_ONLY",
        1 => "BASIC_WRITE",
        2 => "SERVICE_CONTROL",
        3 => "SYSTEM_ADMIN",
        _ => "UNKNOWN",
    }
}

fn save_config(config: &Config, path: &Path) -> Result<()> {
    let content = if path.extension().is_some_and(|e| e == "toml") {
        toml::to_string_pretty(config)?
    } else {
        serde_yaml::to_string(config)?
    };

    std::fs::write(path, content)?;
    Ok(())
}

// ============================================================================
// Interactive Menu Functions
// ============================================================================

use crate::i18n::{Lang, detect_language, t};

/// Interactive main menu - entry point for interactive mode
fn interactive_main_menu(args: &Args) -> Result<()> {
    use dialoguer::{Select, theme::ColorfulTheme};

    // Load language from config if available, otherwise detect from system
    let mut lang = if let Some(config_path) = get_config_path(args) {
        if let Ok(config) = Config::load(&config_path) {
            config
                .agent
                .language
                .as_ref()
                .and_then(|s| Lang::from_str(s))
                .unwrap_or_else(detect_language)
        } else {
            detect_language()
        }
    } else {
        detect_language()
    };
    let theme = ColorfulTheme::default();

    loop {
        // Clear screen for better UX (optional)
        print!("\x1B[2J\x1B[1;1H");

        // Print header
        let version = env!("CARGO_PKG_VERSION");
        println!();
        println!("╭──────────────────────────────────────╮");
        println!("│       {} v{}          │", t("menu.title", lang), version);
        println!("╰──────────────────────────────────────╯");
        println!();

        let options = &[
            t("menu.start_agent", lang),
            t("menu.manage_servers", lang),
            t("menu.view_status", lang),
            t("menu.separator", lang),
            t("menu.modify_config", lang),
            t("menu.test_all_connections", lang),
            t("menu.realtime_metrics", lang),
            t("menu.separator", lang),
            t("menu.install_service", lang),
            t("menu.diagnostics", lang),
            t("menu.check_update", lang),
            t("menu.init_config", lang),
            t("menu.view_logs", lang),
            t("menu.export_config", lang),
            t("menu.switch_language", lang),
            t("menu.exit", lang),
        ];

        let selection = Select::with_theme(&theme)
            .with_prompt(t("menu.select_action", lang))
            .items(options)
            .default(0)
            .interact()?;

        match selection {
            0 => {
                // Start Agent
                if let Some(config_path) = get_config_path(args) {
                    let rt = tokio::runtime::Runtime::new()?;
                    if let Err(e) = rt.block_on(run_agent(config_path)) {
                        eprintln!("Error: {e}");
                        wait_for_enter(lang);
                    }
                } else {
                    println!();
                    println!("{}", t("error.no_config", lang));
                    wait_for_enter(lang);
                }
            }
            1 => {
                // Manage Servers
                interactive_server_management(args, lang)?;
            }
            2 => {
                // View Status
                interactive_show_status(args, lang)?;
                wait_for_enter(lang);
            }
            3 | 7 => {
                // Separator - skip immediately back to menu
                continue;
            }
            4 => {
                // Modify Config
                interactive_modify_config(args, lang)?;
            }
            5 => {
                // Test All Connections
                interactive_test_all_connections(args, lang)?;
                wait_for_enter(lang);
            }
            6 => {
                // Realtime Metrics (using ratatui TUI)
                tui::interactive_realtime_metrics(lang)?;
            }
            8 => {
                // Install as Service
                interactive_service_management(args, lang)?;
            }
            9 => {
                // System Diagnostics
                interactive_diagnostics(args, lang)?;
                wait_for_enter(lang);
            }
            10 => {
                // Check for Updates
                interactive_check_update(args, lang)?;
                wait_for_enter(lang);
            }
            11 => {
                // Initialize Config
                interactive_init_config(lang)?;
                wait_for_enter(lang);
            }
            12 => {
                // View Logs
                interactive_view_logs(args, lang)?;
                wait_for_enter(lang);
            }
            13 => {
                // Export Config
                interactive_export_config(args, lang)?;
                wait_for_enter(lang);
            }
            14 => {
                // Switch Language
                lang = interactive_switch_language(args, lang)?;
            }
            15 => {
                // Exit
                break;
            }
            _ => continue, // Unknown selection - go back to menu
        }
    }

    Ok(())
}

/// Interactive language switch - saves preference to config
fn interactive_switch_language(args: &Args, current_lang: Lang) -> Result<Lang> {
    use dialoguer::{Select, theme::ColorfulTheme};

    let theme = ColorfulTheme::default();

    println!();
    println!(
        "{}: {}",
        t("menu.current_language", current_lang),
        match current_lang {
            Lang::En => t("lang.english", current_lang),
            Lang::Zh => t("lang.chinese", current_lang),
        }
    );
    println!();

    let options = &[
        t("lang.english", current_lang),
        t("lang.chinese", current_lang),
    ];

    let selection = Select::with_theme(&theme)
        .with_prompt(t("menu.select_language", current_lang))
        .items(options)
        .default(match current_lang {
            Lang::En => 0,
            Lang::Zh => 1,
        })
        .interact()?;

    let new_lang = match selection {
        0 => Lang::En,
        1 => Lang::Zh,
        _ => current_lang,
    };

    if new_lang != current_lang {
        // Save language preference to config
        if let Some(config_path) = get_config_path(args) {
            if let Ok(mut config) = Config::load(&config_path) {
                config.agent.language = Some(new_lang.as_str().to_string());
                if let Err(e) = save_config(&config, &config_path) {
                    eprintln!("{}: {e}", t("error.save_failed", new_lang));
                }
            }
        }

        println!();
        println!("✓ {}", t("menu.language_switched", new_lang));
        std::thread::sleep(std::time::Duration::from_millis(500));
    }

    Ok(new_lang)
}

/// Interactive server management menu
fn interactive_server_management(args: &Args, lang: Lang) -> Result<()> {
    use dialoguer::{Select, theme::ColorfulTheme};

    let theme = ColorfulTheme::default();

    loop {
        print!("\x1B[2J\x1B[1;1H");
        println!();
        println!("╭──────────────────────────────────────╮");
        println!(
            "│       {}                │",
            t("server.configured_servers", lang)
        );
        println!("╰──────────────────────────────────────╯");
        println!();

        // Load current config
        let config_path = get_config_path(args);
        let config = config_path.as_ref().and_then(|p| Config::load(p).ok());

        let mut options: Vec<String> = Vec::new();
        let mut server_indices: Vec<usize> = Vec::new();

        if let Some(cfg) = &config {
            if cfg.servers.is_empty() {
                println!("  {}", t("server.no_servers", lang));
                println!();
            } else {
                for (i, server) in cfg.servers.iter().enumerate() {
                    options.push(format!(
                        "{}:{} [{}]",
                        server.host,
                        server.port,
                        permission_name(server.permission)
                    ));
                    server_indices.push(i);
                }
            }
        } else {
            println!("  {}", t("error.no_config", lang));
            println!();
        }

        // Add special options
        options.push("──────────────────".to_string());
        options.push(t("server.add_new", lang).to_string());
        options.push(t("server.back_to_menu", lang).to_string());

        let selection = Select::with_theme(&theme)
            .with_prompt(t("menu.select_action", lang))
            .items(&options)
            .default(0)
            .interact()?;

        // Handle selection
        let servers_count = server_indices.len();

        if selection < servers_count {
            // Selected a server - show server action menu
            if let (Some(path), Some(cfg)) = (&config_path, &config) {
                let server = &cfg.servers[server_indices[selection]];
                interactive_server_action(path, server.host.clone(), server.port, lang)?;
            }
        } else if selection == servers_count + 1 {
            // Add new server
            if let Some(path) = &config_path {
                interactive_add_server(path, lang)?;
            } else {
                println!();
                println!("{}", t("error.no_config", lang));
                wait_for_enter(lang);
            }
        } else if selection == servers_count + 2 {
            // Back to main menu
            break;
        }
        // selection == servers_count is the separator, do nothing
    }

    Ok(())
}

/// Interactive server action menu (for a specific server)
fn interactive_server_action(
    config_path: &Path,
    host: String,
    port: u16,
    lang: Lang,
) -> Result<()> {
    use dialoguer::{Confirm, Select, theme::ColorfulTheme};

    let theme = ColorfulTheme::default();

    loop {
        print!("\x1B[2J\x1B[1;1H");
        println!();
        println!("╭──────────────────────────────────────╮");
        println!("│  {host}:{port}                     ");
        println!("╰──────────────────────────────────────╯");
        println!();

        let options = &[
            t("server.update_config", lang),
            t("server.test_connection", lang),
            t("server.delete", lang),
            t("server.back", lang),
        ];

        let selection = Select::with_theme(&theme)
            .with_prompt(t("server.select_action", lang))
            .items(options)
            .default(0)
            .interact()?;

        match selection {
            0 => {
                // Update config
                let mut config = Config::load(config_path)?;
                handle_server_update(
                    &mut config,
                    config_path,
                    Some(format!("{host}:{port}")),
                    port,
                    None,
                    None,
                    None,
                    None,
                )?;
                // Prompt for restart
                prompt_restart_after_config_change(lang)?;
                wait_for_enter(lang);
            }
            1 => {
                // Test connection
                interactive_test_connection(&host, port, config_path, lang)?;
                wait_for_enter(lang);
            }
            2 => {
                // Delete server
                let confirm = Confirm::with_theme(&theme)
                    .with_prompt(t("confirm.delete_server", lang))
                    .default(false)
                    .interact()?;

                if confirm {
                    let mut config = Config::load(config_path)?;
                    handle_server_remove(
                        &mut config,
                        config_path,
                        Some(format!("{host}:{port}")),
                        port,
                    )?;
                    println!("{}", t("status.server_deleted", lang));
                    // Prompt for restart
                    prompt_restart_after_config_change(lang)?;
                    wait_for_enter(lang);
                    break;
                }
            }
            3 => {
                // Back
                break;
            }
            _ => unreachable!(),
        }
    }

    Ok(())
}

/// Interactive add server
fn interactive_add_server(config_path: &Path, lang: Lang) -> Result<()> {
    use dialoguer::{Confirm, Input, Password, Select, theme::ColorfulTheme};

    let theme = ColorfulTheme::default();

    println!();

    // Get server address
    let host_input: String = Input::with_theme(&theme)
        .with_prompt(t("server.enter_address", lang))
        .interact_text()?;

    let (host, port) = parse_host_port(&host_input, 39100);

    // Get token
    let token: String = Password::with_theme(&theme)
        .with_prompt(t("server.enter_token", lang))
        .interact()?;

    // Get permission level
    let permission_options = &[
        t("permission.read_only", lang),
        t("permission.basic_write", lang),
        t("permission.service_control", lang),
        t("permission.system_admin", lang),
    ];

    let perm_selection = Select::with_theme(&theme)
        .with_prompt(t("server.select_permission", lang))
        .items(permission_options)
        .default(0)
        .interact()?;

    let permission = perm_selection as u8;

    // TLS settings
    let tls_enabled = Confirm::with_theme(&theme)
        .with_prompt(t("server.enable_tls", lang))
        .default(false)
        .interact()?;

    let tls_verify = if tls_enabled {
        Confirm::with_theme(&theme)
            .with_prompt(t("server.verify_tls", lang))
            .default(true)
            .interact()?
    } else {
        true
    };

    // Add server
    let mut config = Config::load(config_path)?;

    // Check if server already exists
    if config
        .servers
        .iter()
        .any(|s| s.host == host && s.port == port)
    {
        anyhow::bail!("Server {host}:{port} already exists.");
    }

    config.servers.push(crate::config::ServerConfig {
        host: host.clone(),
        port,
        token,
        management_token: None,
        permission,
        tls_enabled,
        tls_verify,
    });

    save_config(&config, config_path)?;
    println!();
    println!("{}", t("status.server_added", lang));

    // Prompt for restart
    prompt_restart_after_config_change(lang)?;

    Ok(())
}

/// Test connection to a server
fn interactive_test_connection(
    host: &str,
    port: u16,
    config_path: &Path,
    lang: Lang,
) -> Result<()> {
    use crate::connection::grpc::GrpcClient;

    println!();
    println!("{}", t("status.testing_connection", lang));

    // Load config to get server settings
    let config = Config::load(config_path)?;
    let server = config
        .servers
        .iter()
        .find(|s| s.host == host && s.port == port)
        .ok_or_else(|| anyhow::anyhow!("Server not found"))?
        .clone();

    // Create a tokio runtime for the async test
    let rt = tokio::runtime::Runtime::new()?;

    let result = rt.block_on(async { GrpcClient::test_server_connection(&server).await });

    match result {
        Ok(version) => {
            println!(
                "✓ {} {}: {}",
                t("status.connection_success", lang),
                t("status.server_version", lang),
                version
            );
        }
        Err(e) => {
            println!("✗ {}: {}", t("status.connection_failed", lang), e);
        }
    }

    Ok(())
}

/// Show status interactively
fn interactive_show_status(args: &Args, lang: Lang) -> Result<()> {
    println!();
    println!("NanoLink Agent v{}", env!("CARGO_PKG_VERSION"));
    println!();

    match get_config_path(args) {
        Some(config_path) => {
            println!("Config file: {}", config_path.display());

            match Config::load(&config_path) {
                Ok(config) => {
                    println!();
                    println!("{}:", t("server.configured_servers", lang));
                    if config.servers.is_empty() {
                        println!("  {}", t("server.no_servers", lang));
                    } else {
                        for (i, server) in config.servers.iter().enumerate() {
                            println!("  {}. {}:{}", i + 1, server.host, server.port);
                            println!(
                                "     Permission: {} ({})",
                                server.permission,
                                permission_name(server.permission)
                            );
                            println!(
                                "     TLS: {}, Verify: {}",
                                server.tls_enabled, server.tls_verify
                            );
                        }
                    }

                    println!();
                    println!("Settings:");
                    println!(
                        "  Realtime interval: {}ms",
                        config.collector.realtime_interval_ms
                    );
                    println!("  Buffer capacity: {}", config.buffer.capacity);
                    println!(
                        "  Management API: {} (port {})",
                        if config.management.enabled {
                            "enabled"
                        } else {
                            "disabled"
                        },
                        config.management.port
                    );
                }
                Err(e) => {
                    println!("  Error loading config: {e}");
                }
            }
        }
        None => {
            println!("{}", t("error.no_config", lang));
        }
    }

    Ok(())
}

/// Interactive init config
fn interactive_init_config(lang: Lang) -> Result<()> {
    use dialoguer::{Confirm, Input, theme::ColorfulTheme};

    let theme = ColorfulTheme::default();

    println!();

    let output: String = Input::with_theme(&theme)
        .with_prompt(t("init.output_path", lang))
        .default("nanolink.yaml".to_string())
        .interact_text()?;

    let use_toml = Confirm::with_theme(&theme)
        .with_prompt(t("init.use_toml", lang))
        .default(false)
        .interact()?;

    let output_path = PathBuf::from(&output);

    if output_path.exists() {
        anyhow::bail!("Config file already exists: {}", output_path.display());
    }

    let sample_config = Config::sample();
    let content = if use_toml {
        toml::to_string_pretty(&sample_config)?
    } else {
        serde_yaml::to_string(&sample_config)?
    };

    std::fs::write(&output_path, &content)?;
    println!();
    println!("{}: {}", t("init.success", lang), output_path.display());

    Ok(())
}

/// Interactive check for updates
fn interactive_check_update(args: &Args, lang: Lang) -> Result<()> {
    use crate::executor::UpdateExecutor;
    use dialoguer::{Confirm, theme::ColorfulTheme};
    use std::collections::HashMap;

    let theme = ColorfulTheme::default();

    println!();
    println!("{}", t("update.checking", lang));
    println!();

    // Load config to get update settings
    let config = match get_config_path(args) {
        Some(path) => Config::load(&path)?,
        None => Config::sample(),
    };

    // Show update source
    let source_name = match config.update.source {
        crate::config::UpdateSource::Github => "GitHub",
        crate::config::UpdateSource::Cloudflare => "Cloudflare R2",
        crate::config::UpdateSource::Custom => "Custom",
    };
    println!("{}: {}", t("update.source", lang), source_name);
    println!();

    // Create executor and check for updates
    let executor = UpdateExecutor::new(config.update.clone());
    let rt = tokio::runtime::Runtime::new()?;

    let result = rt.block_on(async { executor.check_update().await });

    if !result.success {
        println!("✗ {}: {}", t("update.check_failed", lang), result.error);
        return Ok(());
    }

    let update_info = match result.update_info {
        Some(info) => info,
        None => {
            println!("✗ {}", t("update.check_failed", lang));
            return Ok(());
        }
    };

    println!(
        "{}: {}",
        t("update.current_version", lang),
        update_info.current_version
    );
    println!(
        "{}: {}",
        t("update.latest_version", lang),
        update_info.latest_version
    );
    println!();

    if !update_info.update_available {
        println!(
            "✓ {} ({})",
            t("update.up_to_date", lang),
            update_info.current_version
        );
        return Ok(());
    }

    println!(
        "✓ {}: {} → {}",
        t("update.new_version", lang),
        update_info.current_version,
        update_info.latest_version
    );

    if !update_info.changelog.is_empty() {
        println!();
        println!("Changelog:");
        for line in update_info.changelog.lines().take(10) {
            println!("  {line}");
        }
    }
    println!();

    // Ask if user wants to download
    let download = Confirm::with_theme(&theme)
        .with_prompt(t("update.download_prompt", lang))
        .default(true)
        .interact()?;

    if !download {
        return Ok(());
    }

    println!();
    println!("{}", t("update.downloading", lang));

    let download_result = rt.block_on(async {
        let mut params = HashMap::new();
        params.insert("url".to_string(), update_info.download_url.clone());
        executor.download_update(&params).await
    });

    if !download_result.success {
        println!(
            "✗ {}: {}",
            t("update.download_failed", lang),
            download_result.error
        );
        return Ok(());
    }

    println!("✓ {}", t("update.download_success", lang));
    println!();

    // Ask if user wants to apply
    let apply = Confirm::with_theme(&theme)
        .with_prompt(t("update.apply_prompt", lang))
        .default(true)
        .interact()?;

    if !apply {
        return Ok(());
    }

    println!();
    println!("{}", t("update.applying", lang));

    let apply_result = rt.block_on(async {
        let params = HashMap::new();
        executor.apply_update(&params).await
    });

    if !apply_result.success {
        println!(
            "✗ {}: {}",
            t("update.apply_failed", lang),
            apply_result.error
        );
        return Ok(());
    }

    println!("✓ {}", t("update.success", lang));
    println!();
    println!("{}", t("update.restart_required", lang));
    println!();

    // Ask if user wants to restart
    let restart = Confirm::with_theme(&theme)
        .with_prompt(t("update.restart_prompt", lang))
        .default(true)
        .interact()?;

    if restart {
        println!();
        println!("{}", t("config.restarting", lang));
        if let Err(e) = restart_agent_service() {
            println!("✗ {}: {}", t("config.restart_failed", lang), e);
        } else {
            println!("✓ {}", t("config.restart_success", lang));
        }
    }

    Ok(())
}

/// Restart the agent service (platform-specific)
fn restart_agent_service() -> Result<(), String> {
    #[cfg(target_os = "linux")]
    {
        crate::platform::restart_service()
    }

    #[cfg(target_os = "macos")]
    {
        crate::platform::restart_service()
    }

    #[cfg(target_os = "windows")]
    {
        crate::platform::restart_service()
    }

    #[cfg(not(any(target_os = "linux", target_os = "macos", target_os = "windows")))]
    {
        Err("Restart not supported on this platform".to_string())
    }
}

/// Prompt user to restart agent after config change
fn prompt_restart_after_config_change(lang: Lang) -> Result<()> {
    use dialoguer::{Confirm, theme::ColorfulTheme};

    let theme = ColorfulTheme::default();

    println!();
    let restart = Confirm::with_theme(&theme)
        .with_prompt(t("config.restart_prompt", lang))
        .default(true)
        .interact()?;

    if restart {
        println!("{}", t("config.restarting", lang));
        if let Err(e) = restart_agent_service() {
            println!("✗ {}: {}", t("config.restart_failed", lang), e);
        } else {
            println!("✓ {}", t("config.restart_success", lang));
        }
    } else {
        println!("{}", t("config.restart_manual", lang));
    }

    Ok(())
}

/// Wait for user to press Enter
fn wait_for_enter(lang: Lang) {
    use std::io::{self, Write};

    println!();
    print!("{}", t("misc.press_enter", lang));
    let _ = io::stdout().flush(); // Ignore flush errors (e.g., stdout closed)
    let mut input = String::new();
    let _ = io::stdin().read_line(&mut input);
}

// ============================================================================
// New Interactive Functions
// ============================================================================

/// Interactive modify configuration
fn interactive_modify_config(args: &Args, lang: Lang) -> Result<()> {
    use dialoguer::{Confirm, Input, Select, theme::ColorfulTheme};

    let theme = ColorfulTheme::default();
    let config_path = match get_config_path(args) {
        Some(p) => p,
        None => {
            println!("{}", t("error.no_config", lang));
            wait_for_enter(lang);
            return Ok(());
        }
    };

    loop {
        print!("\x1B[2J\x1B[1;1H");
        println!();
        println!("╭──────────────────────────────────────╮");
        println!("│       {}                    │", t("config.title", lang));
        println!("╰──────────────────────────────────────╯");
        println!();

        let config = Config::load(&config_path)?;

        let options = vec![
            format!(
                "{} ({}: {}ms)",
                t("config.realtime_interval", lang),
                t("config.current_value", lang),
                config.collector.realtime_interval_ms
            ),
            format!(
                "{} ({}: {})",
                t("config.buffer_capacity", lang),
                t("config.current_value", lang),
                config.buffer.capacity
            ),
            format!(
                "{} ({}: {})",
                t("config.data_compensation", lang),
                t("config.current_value", lang),
                if config.buffer.data_compensation {
                    t("common.enabled", lang)
                } else {
                    t("common.disabled", lang)
                }
            ),
            format!(
                "{} ({}: {})",
                t("config.management_enabled", lang),
                t("config.current_value", lang),
                config.management.enabled
            ),
            format!(
                "{} ({}: {})",
                t("config.management_port", lang),
                t("config.current_value", lang),
                config.management.port
            ),
            format!(
                "{} ({}: {}s)",
                t("config.heartbeat_interval", lang),
                t("config.current_value", lang),
                config.agent.heartbeat_interval
            ),
            format!(
                "{} ({}: {})",
                t("config.log_level", lang),
                t("config.current_value", lang),
                config.logging.level
            ),
            t("server.back_to_menu", lang).to_string(),
            t("config.immediate_send", lang).to_string(),
        ];

        let selection = Select::with_theme(&theme)
            .with_prompt(t("config.select_option", lang))
            .items(&options)
            .default(0)
            .interact()?;

        let mut config = Config::load(&config_path)?;

        match selection {
            0 => {
                // Realtime interval (100ms - 1 hour)
                let new_val: u64 = Input::with_theme(&theme)
                    .with_prompt(format!("{} (100-3600000)", t("config.new_value", lang)))
                    .default(config.collector.realtime_interval_ms)
                    .validate_with(|input: &u64| {
                        if *input >= 100 && *input <= 3600000 {
                            Ok(())
                        } else {
                            Err("Value must be between 100 and 3600000 ms")
                        }
                    })
                    .interact_text()?;
                config.collector.realtime_interval_ms = new_val;
                save_config(&config, &config_path)?;
                println!("✓ {}", t("config.saved", lang));
                prompt_restart_after_config_change(lang)?;
            }
            1 => {
                // Buffer capacity (10 - 100000)
                let new_val: usize = Input::with_theme(&theme)
                    .with_prompt(format!("{} (10-100000)", t("config.new_value", lang)))
                    .default(config.buffer.capacity)
                    .validate_with(|input: &usize| {
                        if *input >= 10 && *input <= 100000 {
                            Ok(())
                        } else {
                            Err("Value must be between 10 and 100000")
                        }
                    })
                    .interact_text()?;
                config.buffer.capacity = new_val;
                save_config(&config, &config_path)?;
                println!("✓ {}", t("config.saved", lang));
                prompt_restart_after_config_change(lang)?;
            }
            2 => {
                // Data compensation enabled
                let new_val = Confirm::with_theme(&theme)
                    .with_prompt(t("config.data_compensation_prompt", lang))
                    .default(config.buffer.data_compensation)
                    .interact()?;
                config.buffer.data_compensation = new_val;
                save_config(&config, &config_path)?;
                println!("✓ {}", t("config.saved", lang));
                if new_val {
                    println!("{}", t("config.data_compensation_info", lang));
                }
                prompt_restart_after_config_change(lang)?;
            }
            3 => {
                // Management API enabled
                let new_val = Confirm::with_theme(&theme)
                    .with_prompt(t("config.management_enabled", lang))
                    .default(config.management.enabled)
                    .interact()?;
                config.management.enabled = new_val;
                if new_val && config.management.api_token.is_none() {
                    let token: String = Input::with_theme(&theme)
                        .with_prompt(t("config.management_token", lang))
                        .interact_text()?;
                    if !token.is_empty() {
                        config.management.api_token = Some(token);
                    }
                }
                save_config(&config, &config_path)?;
                println!("✓ {}", t("config.saved", lang));
                prompt_restart_after_config_change(lang)?;
            }
            4 => {
                // Management port (1-65535)
                let new_val: u16 = Input::with_theme(&theme)
                    .with_prompt(format!("{} (1-65535)", t("config.new_value", lang)))
                    .default(config.management.port)
                    .validate_with(|input: &u16| {
                        if *input >= 1 {
                            Ok(())
                        } else {
                            Err("Port must be between 1 and 65535")
                        }
                    })
                    .interact_text()?;
                config.management.port = new_val;
                save_config(&config, &config_path)?;
                println!("✓ {}", t("config.saved", lang));
                prompt_restart_after_config_change(lang)?;
            }
            5 => {
                // Heartbeat interval (1 - 3600 seconds)
                let new_val: u64 = Input::with_theme(&theme)
                    .with_prompt(format!("{} (1-3600)", t("config.new_value", lang)))
                    .default(config.agent.heartbeat_interval)
                    .validate_with(|input: &u64| {
                        if *input >= 1 && *input <= 3600 {
                            Ok(())
                        } else {
                            Err("Value must be between 1 and 3600 seconds")
                        }
                    })
                    .interact_text()?;
                config.agent.heartbeat_interval = new_val;
                save_config(&config, &config_path)?;
                println!("✓ {}", t("config.saved", lang));
                prompt_restart_after_config_change(lang)?;
            }
            6 => {
                // Log level
                let levels = ["trace", "debug", "info", "warn", "error"];
                let current_idx = levels
                    .iter()
                    .position(|&l| l == config.logging.level)
                    .unwrap_or(2);
                let sel = Select::with_theme(&theme)
                    .with_prompt(t("config.log_level", lang))
                    .items(levels)
                    .default(current_idx)
                    .interact()?;
                config.logging.level = levels[sel].to_string();
                save_config(&config, &config_path)?;
                println!("✓ {}", t("config.saved", lang));
                prompt_restart_after_config_change(lang)?;
            }
            7 => {
                // Immediate send - trigger management API
                if !config.management.enabled {
                    println!();
                    println!("✗ {}", t("config.management_required", lang));
                    wait_for_enter(lang);
                    continue;
                }

                println!();
                println!("  {}", t("config.immediate_send_desc", lang));

                let confirm = Confirm::with_theme(&theme)
                    .with_prompt(t("config.immediate_send", lang))
                    .default(true)
                    .interact()?;

                if confirm {
                    // Call management API to trigger immediate reconnect
                    use std::io::{Read, Write};
                    use std::net::TcpStream;

                    let addr = format!("127.0.0.1:{}", config.management.port);
                    let socket_addr: std::net::SocketAddr = match addr.parse() {
                        Ok(a) => a,
                        Err(_) => {
                            println!("✗ {}", t("config.send_failed", lang));
                            wait_for_enter(lang);
                            continue;
                        }
                    };
                    match TcpStream::connect_timeout(
                        &socket_addr,
                        std::time::Duration::from_secs(5),
                    ) {
                        Ok(mut stream) => {
                            // Build request with auth header if token is configured
                            let auth_header = match &config.management.api_token {
                                Some(token) if !token.is_empty() => {
                                    format!("Authorization: Bearer {token}\r\n")
                                }
                                _ => String::new(),
                            };
                            let request = format!(
                                "POST /api/connection/reconnect HTTP/1.1\r\nHost: 127.0.0.1:{}\r\n{}Content-Length: 0\r\n\r\n",
                                config.management.port, auth_header
                            );
                            if stream.write_all(request.as_bytes()).is_ok() {
                                let mut response = [0u8; 512];
                                if stream.read(&mut response).is_ok() {
                                    let response_str = String::from_utf8_lossy(&response);
                                    // Check HTTP status line (e.g., "HTTP/1.1 200 OK")
                                    let first_line = response_str.lines().next().unwrap_or("");
                                    if first_line.contains(" 200 ") {
                                        println!("✓ {}", t("config.send_triggered", lang));
                                    } else if first_line.contains(" 401 ") {
                                        println!(
                                            "✗ {}: Unauthorized",
                                            t("config.send_failed", lang)
                                        );
                                    } else {
                                        println!("✗ {}", t("config.send_failed", lang));
                                    }
                                }
                            }
                        }
                        Err(_) => {
                            println!("✗ {}", t("config.agent_not_running", lang));
                        }
                    }
                    wait_for_enter(lang);
                }
            }
            8 => break,
            _ => {}
        }
    }

    Ok(())
}

/// Interactive test all connections
fn interactive_test_all_connections(args: &Args, lang: Lang) -> Result<()> {
    use crate::connection::grpc::GrpcClient;

    println!();
    println!("╭──────────────────────────────────────╮");
    println!("│       {}              │", t("test.title", lang));
    println!("╰──────────────────────────────────────╯");
    println!();

    let config_path = match get_config_path(args) {
        Some(p) => p,
        None => {
            println!("{}", t("error.no_config", lang));
            return Ok(());
        }
    };

    let config = Config::load(&config_path)?;
    let mut success_count = 0;
    let total = config.servers.len();

    let rt = tokio::runtime::Runtime::new()?;

    for server in &config.servers {
        print!(
            "  {} {}:{}... ",
            t("test.testing", lang),
            server.host,
            server.port
        );
        std::io::Write::flush(&mut std::io::stdout())?;

        let result = rt.block_on(async { GrpcClient::test_server_connection(server).await });

        match result {
            Ok(version) => {
                println!("✓ {} (v{})", t("test.success", lang), version);
                success_count += 1;
            }
            Err(e) => {
                println!("✗ {}: {}", t("test.failed", lang), e);
            }
        }
    }

    println!();
    println!(
        "{}: {}/{} {}",
        t("test.summary", lang),
        success_count,
        total,
        t("test.passed", lang)
    );

    Ok(())
}

/// RAII guard for terminal raw mode - ensures cleanup on drop
struct RawModeGuard;

impl RawModeGuard {
    fn new() -> Result<Self> {
        crossterm::terminal::enable_raw_mode()?;
        Ok(Self)
    }
}

impl Drop for RawModeGuard {
    fn drop(&mut self) {
        let _ = crossterm::terminal::disable_raw_mode();
    }
}

/// Format bytes to human readable format (KB, MB, GB, TB)
fn format_bytes(bytes: u64) -> (f64, &'static str) {
    const KB: u64 = 1024;
    const MB: u64 = KB * 1024;
    const GB: u64 = MB * 1024;
    const TB: u64 = GB * 1024;

    if bytes >= TB {
        (bytes as f64 / TB as f64, "TB")
    } else if bytes >= GB {
        (bytes as f64 / GB as f64, "GB")
    } else if bytes >= MB {
        (bytes as f64 / MB as f64, "MB")
    } else if bytes >= KB {
        (bytes as f64 / KB as f64, "KB")
    } else {
        (bytes as f64, "B")
    }
}

/// Truncate string to max length with ellipsis
fn truncate_str(s: &str, max_len: usize) -> String {
    if s.len() <= max_len {
        s.to_string()
    } else if max_len > 3 {
        format!("{}...", &s[..max_len - 3])
    } else {
        s[..max_len].to_string()
    }
}

/// Interactive realtime metrics viewer with multiple tabs (legacy, replaced by tui module)
#[allow(dead_code)]
fn interactive_realtime_metrics_legacy(lang: Lang) -> Result<()> {
    use crossterm::event::{self, Event, KeyCode, KeyEventKind};
    use std::time::Duration;
    use sysinfo::{Disks, Networks, System};

    let mut system = System::new_all();
    let mut disks = Disks::new_with_refreshed_list();
    let mut networks = Networks::new_with_refreshed_list();

    let tabs = [
        t("metrics.cpu_overview", lang),
        t("metrics.cpu_cores", lang),
        t("metrics.memory", lang),
        t("metrics.disk_io", lang),
        t("metrics.network", lang),
        t("metrics.gpu", lang),
        t("metrics.processes", lang),
        t("metrics.ports", lang),
    ];
    let mut current_tab: usize = 0;
    let mut scroll_offset: usize = 0;
    let mut max_scroll: usize; // Track max scrollable items

    // RAII guard ensures terminal is restored even on panic/error
    let _raw_mode_guard = RawModeGuard::new()?;

    // Helper to create progress bar
    fn progress_bar(percent: f64, width: usize, warn_threshold: f64) -> String {
        let filled = (percent as usize * width / 100).min(width);
        let mut bar = String::with_capacity(width + 2);
        bar.push('[');
        for i in 0..width {
            if i < filled {
                if percent > warn_threshold {
                    bar.push('!');
                } else {
                    bar.push('█');
                }
            } else {
                bar.push('░');
            }
        }
        bar.push(']');
        bar
    }

    loop {
        print!("\x1B[2J\x1B[1;1H");

        // ═══════════════════════════════════════════════════════════════════
        // Header
        // ═══════════════════════════════════════════════════════════════════
        println!("┌─────────────────────────────────────────────────────────────────────────────┐");
        println!(
            "│                     🖥  {}                      │",
            t("metrics.title", lang)
        );
        println!("├─────────────────────────────────────────────────────────────────────────────┤");

        // Tab bar with better styling
        print!("│  ");
        for (i, tab) in tabs.iter().enumerate() {
            if i == current_tab {
                print!("[ \x1B[1;36m{tab}\x1B[0m ]"); // Cyan bold for active
            } else {
                print!("  {tab}  ");
            }
        }
        println!("  │");
        println!("├─────────────────────────────────────────────────────────────────────────────┤");
        println!("│  \x1B[90m{}\x1B[0m", t("metrics.press_q", lang));
        println!("└─────────────────────────────────────────────────────────────────────────────┘");
        println!();

        // Refresh data
        system.refresh_all();
        disks.refresh(false);
        networks.refresh(false);

        match current_tab {
            0 => {
                // ═══════════════════════════════════════════════════════════
                // CPU Overview
                // ═══════════════════════════════════════════════════════════
                let cpu_usage = system.global_cpu_usage();

                println!("  ┌─ CPU Overview ──────────────────────────────────────────────────┐");
                println!("  │                                                                 │");
                println!(
                    "  │  {} : \x1B[1;33m{:>5.1}%\x1B[0m                                            │",
                    t("metrics.usage", lang),
                    cpu_usage
                );
                println!(
                    "  │  Logical Cores: {}                                              │",
                    system.cpus().len()
                );
                println!("  │                                                                 │");
                println!("  │  {}  │", progress_bar(cpu_usage as f64, 50, 90.0));
                println!("  │                                                                 │");

                #[cfg(unix)]
                {
                    let load = System::load_average();
                    println!(
                        "  │  Load Average: \x1B[36m{:.2}\x1B[0m  \x1B[36m{:.2}\x1B[0m  \x1B[36m{:.2}\x1B[0m  (1m / 5m / 15m)       │",
                        load.one, load.five, load.fifteen
                    );
                    println!(
                        "  │                                                                 │"
                    );
                }

                println!("  └─────────────────────────────────────────────────────────────────┘");
            }
            1 => {
                // ═══════════════════════════════════════════════════════════
                // CPU Cores
                // ═══════════════════════════════════════════════════════════
                let cpus = system.cpus();
                let start = scroll_offset.min(cpus.len().saturating_sub(16));
                let end = (start + 16).min(cpus.len());

                println!("  ┌─ CPU Cores ─────────────────────────────────────────────────────┐");
                println!("  │  Core       Usage                                               │");
                println!("  ├─────────────────────────────────────────────────────────────────┤");

                for (i, cpu) in cpus.iter().enumerate().skip(start).take(end - start) {
                    let usage = cpu.cpu_usage();
                    let bar = progress_bar(usage as f64, 30, 90.0);
                    let color = if usage > 90.0 {
                        "31"
                    } else if usage > 70.0 {
                        "33"
                    } else {
                        "32"
                    };
                    println!(
                        "  │  Core {i:>2}  \x1B[{color}m{usage:>5.1}%\x1B[0m  {bar}            │"
                    );
                }

                println!("  ├─────────────────────────────────────────────────────────────────┤");
                if cpus.len() > 16 {
                    println!(
                        "  │  \x1B[90mShowing {}-{} of {} (↑↓ to scroll)\x1B[0m                         │",
                        start + 1,
                        end,
                        cpus.len()
                    );
                } else {
                    println!(
                        "  │  \x1B[90mTotal {} cores\x1B[0m                                              │",
                        cpus.len()
                    );
                }
                println!("  └─────────────────────────────────────────────────────────────────┘");
            }
            2 => {
                // ═══════════════════════════════════════════════════════════
                // Memory
                // ═══════════════════════════════════════════════════════════
                let total = system.total_memory();
                let used = system.used_memory();
                let swap_total = system.total_swap();
                let swap_used = system.used_swap();

                let mem_percent = if total > 0 {
                    (used as f64 / total as f64) * 100.0
                } else {
                    0.0
                };

                println!("  ┌─ Memory ────────────────────────────────────────────────────────┐");
                println!("  │                                                                 │");
                println!(
                    "  │  \x1B[1mRAM\x1B[0m                                                            │"
                );
                println!(
                    "  │  Used: \x1B[33m{:>6.2} GB\x1B[0m / {:>6.2} GB  (\x1B[1m{:>5.1}%\x1B[0m)                    │",
                    used as f64 / 1024.0 / 1024.0 / 1024.0,
                    total as f64 / 1024.0 / 1024.0 / 1024.0,
                    mem_percent
                );
                println!(
                    "  │  {}                               │",
                    progress_bar(mem_percent, 40, 90.0)
                );
                println!("  │                                                                 │");

                if swap_total > 0 {
                    let swap_percent = (swap_used as f64 / swap_total as f64) * 100.0;
                    println!(
                        "  ├─────────────────────────────────────────────────────────────────┤"
                    );
                    println!(
                        "  │  \x1B[1mSwap\x1B[0m                                                           │"
                    );
                    println!(
                        "  │  Used: \x1B[33m{:>6.2} GB\x1B[0m / {:>6.2} GB  (\x1B[1m{:>5.1}%\x1B[0m)                    │",
                        swap_used as f64 / 1024.0 / 1024.0 / 1024.0,
                        swap_total as f64 / 1024.0 / 1024.0 / 1024.0,
                        swap_percent
                    );
                    println!(
                        "  │  {}                               │",
                        progress_bar(swap_percent, 40, 90.0)
                    );
                    println!(
                        "  │                                                                 │"
                    );
                }

                println!("  └─────────────────────────────────────────────────────────────────┘");
            }
            3 => {
                // ═══════════════════════════════════════════════════════════
                // Disk I/O
                // ═══════════════════════════════════════════════════════════
                println!("  ┌─ Disk Storage ──────────────────────────────────────────────────┐");

                for (idx, disk) in disks.list().iter().enumerate() {
                    let total = disk.total_space();
                    let available = disk.available_space();
                    let used = total - available;
                    let percent = if total > 0 {
                        (used as f64 / total as f64) * 100.0
                    } else {
                        0.0
                    };

                    if idx > 0 {
                        println!(
                            "  ├─────────────────────────────────────────────────────────────────┤"
                        );
                    }
                    println!(
                        "  │                                                                 │"
                    );
                    println!(
                        "  │  \x1B[1m{}\x1B[0m  [{}]",
                        disk.mount_point().display(),
                        disk.file_system().to_string_lossy()
                    );
                    let color = if percent > 90.0 {
                        "31"
                    } else if percent > 80.0 {
                        "33"
                    } else {
                        "32"
                    };
                    println!(
                        "  │  Used: \x1B[{color}m{:>6.1} GB\x1B[0m / {:>6.1} GB  (\x1B[{color}m{:>5.1}%\x1B[0m)                   │",
                        used as f64 / 1024.0 / 1024.0 / 1024.0,
                        total as f64 / 1024.0 / 1024.0 / 1024.0,
                        percent
                    );
                    println!(
                        "  │  {}                               │",
                        progress_bar(percent, 40, 90.0)
                    );
                }
                println!("  │                                                                 │");
                println!("  └─────────────────────────────────────────────────────────────────┘");
            }
            4 => {
                // ═══════════════════════════════════════════════════════════
                // Network
                // ═══════════════════════════════════════════════════════════
                println!("  ┌─ Network Interfaces ────────────────────────────────────────────┐");
                println!("  │  Interface            ↓ Received           ↑ Transmitted       │");
                println!("  ├─────────────────────────────────────────────────────────────────┤");

                for (name, data) in networks.list() {
                    let rx = data.received();
                    let tx = data.transmitted();

                    let (rx_val, rx_unit) = format_bytes(rx);
                    let (tx_val, tx_unit) = format_bytes(tx);

                    println!(
                        "  │  {:<18}  \x1B[32m{:>8.2} {:<2}\x1B[0m         \x1B[36m{:>8.2} {:<2}\x1B[0m        │",
                        truncate_str(name, 18),
                        rx_val,
                        rx_unit,
                        tx_val,
                        tx_unit
                    );
                }

                println!("  │                                                                 │");
                println!("  └─────────────────────────────────────────────────────────────────┘");
            }
            5 => {
                // ═══════════════════════════════════════════════════════════
                // GPU
                // ═══════════════════════════════════════════════════════════
                let gpu_collector = crate::collector::GpuCollector::new();
                let gpus = gpu_collector.collect();

                println!("  ┌─ GPU Information ───────────────────────────────────────────────┐");

                if gpus.is_empty() {
                    println!(
                        "  │                                                                 │"
                    );
                    println!(
                        "  │  \x1B[90m{}\x1B[0m                                             │",
                        t("metrics.no_gpu", lang)
                    );
                    println!(
                        "  │                                                                 │"
                    );
                } else {
                    for (idx, gpu) in gpus.iter().enumerate() {
                        if idx > 0 {
                            println!(
                                "  ├─────────────────────────────────────────────────────────────────┤"
                            );
                        }
                        println!(
                            "  │                                                                 │"
                        );
                        println!(
                            "  │  \x1B[1mGPU {}: {}\x1B[0m",
                            gpu.index,
                            truncate_str(&gpu.name, 50)
                        );
                        println!(
                            "  │  {} : \x1B[33m{:>5.1}%\x1B[0m  {}                      │",
                            t("metrics.usage", lang),
                            gpu.usage_percent,
                            progress_bar(gpu.usage_percent, 25, 90.0)
                        );

                        let mem_total_mb = gpu.memory_total as f64 / 1024.0 / 1024.0;
                        let mem_used_mb = gpu.memory_used as f64 / 1024.0 / 1024.0;
                        let mem_percent = if mem_total_mb > 0.0 {
                            (mem_used_mb / mem_total_mb) * 100.0
                        } else {
                            0.0
                        };
                        println!(
                            "  │  Memory: \x1B[36m{mem_used_mb:>6.0} MB\x1B[0m / {mem_total_mb:>6.0} MB  ({mem_percent:>5.1}%)                   │"
                        );

                        if gpu.temperature > 0.0 {
                            let temp_color = if gpu.temperature > 80.0 {
                                "31"
                            } else if gpu.temperature > 60.0 {
                                "33"
                            } else {
                                "32"
                            };
                            println!(
                                "  │  {} : \x1B[{temp_color}m{:>3.0}°C\x1B[0m                                            │",
                                t("metrics.temperature", lang),
                                gpu.temperature
                            );
                        }
                        if gpu.power_watts > 0 {
                            println!(
                                "  │  {} : {:>3}W / {:>3}W                                       │",
                                t("metrics.power", lang),
                                gpu.power_watts,
                                gpu.power_limit_watts
                            );
                        }
                    }
                }
                println!("  │                                                                 │");
                println!("  └─────────────────────────────────────────────────────────────────┘");
            }
            6 => {
                // ═══════════════════════════════════════════════════════════
                // Processes
                // ═══════════════════════════════════════════════════════════
                let mut procs: Vec<_> = system.processes().iter().collect();
                procs.sort_by(|a, b| {
                    b.1.cpu_usage()
                        .partial_cmp(&a.1.cpu_usage())
                        .unwrap_or(std::cmp::Ordering::Equal)
                });

                let total_mem = system.total_memory() as f64;
                let start = scroll_offset.min(procs.len().saturating_sub(15));

                println!("  ┌─ Top Processes (by CPU) ───────────────────────────────────────┐");
                println!(
                    "  │  \x1B[1m{:>7}  {:>7}  {:>7}  {:>10}  {:<24}\x1B[0m │",
                    "PID", "CPU%", "MEM%", "MEM(MB)", "NAME"
                );
                println!("  ├─────────────────────────────────────────────────────────────────┤");

                for (pid, proc) in procs.iter().skip(start).take(15) {
                    let mem_percent = if total_mem > 0.0 {
                        (proc.memory() as f64 / total_mem) * 100.0
                    } else {
                        0.0
                    };
                    let cpu_color = if proc.cpu_usage() > 50.0 {
                        "31"
                    } else if proc.cpu_usage() > 10.0 {
                        "33"
                    } else {
                        "0"
                    };
                    println!(
                        "  │  {:>7}  \x1B[{cpu_color}m{:>6.1}%\x1B[0m  {:>6.1}%  {:>10.1}  {:<24} │",
                        pid.as_u32(),
                        proc.cpu_usage(),
                        mem_percent,
                        proc.memory() as f64 / 1024.0 / 1024.0,
                        truncate_str(&proc.name().to_string_lossy(), 24)
                    );
                }

                println!("  ├─────────────────────────────────────────────────────────────────┤");
                if procs.len() > 15 {
                    println!(
                        "  │  \x1B[90mShowing {}-{} of {} (↑↓ to scroll)\x1B[0m                         │",
                        start + 1,
                        (start + 15).min(procs.len()),
                        procs.len()
                    );
                } else {
                    println!(
                        "  │  \x1B[90mTotal {} processes\x1B[0m                                          │",
                        procs.len()
                    );
                }
                println!("  └─────────────────────────────────────────────────────────────────┘");
            }
            7 => {
                // ═══════════════════════════════════════════════════════════
                // Listening Ports
                // ═══════════════════════════════════════════════════════════
                let ports = get_listening_ports_legacy();
                let start = scroll_offset.min(ports.len().saturating_sub(15));

                println!("  ┌─ Listening Ports ──────────────────────────────────────────────┐");
                println!(
                    "  │  \x1B[1m{:>7}  {:>8}  {:>22}  {:<18}\x1B[0m │",
                    "PID", "PROTO", "ADDRESS", "PROCESS"
                );
                println!("  ├─────────────────────────────────────────────────────────────────┤");

                for (pid, proto, addr, name) in ports.iter().skip(start).take(15) {
                    let proto_color = if proto.contains("TCP") { "32" } else { "36" };
                    println!(
                        "  │  {:>7}  \x1B[{proto_color}m{:>8}\x1B[0m  {:>22}  {:<18} │",
                        pid,
                        proto,
                        addr,
                        truncate_str(name, 18)
                    );
                }

                println!("  ├─────────────────────────────────────────────────────────────────┤");
                if ports.len() > 15 {
                    println!(
                        "  │  \x1B[90mShowing {}-{} of {} (↑↓ to scroll)\x1B[0m                         │",
                        start + 1,
                        (start + 15).min(ports.len()),
                        ports.len()
                    );
                } else {
                    println!(
                        "  │  \x1B[90mTotal {} listening ports\x1B[0m                                    │",
                        ports.len()
                    );
                }
                println!("  └─────────────────────────────────────────────────────────────────┘");
            }
            _ => {}
        }

        // Update max_scroll based on current tab content
        max_scroll = match current_tab {
            1 => system.cpus().len().saturating_sub(16), // CPU Cores
            6 => system.processes().len().saturating_sub(15), // Processes
            7 => get_listening_ports_legacy().len().saturating_sub(15), // Ports
            _ => 0,
        };

        // Handle input
        if event::poll(Duration::from_millis(500))? {
            if let Event::Key(key) = event::read()? {
                if key.kind == KeyEventKind::Press {
                    match key.code {
                        KeyCode::Char('q') | KeyCode::Esc => break,
                        KeyCode::Left => {
                            current_tab = current_tab.saturating_sub(1);
                            scroll_offset = 0;
                        }
                        KeyCode::Right => {
                            current_tab = (current_tab + 1).min(tabs.len() - 1);
                            scroll_offset = 0;
                        }
                        KeyCode::Up => {
                            scroll_offset = scroll_offset.saturating_sub(1);
                        }
                        KeyCode::Down => {
                            // Limit scroll to max_scroll
                            if scroll_offset < max_scroll {
                                scroll_offset += 1;
                            }
                        }
                        KeyCode::Tab => {
                            current_tab = (current_tab + 1) % tabs.len();
                            scroll_offset = 0;
                        }
                        _ => {}
                    }
                }
            }
        }
    }

    // RAII guard automatically restores terminal on drop
    Ok(())
}

/// Get listening ports (platform-specific) - legacy, moved to tui module
#[allow(dead_code)]
fn get_listening_ports_legacy() -> Vec<(String, String, String, String)> {
    let mut ports = Vec::new();

    #[cfg(target_os = "linux")]
    {
        use std::process::Command;
        if let Ok(output) = Command::new("ss").args(["-tulnp"]).output() {
            let stdout = String::from_utf8_lossy(&output.stdout);
            for line in stdout.lines().skip(1) {
                let parts: Vec<&str> = line.split_whitespace().collect();
                if parts.len() >= 5 {
                    let proto = parts[0].to_string();
                    let addr = parts[4].to_string();
                    let process_info = parts.get(6).unwrap_or(&"").to_string();

                    // Extract PID and process name from users:(("name",pid=123,fd=4))
                    let (pid, name) = if let Some(start) = process_info.find("pid=") {
                        let pid_part = &process_info[start + 4..];
                        let pid: String = pid_part.chars().take_while(|c| c.is_numeric()).collect();
                        let name = process_info
                            .split("((\"")
                            .nth(1)
                            .and_then(|s| s.split("\"").next())
                            .unwrap_or("-")
                            .to_string();
                        (pid, name)
                    } else {
                        ("-".to_string(), "-".to_string())
                    };

                    ports.push((pid, proto, addr, name));
                }
            }
        }
    }

    #[cfg(target_os = "windows")]
    {
        use std::process::Command;
        if let Ok(output) = Command::new("netstat").args(["-ano"]).output() {
            let stdout = String::from_utf8_lossy(&output.stdout);
            for line in stdout.lines() {
                if line.contains("LISTENING") {
                    let parts: Vec<&str> = line.split_whitespace().collect();
                    if parts.len() >= 5 {
                        let proto = parts[0].to_string();
                        let addr = parts[1].to_string();
                        let pid = parts[4].to_string();
                        ports.push((pid, proto, addr, "-".to_string()));
                    }
                }
            }
        }
    }

    #[cfg(target_os = "macos")]
    {
        use std::process::Command;
        if let Ok(output) = Command::new("lsof")
            .args(["-iTCP", "-sTCP:LISTEN", "-n", "-P"])
            .output()
        {
            let stdout = String::from_utf8_lossy(&output.stdout);
            for line in stdout.lines().skip(1) {
                let parts: Vec<&str> = line.split_whitespace().collect();
                if parts.len() >= 9 {
                    let name = parts[0].to_string();
                    let pid = parts[1].to_string();
                    let addr = parts[8].to_string();
                    ports.push((pid, "TCP".to_string(), addr, name));
                }
            }
        }
    }

    ports
}

/// Interactive service management
fn interactive_service_management(args: &Args, lang: Lang) -> Result<()> {
    use dialoguer::{Select, theme::ColorfulTheme};

    let theme = ColorfulTheme::default();

    loop {
        print!("\x1B[2J\x1B[1;1H");
        println!();
        println!("╭──────────────────────────────────────╮");
        println!("│       {}          │", t("service.title", lang));
        println!("╰──────────────────────────────────────╯");
        println!();

        let options = &[
            t("service.install", lang),
            t("service.uninstall", lang),
            t("service.start", lang),
            t("service.stop", lang),
            t("service.status", lang),
            t("server.back_to_menu", lang),
        ];

        let selection = Select::with_theme(&theme)
            .with_prompt(t("menu.select_action", lang))
            .items(options)
            .default(0)
            .interact()?;

        match selection {
            0 => {
                // Install
                println!("{}", t("service.installing", lang));
                #[cfg(target_os = "windows")]
                {
                    let config_path = get_config_path(args);
                    match crate::platform::install_service(config_path) {
                        Ok(_) => println!("✓ {}", t("service.installed", lang)),
                        Err(e) => println!("✗ {}: {}", t("service.error", lang), e),
                    }
                }
                #[cfg(target_os = "linux")]
                {
                    match install_systemd_service(args) {
                        Ok(_) => println!("✓ {}", t("service.installed", lang)),
                        Err(e) => println!("✗ {}: {}", t("service.error", lang), e),
                    }
                }
                #[cfg(target_os = "macos")]
                {
                    match install_launchd_service(args) {
                        Ok(_) => println!("✓ {}", t("service.installed", lang)),
                        Err(e) => println!("✗ {}: {}", t("service.error", lang), e),
                    }
                }
                #[cfg(not(any(target_os = "windows", target_os = "linux", target_os = "macos")))]
                {
                    println!("{}", t("service.not_supported", lang));
                }
                wait_for_enter(lang);
            }
            1 => {
                // Uninstall
                println!("{}", t("service.uninstalling", lang));
                #[cfg(target_os = "windows")]
                {
                    match crate::platform::uninstall_service() {
                        Ok(_) => println!("✓ {}", t("service.uninstalled", lang)),
                        Err(e) => println!("✗ {}: {}", t("service.error", lang), e),
                    }
                }
                #[cfg(target_os = "linux")]
                {
                    match uninstall_systemd_service() {
                        Ok(_) => println!("✓ {}", t("service.uninstalled", lang)),
                        Err(e) => println!("✗ {}: {}", t("service.error", lang), e),
                    }
                }
                #[cfg(target_os = "macos")]
                {
                    match uninstall_launchd_service() {
                        Ok(_) => println!("✓ {}", t("service.uninstalled", lang)),
                        Err(e) => println!("✗ {}: {}", t("service.error", lang), e),
                    }
                }
                #[cfg(not(any(target_os = "windows", target_os = "linux", target_os = "macos")))]
                {
                    println!("{}", t("service.not_supported", lang));
                }
                wait_for_enter(lang);
            }
            2 => {
                // Start
                println!("{}", t("service.starting", lang));
                #[cfg(target_os = "windows")]
                {
                    match crate::platform::start_service() {
                        Ok(_) => println!("✓ {}", t("service.started", lang)),
                        Err(e) => println!("✗ {}: {}", t("service.error", lang), e),
                    }
                }
                #[cfg(target_os = "linux")]
                {
                    match std::process::Command::new("systemctl")
                        .args(["start", "nanolink-agent"])
                        .status()
                    {
                        Ok(s) if s.success() => println!("✓ {}", t("service.started", lang)),
                        _ => println!("✗ {}", t("service.error", lang)),
                    }
                }
                #[cfg(target_os = "macos")]
                {
                    match std::process::Command::new("launchctl")
                        .args(["load", "/Library/LaunchDaemons/com.nanolink.agent.plist"])
                        .status()
                    {
                        Ok(s) if s.success() => println!("✓ {}", t("service.started", lang)),
                        _ => println!("✗ {}", t("service.error", lang)),
                    }
                }
                #[cfg(not(any(target_os = "windows", target_os = "linux", target_os = "macos")))]
                {
                    println!("{}", t("service.not_supported", lang));
                }
                wait_for_enter(lang);
            }
            3 => {
                // Stop
                println!("{}", t("service.stopping", lang));
                #[cfg(target_os = "windows")]
                {
                    match crate::platform::stop_service() {
                        Ok(_) => println!("✓ {}", t("service.stopped", lang)),
                        Err(e) => println!("✗ {}: {}", t("service.error", lang), e),
                    }
                }
                #[cfg(target_os = "linux")]
                {
                    match std::process::Command::new("systemctl")
                        .args(["stop", "nanolink-agent"])
                        .status()
                    {
                        Ok(s) if s.success() => println!("✓ {}", t("service.stopped", lang)),
                        _ => println!("✗ {}", t("service.error", lang)),
                    }
                }
                #[cfg(target_os = "macos")]
                {
                    match std::process::Command::new("launchctl")
                        .args(["unload", "/Library/LaunchDaemons/com.nanolink.agent.plist"])
                        .status()
                    {
                        Ok(s) if s.success() => println!("✓ {}", t("service.stopped", lang)),
                        _ => println!("✗ {}", t("service.error", lang)),
                    }
                }
                #[cfg(not(any(target_os = "windows", target_os = "linux", target_os = "macos")))]
                {
                    println!("{}", t("service.not_supported", lang));
                }
                wait_for_enter(lang);
            }
            4 => {
                // Status
                #[cfg(target_os = "windows")]
                {
                    match crate::platform::query_service_status() {
                        Ok(status) => println!("{status}"),
                        Err(e) => println!("✗ {}: {}", t("service.error", lang), e),
                    }
                }
                #[cfg(target_os = "linux")]
                {
                    let _ = std::process::Command::new("systemctl")
                        .args(["status", "nanolink-agent"])
                        .status();
                }
                #[cfg(target_os = "macos")]
                {
                    let _ = std::process::Command::new("launchctl")
                        .args(["list", "com.nanolink.agent"])
                        .status();
                }
                #[cfg(not(any(target_os = "windows", target_os = "linux", target_os = "macos")))]
                {
                    println!("{}", t("service.not_supported", lang));
                }
                wait_for_enter(lang);
            }
            5 => break,
            _ => {}
        }
    }

    Ok(())
}

/// Validate and escape path for systemd service file
/// Returns None if path contains invalid characters
#[cfg(target_os = "linux")]
fn validate_systemd_path(path: &std::path::Path) -> Option<String> {
    let path_str = path.to_string_lossy();
    // Reject paths with newlines, quotes, or control characters
    if path_str
        .chars()
        .any(|c| c == '\n' || c == '\r' || c == '"' || c.is_control())
    {
        return None;
    }
    // Shell-escape the path for systemd ExecStart
    Some(format!(
        "\"{}\"",
        path_str.replace('\\', "\\\\").replace('"', "\\\"")
    ))
}

/// Escape string for XML plist
#[cfg(target_os = "macos")]
fn escape_xml(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&apos;")
}

/// Check if running with root privileges
#[cfg(unix)]
fn is_root() -> bool {
    unsafe { libc::geteuid() == 0 }
}

#[cfg(target_os = "linux")]
fn install_systemd_service(args: &Args) -> Result<(), String> {
    use std::fs;

    // Check root permission
    if !is_root() {
        return Err("Root permission required. Run with sudo.".to_string());
    }

    let exe_path = std::env::current_exe().map_err(|e| e.to_string())?;
    let exe_escaped = validate_systemd_path(&exe_path)
        .ok_or_else(|| "Invalid characters in executable path".to_string())?;

    let config_arg = match get_config_path(args) {
        Some(p) => {
            let config_escaped = validate_systemd_path(&p)
                .ok_or_else(|| "Invalid characters in config path".to_string())?;
            format!(" -c {}", config_escaped)
        }
        None => String::new(),
    };

    let service_content = format!(
        r#"[Unit]
Description=NanoLink Agent
After=network.target

[Service]
Type=simple
ExecStart={}{} -f
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
"#,
        exe_escaped, config_arg
    );

    fs::write(
        "/etc/systemd/system/nanolink-agent.service",
        service_content,
    )
    .map_err(|e| format!("Failed to write service file: {}", e))?;

    std::process::Command::new("systemctl")
        .args(["daemon-reload"])
        .status()
        .map_err(|e| e.to_string())?;

    std::process::Command::new("systemctl")
        .args(["enable", "nanolink-agent"])
        .status()
        .map_err(|e| e.to_string())?;

    Ok(())
}

#[cfg(target_os = "linux")]
fn uninstall_systemd_service() -> Result<(), String> {
    use std::fs;

    let _ = std::process::Command::new("systemctl")
        .args(["stop", "nanolink-agent"])
        .status();

    let _ = std::process::Command::new("systemctl")
        .args(["disable", "nanolink-agent"])
        .status();

    fs::remove_file("/etc/systemd/system/nanolink-agent.service").map_err(|e| e.to_string())?;

    std::process::Command::new("systemctl")
        .args(["daemon-reload"])
        .status()
        .map_err(|e| e.to_string())?;

    Ok(())
}

#[cfg(target_os = "macos")]
fn install_launchd_service(args: &Args) -> Result<(), String> {
    use std::fs;

    // Check root permission
    if !is_root() {
        return Err("Root permission required. Run with sudo.".to_string());
    }

    let exe_path = std::env::current_exe().map_err(|e| e.to_string())?;
    let exe_escaped = escape_xml(&exe_path.to_string_lossy());

    let mut args_xml = String::from("        <string>-f</string>\n");
    if let Some(p) = get_config_path(args) {
        let config_escaped = escape_xml(&p.to_string_lossy());
        args_xml.push_str(&format!(
            "        <string>-c</string>\n        <string>{}</string>\n",
            config_escaped
        ));
    }

    let plist_content = format!(
        r#"<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.nanolink.agent</string>
    <key>ProgramArguments</key>
    <array>
        <string>{}</string>
{}    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
"#,
        exe_escaped, args_xml
    );

    fs::write(
        "/Library/LaunchDaemons/com.nanolink.agent.plist",
        plist_content,
    )
    .map_err(|e| format!("Failed to write plist file: {}", e))?;

    Ok(())
}

#[cfg(target_os = "macos")]
fn uninstall_launchd_service() -> Result<(), String> {
    use std::fs;

    let _ = std::process::Command::new("launchctl")
        .args(["unload", "/Library/LaunchDaemons/com.nanolink.agent.plist"])
        .status();

    fs::remove_file("/Library/LaunchDaemons/com.nanolink.agent.plist")
        .map_err(|e| e.to_string())?;

    Ok(())
}

/// Interactive system diagnostics
fn interactive_diagnostics(args: &Args, lang: Lang) -> Result<()> {
    use std::net::{TcpStream, ToSocketAddrs};
    use std::time::Duration;

    println!();
    println!("╭──────────────────────────────────────╮");
    println!("│       {}                  │", t("diag.title", lang));
    println!("╰──────────────────────────────────────╯");
    println!();

    // 1. Config validation
    print!("  ● {}... ", t("diag.config_valid", lang));
    std::io::Write::flush(&mut std::io::stdout())?;

    match get_config_path(args) {
        Some(config_path) => match Config::load(&config_path) {
            Ok(_) => println!("✓ {}", t("diag.ok", lang)),
            Err(e) => println!("✗ {}: {}", t("diag.error", lang), e),
        },
        None => println!("✗ {}", t("error.no_config", lang)),
    }

    // 2. DNS resolution
    print!("  ● {}... ", t("diag.dns", lang));
    std::io::Write::flush(&mut std::io::stdout())?;

    match std::net::ToSocketAddrs::to_socket_addrs(&("google.com", 80)) {
        Ok(_) => println!("✓ {}", t("diag.ok", lang)),
        Err(e) => println!("✗ {}: {}", t("diag.error", lang), e),
    }

    // 3. Network connectivity
    print!("  ● {}... ", t("diag.network", lang));
    std::io::Write::flush(&mut std::io::stdout())?;

    // Use a known-valid address to avoid unwrap
    let google_dns: std::net::SocketAddr = "8.8.8.8:53".parse().expect("valid IP literal");
    match TcpStream::connect_timeout(&google_dns, Duration::from_secs(5)) {
        Ok(_) => println!("✓ {}", t("diag.ok", lang)),
        Err(e) => println!("✗ {}: {}", t("diag.error", lang), e),
    }

    // 4. Disk space
    print!("  ● {}... ", t("diag.disk_space", lang));
    std::io::Write::flush(&mut std::io::stdout())?;

    let disks = sysinfo::Disks::new_with_refreshed_list();
    let mut low_space = false;
    for disk in disks.list() {
        let total = disk.total_space();
        let available = disk.available_space();
        if total > 0 && (available as f64 / total as f64) < 0.1 {
            low_space = true;
        }
    }
    if low_space {
        println!("! {} (<10% free)", t("diag.warning", lang));
    } else {
        println!("✓ {}", t("diag.ok", lang));
    }

    // 5. Server reachability
    if let Some(config_path) = get_config_path(args) {
        if let Ok(config) = Config::load(&config_path) {
            println!();
            println!("  {}:", t("diag.server_reach", lang));

            for server in &config.servers {
                print!("    ● {}:{}... ", server.host, server.port);
                std::io::Write::flush(&mut std::io::stdout())?;

                let addr = format!("{}:{}", server.host, server.port);
                match addr.to_socket_addrs() {
                    Ok(mut addrs) => {
                        if let Some(addr) = addrs.next() {
                            match TcpStream::connect_timeout(&addr, Duration::from_secs(5)) {
                                Ok(_) => println!("✓ {}", t("diag.ok", lang)),
                                Err(e) => println!("✗ {e}"),
                            }
                        } else {
                            println!("✗ DNS resolution failed");
                        }
                    }
                    Err(e) => println!("✗ {e}"),
                }
            }
        }
    }

    println!();
    println!("✓ {}", t("diag.complete", lang));

    Ok(())
}

/// Interactive view logs
fn interactive_view_logs(args: &Args, lang: Lang) -> Result<()> {
    use dialoguer::{Input, Select, theme::ColorfulTheme};

    let theme = ColorfulTheme::default();

    println!();
    println!("╭──────────────────────────────────────╮");
    println!("│       {}                    │", t("logs.title", lang));
    println!("╰──────────────────────────────────────╯");
    println!();

    let options = &[t("logs.system", lang), t("logs.audit", lang)];

    let selection = Select::with_theme(&theme)
        .with_prompt(t("menu.select_action", lang))
        .items(options)
        .default(0)
        .interact()?;

    let lines: usize = Input::with_theme(&theme)
        .with_prompt(t("logs.lines_count", lang))
        .default(50)
        .interact_text()?;

    match selection {
        0 => {
            // System logs
            #[cfg(target_os = "linux")]
            {
                let _ = std::process::Command::new("journalctl")
                    .args([
                        "-u",
                        "nanolink-agent",
                        "-n",
                        &lines.to_string(),
                        "--no-pager",
                    ])
                    .status();
            }
            #[cfg(target_os = "macos")]
            {
                // macOS 'log show --last' uses time duration, not line count
                // Use a reasonable time window based on requested lines
                let minutes = (lines / 10).max(5).min(60); // ~10 lines/min estimate
                println!("(Showing logs from last {} minutes)", minutes);
                let _ = std::process::Command::new("log")
                    .args([
                        "show",
                        "--predicate",
                        "process == \"nanolink-agent\"",
                        "--last",
                        &format!("{}m", minutes),
                    ])
                    .status();
            }
            #[cfg(target_os = "windows")]
            {
                println!("Check Event Viewer for NanoLink Agent logs");
            }
        }
        1 => {
            // Audit logs
            if let Some(config_path) = get_config_path(args) {
                if let Ok(config) = Config::load(&config_path) {
                    let audit_file = &config.logging.audit_file;
                    if std::path::Path::new(audit_file).exists() {
                        let content = std::fs::read_to_string(audit_file)?;
                        let all_lines: Vec<&str> = content.lines().collect();
                        let start = all_lines.len().saturating_sub(lines);
                        println!();
                        for line in &all_lines[start..] {
                            println!("{line}");
                        }
                    } else {
                        println!("{}", t("logs.no_logs", lang));
                    }
                }
            } else {
                println!("{}", t("error.no_config", lang));
            }
        }
        _ => {}
    }

    Ok(())
}

/// Interactive export configuration
fn interactive_export_config(args: &Args, lang: Lang) -> Result<()> {
    use dialoguer::{Input, Select, theme::ColorfulTheme};

    let theme = ColorfulTheme::default();

    println!();
    println!("╭──────────────────────────────────────╮");
    println!("│       {}                  │", t("export.title", lang));
    println!("╰──────────────────────────────────────╯");
    println!();

    let config_path = match get_config_path(args) {
        Some(p) => p,
        None => {
            println!("{}", t("error.no_config", lang));
            return Ok(());
        }
    };

    let mut config = Config::load(&config_path)?;

    // Warn about sensitive information
    let has_tokens =
        config.servers.iter().any(|s| !s.token.is_empty()) || config.management.api_token.is_some();

    if has_tokens {
        use dialoguer::Confirm;
        println!();
        println!("⚠️  Warning: Configuration contains sensitive tokens!");
        println!("   Exported file will include authentication tokens in plaintext.");
        println!();

        let redact = Confirm::with_theme(&theme)
            .with_prompt("Redact sensitive tokens? (Recommended)")
            .default(true)
            .interact()?;

        if redact {
            // Redact tokens
            for server in &mut config.servers {
                if !server.token.is_empty() {
                    server.token = "[REDACTED]".to_string();
                }
            }
            if config.management.api_token.is_some() {
                config.management.api_token = Some("[REDACTED]".to_string());
            }
            println!("   Tokens will be redacted in export.");
        } else {
            println!("   Tokens will be included in plaintext. Handle with care!");
        }
        println!();
    }

    let formats = &["YAML", "TOML", "JSON"];
    let format_sel = Select::with_theme(&theme)
        .with_prompt(t("export.format", lang))
        .items(formats)
        .default(0)
        .interact()?;

    let default_ext = match format_sel {
        0 => "yaml",
        1 => "toml",
        2 => "json",
        _ => "yaml",
    };

    let output_path: String = Input::with_theme(&theme)
        .with_prompt(t("export.path", lang))
        .default(format!("nanolink-export.{default_ext}"))
        .interact_text()?;

    // Validate output path - prevent path traversal
    let output_path = std::path::Path::new(&output_path);
    if output_path.to_string_lossy().contains("..") {
        println!("✗ Error: Path traversal not allowed");
        return Ok(());
    }

    // Prevent writing to system directories
    let path_str = output_path.to_string_lossy();
    if path_str.starts_with("/etc/")
        || path_str.starts_with("/usr/")
        || path_str.starts_with("/bin/")
        || path_str.starts_with("/sbin/")
        || path_str.starts_with("C:\\Windows")
        || path_str.starts_with("C:\\Program Files")
    {
        println!("✗ Error: Cannot write to system directory");
        return Ok(());
    }

    let content = match format_sel {
        0 => serde_yaml::to_string(&config)?,
        1 => toml::to_string_pretty(&config)?,
        2 => serde_json::to_string_pretty(&config)?,
        _ => serde_yaml::to_string(&config)?,
    };

    std::fs::write(output_path, content)?;
    println!();
    println!("✓ {}: {}", t("export.success", lang), output_path.display());

    Ok(())
}

/// Run the agent (public for Windows service support)
pub async fn run_agent(config_path: PathBuf) -> Result<()> {
    info!("NanoLink Agent v{} starting...", env!("CARGO_PKG_VERSION"));

    // Load configuration
    let config = Config::load(&config_path)?;
    info!("Configuration loaded from {:?}", config_path);

    // Create shared state with RwLock for runtime updates
    let management_enabled = config.management.enabled;
    let management_port = config.management.port;
    let buffer_capacity = config.buffer.capacity;

    let config = Arc::new(RwLock::new(config));
    let ring_buffer = Arc::new(RingBuffer::new(buffer_capacity));

    // Create shutdown channel
    let (shutdown_tx, _) = broadcast::channel::<()>(1);

    // Create connection manager first to get signal sender and status
    let connection_manager = {
        let config_guard = config.read().await;
        ConnectionManager::new(Arc::new((*config_guard).clone()), ring_buffer.clone())
    };
    let connection_signal_tx = connection_manager.get_signal_sender();
    let connection_status = connection_manager.get_status();

    // Start management API if enabled (with connection control)
    let management_handle = if management_enabled {
        let (management_server, _event_rx) = ManagementServer::new_with_connection_control(
            config.clone(),
            config_path.clone(),
            management_port,
            connection_signal_tx,
            connection_status,
            ring_buffer.clone(),
        );

        let mut shutdown_rx = shutdown_tx.subscribe();
        Some(tokio::spawn(async move {
            tokio::select! {
                _ = management_server.run() => {},
                _ = shutdown_rx.recv() => {
                    info!("Management API shutting down");
                }
            }
        }))
    } else {
        None
    };

    // Start metrics collector (needs read-only config access)
    let collector = {
        let config_guard = config.read().await;
        MetricsCollector::new(Arc::new((*config_guard).clone()), ring_buffer.clone())
    };

    let collector_handle = {
        let mut shutdown_rx = shutdown_tx.subscribe();
        tokio::spawn(async move {
            tokio::select! {
                _ = collector.run() => {},
                _ = shutdown_rx.recv() => {
                    info!("Metrics collector shutting down");
                }
            }
        })
    };

    // Start connection manager (already created above)
    let connection_handle = {
        let mut shutdown_rx = shutdown_tx.subscribe();
        tokio::spawn(async move {
            tokio::select! {
                _ = connection_manager.run() => {},
                _ = shutdown_rx.recv() => {
                    info!("Connection manager shutting down");
                }
            }
        })
    };

    info!("NanoLink Agent started successfully");
    if management_enabled {
        info!("  Management API: http://localhost:{}/api", management_port);
    }

    // Wait for shutdown signal
    tokio::select! {
        _ = tokio::signal::ctrl_c() => {
            info!("Received Ctrl+C, shutting down...");
        }
    }

    // Send shutdown signal
    let _ = shutdown_tx.send(());

    // Wait for tasks to complete
    let _ = tokio::join!(collector_handle, connection_handle);
    if let Some(handle) = management_handle {
        let _ = handle.await;
    }

    info!("NanoLink Agent stopped");
    Ok(())
}
