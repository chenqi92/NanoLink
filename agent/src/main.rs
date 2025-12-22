mod buffer;
mod collector;
mod config;
mod connection;
mod executor;
mod management;
mod platform;
mod security;

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

#[derive(Parser, Debug)]
#[command(name = "nanolink-agent")]
#[command(author = "NanoLink Team")]
#[command(version = "0.2.7")]
#[command(about = "Lightweight server monitoring agent", long_about = None)]
struct Args {
    /// Path to configuration file
    #[arg(short, long, default_value = "nanolink.yaml", global = true)]
    config: PathBuf,

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
        println!("{}", yaml);
        return Ok(());
    }

    // Handle subcommands
    if let Some(command) = args.command {
        return handle_command(command, &args.config).await;
    }

    // Run the agent
    run_agent(args.config).await
}

async fn handle_command(command: Commands, config_path: &PathBuf) -> Result<()> {
    use crate::config::ServerConfig;

    match command {
        Commands::Server { action } => {
            let mut config = Config::load(config_path)?;

            match action {
                ServerAction::Add {
                    host,
                    port,
                    token,
                    permission,
                    tls_enabled,
                    tls_verify,
                } => {
                    // Check if server already exists
                    if config
                        .servers
                        .iter()
                        .any(|s| s.host == host && s.port == port)
                    {
                        anyhow::bail!(
                            "Server {}:{} already exists. Use 'server update' to modify.",
                            host,
                            port
                        );
                    }

                    config.servers.push(ServerConfig {
                        host: host.clone(),
                        port,
                        token,
                        permission,
                        tls_enabled,
                        tls_verify,
                    });

                    save_config(&config, config_path)?;
                    println!("Server {}:{} added successfully.", host, port);
                    println!("Restart the agent to apply changes, or use the management API for hot-reload.");
                }
                ServerAction::Remove { host, port } => {
                    let original_len = config.servers.len();
                    config
                        .servers
                        .retain(|s| !(s.host == host && s.port == port));

                    if config.servers.len() == original_len {
                        anyhow::bail!("Server {}:{} not found.", host, port);
                    }

                    if config.servers.is_empty() {
                        anyhow::bail!("Cannot remove the last server.");
                    }

                    save_config(&config, config_path)?;
                    println!("Server {}:{} removed successfully.", host, port);
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
                        .find(|s| s.host == host && s.port == port);

                    match server {
                        Some(s) => {
                            if let Some(t) = token {
                                s.token = t;
                            }
                            if let Some(p) = permission {
                                s.permission = p;
                            }
                            if let Some(te) = tls_enabled {
                                s.tls_enabled = te;
                            }
                            if let Some(tv) = tls_verify {
                                s.tls_verify = tv;
                            }

                            save_config(&config, config_path)?;
                            println!("Server {}:{} updated successfully.", host, port);
                            println!("Restart the agent to apply changes.");
                        }
                        None => {
                            anyhow::bail!("Server {}:{} not found.", host, port);
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

async fn run_agent(config_path: PathBuf) -> Result<()> {
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
