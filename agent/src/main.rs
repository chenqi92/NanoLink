mod buffer;
mod collector;
mod config;
mod connection;
mod executor;
mod management;
mod platform;
mod security;

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
#[command(version = "0.3.3")]
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
    /// Add a new server
    Add {
        /// Server hostname or IP address
        #[arg(long)]
        host: String,
        /// gRPC port (default: 39100)
        #[arg(long, default_value = "39100")]
        port: u16,
        /// Authentication token
        #[arg(long)]
        token: String,
        /// Permission level (0-3)
        #[arg(long, default_value = "0")]
        permission: u8,
        /// Enable TLS
        #[arg(long, default_value = "false")]
        tls_enabled: bool,
        /// Enable TLS certificate verification
        #[arg(long, default_value = "true")]
        tls_verify: bool,
    },
    /// Remove a server
    Remove {
        /// Server hostname to remove
        #[arg(long)]
        host: String,
        /// Server port to remove
        #[arg(long, default_value = "39100")]
        port: u16,
    },
    /// List all configured servers
    List,
    /// Update a server configuration
    Update {
        /// Server hostname
        #[arg(long)]
        host: String,
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
        eprintln!("  - {}", path);
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
            print_no_config_help();
            std::process::exit(1);
        }
    };

    run_agent(config_path).await
}

async fn handle_command(command: &Commands, args: &Args) -> Result<()> {
    use crate::config::ServerConfig;

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
                            println!("  Error loading config: {}", e);
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
                    if config
                        .servers
                        .iter()
                        .any(|s| s.host == *host && s.port == *port)
                    {
                        anyhow::bail!(
                            "Server {host}:{port} already exists. Use 'server update' to modify."
                        );
                    }

                    config.servers.push(ServerConfig {
                        host: host.clone(),
                        port: *port,
                        token: token.clone(),
                        permission: *permission,
                        tls_enabled: *tls_enabled,
                        tls_verify: *tls_verify,
                    });

                    save_config(&config, &config_path)?;
                    println!("Server {host}:{port} added successfully.");
                    println!(
                        "Restart the agent to apply changes, or use the management API for hot-reload."
                    );
                }
                ServerAction::Remove { host, port } => {
                    let original_len = config.servers.len();
                    config
                        .servers
                        .retain(|s| !(s.host == *host && s.port == *port));

                    if config.servers.len() == original_len {
                        anyhow::bail!("Server {host}:{port} not found.");
                    }

                    if config.servers.is_empty() {
                        anyhow::bail!("Cannot remove the last server.");
                    }

                    save_config(&config, &config_path)?;
                    println!("Server {host}:{port} removed successfully.");
                    println!("Restart the agent to apply changes.");
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
                    let server = config
                        .servers
                        .iter_mut()
                        .find(|s| s.host == *host && s.port == *port);

                    match server {
                        Some(s) => {
                            if let Some(t) = token {
                                s.token = t.clone();
                            }
                            if let Some(p) = permission {
                                s.permission = *p;
                            }
                            if let Some(te) = tls_enabled {
                                s.tls_enabled = *te;
                            }
                            if let Some(tv) = tls_verify {
                                s.tls_verify = *tv;
                            }

                            save_config(&config, &config_path)?;
                            println!("Server {host}:{port} updated successfully.");
                            println!("Restart the agent to apply changes.");
                        }
                        None => {
                            anyhow::bail!("Server {host}:{port} not found.");
                        }
                    }
                }
            }
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
