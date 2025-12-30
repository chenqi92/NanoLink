mod buffer;
mod collector;
mod config;
mod connection;
mod executor;
#[cfg(feature = "gui")]
mod gui;
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
use std::path::PathBuf;
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
fn handle_server_add(
    config: &mut Config,
    config_path: &PathBuf,
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
        parse_host_port(&h, default_port)
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
            "Server {}:{} already exists. Use 'server update' to modify.",
            final_host,
            final_port
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
    println!("Server {}:{} added successfully.", final_host, final_port);
    println!("Restart the agent to apply changes, or use the management API for hot-reload.");
    Ok(())
}

/// Handle server remove command with interactive support
fn handle_server_remove(
    config: &mut Config,
    config_path: &PathBuf,
    host: Option<String>,
    default_port: u16,
) -> Result<()> {
    use dialoguer::{Confirm, Select};

    let is_interactive = host.is_none();

    let (final_host, final_port) = if let Some(ref h) = host {
        parse_host_port(&h, default_port)
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
            .with_prompt(format!("Confirm removal of {}:{}?", final_host, final_port))
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
        anyhow::bail!("Server {}:{} not found.", final_host, final_port);
    }

    if config.servers.is_empty() {
        anyhow::bail!("Cannot remove the last server.");
    }

    save_config(config, config_path)?;
    println!("Server {}:{} removed successfully.", final_host, final_port);
    println!("Restart the agent to apply changes.");
    Ok(())
}

/// Handle server update command with interactive support
fn handle_server_update(
    config: &mut Config,
    config_path: &PathBuf,
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
        parse_host_port(&h, default_port)
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
            println!("Server {}:{} updated successfully.", final_host, final_port);
            println!("Restart the agent to apply changes.");
        }
        None => {
            anyhow::bail!("Server {}:{} not found.", final_host, final_port);
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

fn save_config(config: &Config, path: &PathBuf) -> Result<()> {
    let content = if path.extension().is_some_and(|e| e == "toml") {
        toml::to_string_pretty(config)?
    } else {
        serde_yaml::to_string(config)?
    };

    std::fs::write(path, content)?;
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
