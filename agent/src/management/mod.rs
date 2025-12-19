//! Agent local management API
//!
//! Provides HTTP endpoints for managing the agent configuration at runtime.
//! Listens on localhost only for security.

use std::net::SocketAddr;
use std::path::PathBuf;
use std::sync::Arc;

use axum::{
    extract::{Query, State},
    http::StatusCode,
    routing::{delete, get, post},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use tokio::sync::{broadcast, RwLock};
use tracing::{error, info, warn};

use crate::config::{Config, ServerConfig};

/// Server change event
#[derive(Debug, Clone)]
pub enum ServerEvent {
    /// Add a new server
    Add(ServerConfig),
    /// Update an existing server (by URL)
    Update(ServerConfig),
    /// Remove a server by URL
    Remove(String),
}

/// Management API state
pub struct ManagementState {
    /// Current configuration
    config: Arc<RwLock<Config>>,
    /// Path to configuration file
    config_path: PathBuf,
    /// Channel to notify about server changes
    event_tx: broadcast::Sender<ServerEvent>,
}

/// Configuration for the management API
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ManagementConfig {
    /// Enable management API
    #[serde(default = "default_enabled")]
    pub enabled: bool,

    /// Port to listen on (localhost only)
    #[serde(default = "default_port")]
    pub port: u16,

    /// Require token for API access
    pub api_token: Option<String>,
}

fn default_enabled() -> bool {
    true
}

fn default_port() -> u16 {
    9101
}

impl Default for ManagementConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            port: 9101,
            api_token: None,
        }
    }
}

/// Management API server
pub struct ManagementServer {
    state: Arc<ManagementState>,
    port: u16,
}

impl ManagementServer {
    /// Create a new management server
    pub fn new(
        config: Arc<RwLock<Config>>,
        config_path: PathBuf,
        port: u16,
    ) -> (Self, broadcast::Receiver<ServerEvent>) {
        let (event_tx, event_rx) = broadcast::channel(16);

        let state = Arc::new(ManagementState {
            config,
            config_path,
            event_tx,
        });

        (Self { state, port }, event_rx)
    }

    /// Run the management server
    pub async fn run(self) {
        let app = Router::new()
            .route("/api/health", get(health))
            .route("/api/config", get(get_config))
            .route("/api/servers", get(list_servers))
            .route("/api/servers", post(add_server))
            .route("/api/servers", delete(remove_server))
            .route("/api/servers/update", post(update_server))
            .with_state(self.state);

        let addr = SocketAddr::from(([127, 0, 0, 1], self.port));
        info!("Management API listening on http://{}", addr);

        if let Err(e) = axum::serve(
            tokio::net::TcpListener::bind(addr).await.unwrap(),
            app.into_make_service(),
        )
        .await
        {
            error!("Management API error: {}", e);
        }
    }
}

// Request/Response types

#[derive(Debug, Serialize)]
struct HealthResponse {
    status: String,
    version: String,
}

#[derive(Debug, Serialize)]
struct ServerInfo {
    url: String,
    permission: u8,
    tls_verify: bool,
    connected: bool,
}

#[derive(Debug, Deserialize)]
struct AddServerRequest {
    url: String,
    token: String,
    #[serde(default)]
    permission: u8,
    #[serde(default = "default_true")]
    tls_verify: bool,
}

fn default_true() -> bool {
    true
}

#[derive(Debug, Deserialize)]
struct RemoveServerQuery {
    url: String,
}

#[derive(Debug, Serialize)]
struct ApiResponse {
    success: bool,
    message: String,
}

// Handlers

async fn health() -> Json<HealthResponse> {
    Json(HealthResponse {
        status: "healthy".to_string(),
        version: env!("CARGO_PKG_VERSION").to_string(),
    })
}

async fn get_config(State(state): State<Arc<ManagementState>>) -> Json<serde_json::Value> {
    let config = state.config.read().await;

    // Return config without tokens
    Json(serde_json::json!({
        "agent": config.agent,
        "collector": config.collector,
        "buffer": config.buffer,
        "shell": {
            "enabled": config.shell.enabled,
            "timeout_seconds": config.shell.timeout_seconds,
        },
        "logging": config.logging,
        "server_count": config.servers.len(),
    }))
}

async fn list_servers(State(state): State<Arc<ManagementState>>) -> Json<Vec<ServerInfo>> {
    let config = state.config.read().await;

    let servers: Vec<ServerInfo> = config
        .servers
        .iter()
        .map(|s| ServerInfo {
            url: s.url.clone(),
            permission: s.permission,
            tls_verify: s.tls_verify,
            connected: false, // TODO: Track actual connection state
        })
        .collect();

    Json(servers)
}

async fn add_server(
    State(state): State<Arc<ManagementState>>,
    Json(req): Json<AddServerRequest>,
) -> (StatusCode, Json<ApiResponse>) {
    // Validate URL
    if !req.url.starts_with("ws://") && !req.url.starts_with("wss://") {
        return (
            StatusCode::BAD_REQUEST,
            Json(ApiResponse {
                success: false,
                message: "URL must start with ws:// or wss://".to_string(),
            }),
        );
    }

    // Validate permission
    if req.permission > 3 {
        return (
            StatusCode::BAD_REQUEST,
            Json(ApiResponse {
                success: false,
                message: "Permission must be 0-3".to_string(),
            }),
        );
    }

    let server_config = ServerConfig {
        url: req.url.clone(),
        token: req.token,
        permission: req.permission,
        tls_verify: req.tls_verify,
    };

    // Check if server already exists
    {
        let config = state.config.read().await;
        if config.servers.iter().any(|s| s.url == req.url) {
            return (
                StatusCode::CONFLICT,
                Json(ApiResponse {
                    success: false,
                    message: "Server already exists. Use update endpoint to modify.".to_string(),
                }),
            );
        }
    }

    // Add server to config
    {
        let mut config = state.config.write().await;
        config.servers.push(server_config.clone());

        // Save to file
        if let Err(e) = save_config(&config, &state.config_path) {
            error!("Failed to save config: {}", e);
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse {
                    success: false,
                    message: format!("Failed to save config: {}", e),
                }),
            );
        }
    }

    // Notify about the new server
    let _ = state.event_tx.send(ServerEvent::Add(server_config));

    info!("Added server: {}", req.url);

    (
        StatusCode::OK,
        Json(ApiResponse {
            success: true,
            message: format!("Server {} added successfully", req.url),
        }),
    )
}

async fn update_server(
    State(state): State<Arc<ManagementState>>,
    Json(req): Json<AddServerRequest>,
) -> (StatusCode, Json<ApiResponse>) {
    let server_config = ServerConfig {
        url: req.url.clone(),
        token: req.token,
        permission: req.permission,
        tls_verify: req.tls_verify,
    };

    // Update server in config
    {
        let mut config = state.config.write().await;
        let found = config.servers.iter_mut().find(|s| s.url == req.url);

        match found {
            Some(server) => {
                *server = server_config.clone();
            }
            None => {
                return (
                    StatusCode::NOT_FOUND,
                    Json(ApiResponse {
                        success: false,
                        message: "Server not found".to_string(),
                    }),
                );
            }
        }

        // Save to file
        if let Err(e) = save_config(&config, &state.config_path) {
            error!("Failed to save config: {}", e);
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse {
                    success: false,
                    message: format!("Failed to save config: {}", e),
                }),
            );
        }
    }

    // Notify about the update
    let _ = state.event_tx.send(ServerEvent::Update(server_config));

    info!("Updated server: {}", req.url);

    (
        StatusCode::OK,
        Json(ApiResponse {
            success: true,
            message: format!("Server {} updated successfully", req.url),
        }),
    )
}

async fn remove_server(
    State(state): State<Arc<ManagementState>>,
    Query(query): Query<RemoveServerQuery>,
) -> (StatusCode, Json<ApiResponse>) {
    // Remove server from config
    {
        let mut config = state.config.write().await;
        let original_len = config.servers.len();
        config.servers.retain(|s| s.url != query.url);

        if config.servers.len() == original_len {
            return (
                StatusCode::NOT_FOUND,
                Json(ApiResponse {
                    success: false,
                    message: "Server not found".to_string(),
                }),
            );
        }

        // Don't allow removing all servers
        if config.servers.is_empty() {
            // Restore the removed server
            return (
                StatusCode::BAD_REQUEST,
                Json(ApiResponse {
                    success: false,
                    message: "Cannot remove the last server".to_string(),
                }),
            );
        }

        // Save to file
        if let Err(e) = save_config(&config, &state.config_path) {
            error!("Failed to save config: {}", e);
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse {
                    success: false,
                    message: format!("Failed to save config: {}", e),
                }),
            );
        }
    }

    // Notify about the removal
    let _ = state.event_tx.send(ServerEvent::Remove(query.url.clone()));

    info!("Removed server: {}", query.url);

    (
        StatusCode::OK,
        Json(ApiResponse {
            success: true,
            message: format!("Server {} removed successfully", query.url),
        }),
    )
}

/// Save configuration to file
fn save_config(config: &Config, path: &PathBuf) -> anyhow::Result<()> {
    let content = if path.extension().map_or(false, |e| e == "toml") {
        toml::to_string_pretty(config)?
    } else {
        serde_yaml::to_string(config)?
    };

    std::fs::write(path, content)?;
    Ok(())
}
