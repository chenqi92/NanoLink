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
mod utils;

#[allow(clippy::large_enum_variant)]
pub mod proto {
    include!(concat!(env!("OUT_DIR"), "/nanolink.rs"));
}

use anyhow::Result;
use clap::{Parser, Subcommand};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use tokio::sync::{broadcast, RwLock};
use tracing::{info, Level};
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
#[command(version = "0.3.4")]
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
    if let Some(ref path) = args.config {
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

#[tokio::main]
async fn main() -> Result<()> {
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

    // Handle subcommands
    if let Some(ref command) = args.command {
        return handle_command(command, &args).await;
    }

    // If no subcommand and not foreground mode, enter interactive mode
    if !args.foreground {
        return interactive_main_menu(&args);
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

    run_agent(config_path).await
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

    let (final_host, final_port) = if let Some(ref h) = host {
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

    let (final_host, final_port) = if let Some(ref h) = host {
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

    let (final_host, final_port) = if let Some(ref h) = host {
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

use crate::i18n::{detect_language, t, Lang};

/// Interactive main menu - entry point for interactive mode
fn interactive_main_menu(args: &Args) -> Result<()> {
    use dialoguer::{theme::ColorfulTheme, Select};

    let lang = detect_language();
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
            t("menu.init_config", lang),
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
                    // Create a new tokio runtime for running the agent
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
            3 => {
                // Initialize Config
                interactive_init_config(lang)?;
                wait_for_enter(lang);
            }
            4 => {
                // Exit
                break;
            }
            _ => unreachable!(),
        }
    }

    Ok(())
}

/// Interactive server management menu
fn interactive_server_management(args: &Args, lang: Lang) -> Result<()> {
    use dialoguer::{theme::ColorfulTheme, Select};

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

        if let Some(ref cfg) = config {
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
            if let (Some(ref path), Some(ref cfg)) = (&config_path, &config) {
                let server = &cfg.servers[server_indices[selection]];
                interactive_server_action(path, server.host.clone(), server.port, lang)?;
            }
        } else if selection == servers_count + 1 {
            // Add new server
            if let Some(ref path) = config_path {
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
    use dialoguer::{theme::ColorfulTheme, Confirm, Select};

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
    use dialoguer::{theme::ColorfulTheme, Confirm, Input, Password, Select};

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
        permission,
        tls_enabled,
        tls_verify,
    });

    save_config(&config, config_path)?;
    println!();
    println!("{}", t("status.server_added", lang));

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
    use dialoguer::{theme::ColorfulTheme, Confirm, Input};

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

/// Wait for user to press Enter
fn wait_for_enter(lang: Lang) {
    use std::io::{self, Write};

    println!();
    print!("{}", t("misc.press_enter", lang));
    io::stdout().flush().unwrap();
    let mut input = String::new();
    let _ = io::stdin().read_line(&mut input);
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

    // Start management API if enabled
    let management_handle = if management_enabled {
        let (management_server, _event_rx) =
            ManagementServer::new(config.clone(), config_path.clone(), management_port);

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

    // Start connection manager
    let connection_manager = {
        let config_guard = config.read().await;
        ConnectionManager::new(Arc::new((*config_guard).clone()), ring_buffer.clone())
    };

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
