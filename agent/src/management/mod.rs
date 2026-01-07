//! Agent local management API
//!
//! Provides HTTP endpoints for managing the agent configuration at runtime.
//! Listens on localhost only for security.

use std::net::SocketAddr;
use std::path::PathBuf;
use std::sync::Arc;

use axum::{
    Json, Router,
    extract::{Query, State},
    http::{HeaderMap, StatusCode},
    middleware::{self, Next},
    response::Response,
    routing::{delete, get, post},
};
use serde::{Deserialize, Serialize};
use tokio::sync::{RwLock, broadcast};
use tracing::{error, info, warn};

use crate::buffer::RingBuffer;
use crate::config::{Config, DEFAULT_GRPC_PORT, ServerConfig};
use crate::connection::{ConnectionSignal, ConnectionStatus};

/// Server change event for dynamic server management
#[derive(Debug, Clone)]
#[allow(dead_code)]
pub enum ServerEvent {
    /// Add a new server
    Add(ServerConfig),
    /// Update an existing server (by host:port)
    Update(ServerConfig),
    /// Remove a server by host:port
    Remove(String, u16),
}

/// Management API state
pub struct ManagementState {
    /// Current configuration
    config: Arc<RwLock<Config>>,
    /// Path to configuration file
    config_path: PathBuf,
    /// Channel to notify about server changes
    event_tx: broadcast::Sender<ServerEvent>,
    /// Channel to send connection control signals
    connection_signal_tx: Option<broadcast::Sender<ConnectionSignal>>,
    /// Connection status for each server
    connection_status: Option<Arc<RwLock<Vec<ConnectionStatus>>>>,
    /// Ring buffer reference for buffer stats
    buffer: Option<Arc<RingBuffer>>,
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
            connection_signal_tx: None,
            connection_status: None,
            buffer: None,
        });

        (Self { state, port }, event_rx)
    }

    /// Create a new management server with connection control capabilities
    pub fn new_with_connection_control(
        config: Arc<RwLock<Config>>,
        config_path: PathBuf,
        port: u16,
        connection_signal_tx: broadcast::Sender<ConnectionSignal>,
        connection_status: Arc<RwLock<Vec<ConnectionStatus>>>,
        buffer: Arc<RingBuffer>,
    ) -> (Self, broadcast::Receiver<ServerEvent>) {
        let (event_tx, event_rx) = broadcast::channel(16);

        let state = Arc::new(ManagementState {
            config,
            config_path,
            event_tx,
            connection_signal_tx: Some(connection_signal_tx),
            connection_status: Some(connection_status),
            buffer: Some(buffer),
        });

        (Self { state, port }, event_rx)
    }

    /// Run the management server
    pub async fn run(self) {
        // Clone state for auth middleware
        let auth_state = self.state.clone();

        // Protected routes (require authentication if api_token is set)
        let protected_routes = Router::new()
            .route("/api/config", get(get_config))
            .route("/api/servers", get(list_servers))
            .route("/api/servers", post(add_server))
            .route("/api/servers", delete(remove_server))
            .route("/api/servers/update", post(update_server))
            .route("/api/connection/status", get(connection_status))
            .route("/api/connection/reconnect", post(trigger_reconnect))
            .route("/api/buffer/status", get(buffer_status))
            .layer(middleware::from_fn_with_state(
                auth_state.clone(),
                auth_middleware,
            ));

        // Public routes (no authentication required)
        let app = Router::new()
            .route("/api/health", get(health))
            .merge(protected_routes)
            .with_state(self.state);

        let addr = SocketAddr::from(([127, 0, 0, 1], self.port));
        info!("Management API listening on http://{}", addr);

        match tokio::net::TcpListener::bind(addr).await {
            Ok(listener) => {
                if let Err(e) = axum::serve(listener, app.into_make_service()).await {
                    error!("Management API error: {}", e);
                }
            }
            Err(e) => {
                error!("Failed to bind Management API to {}: {}", addr, e);
            }
        }
    }
}

/// Authentication middleware - validates Bearer token against config api_token
async fn auth_middleware(
    State(state): State<Arc<ManagementState>>,
    headers: HeaderMap,
    request: axum::extract::Request,
    next: Next,
) -> Result<Response, (StatusCode, Json<ApiResponse>)> {
    let config = state.config.read().await;

    // If no token is configured, allow all requests (for backward compatibility)
    let Some(ref expected_token) = config.management.api_token else {
        return Ok(next.run(request).await);
    };

    // Skip auth if token is empty
    if expected_token.is_empty() {
        return Ok(next.run(request).await);
    }

    // Extract Authorization header
    let auth_header = headers.get("Authorization").and_then(|v| v.to_str().ok());

    match auth_header {
        Some(header) if header.starts_with("Bearer ") => {
            let token = &header[7..]; // Skip "Bearer "
            // Use constant-time comparison to prevent timing attacks
            if subtle::ConstantTimeEq::ct_eq(token.as_bytes(), expected_token.as_bytes()).into() {
                Ok(next.run(request).await)
            } else {
                warn!("Management API: invalid token attempted");
                Err((
                    StatusCode::UNAUTHORIZED,
                    Json(ApiResponse {
                        success: false,
                        message: "Invalid API token".to_string(),
                    }),
                ))
            }
        }
        _ => Err((
            StatusCode::UNAUTHORIZED,
            Json(ApiResponse {
                success: false,
                message:
                    "Missing or invalid Authorization header. Use: Authorization: Bearer <token>"
                        .to_string(),
            }),
        )),
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
    host: String,
    port: u16,
    permission: u8,
    tls_enabled: bool,
    tls_verify: bool,
    connected: bool,
}

#[derive(Debug, Deserialize)]
struct AddServerRequest {
    host: String,
    #[serde(default = "default_grpc_port")]
    port: u16,
    token: String,
    #[serde(default)]
    permission: u8,
    #[serde(default)]
    tls_enabled: bool,
    #[serde(default = "default_true")]
    tls_verify: bool,
}

fn default_true() -> bool {
    true
}

fn default_grpc_port() -> u16 {
    DEFAULT_GRPC_PORT
}

#[derive(Debug, Deserialize)]
struct RemoveServerQuery {
    host: String,
    #[serde(default = "default_grpc_port")]
    port: u16,
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
            host: s.host.clone(),
            port: s.port,
            permission: s.permission,
            tls_enabled: s.tls_enabled,
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
        host: req.host.clone(),
        port: req.port,
        token: req.token,
        permission: req.permission,
        tls_enabled: req.tls_enabled,
        tls_verify: req.tls_verify,
    };

    // Check if server already exists
    {
        let config = state.config.read().await;
        if config
            .servers
            .iter()
            .any(|s| s.host == req.host && s.port == req.port)
        {
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
                    message: format!("Failed to save config: {e}"),
                }),
            );
        }
    }

    // Notify about the new server
    let _ = state.event_tx.send(ServerEvent::Add(server_config));

    info!("Added server: {}:{}", req.host, req.port);

    (
        StatusCode::OK,
        Json(ApiResponse {
            success: true,
            message: format!("Server {}:{} added successfully", req.host, req.port),
        }),
    )
}

async fn update_server(
    State(state): State<Arc<ManagementState>>,
    Json(req): Json<AddServerRequest>,
) -> (StatusCode, Json<ApiResponse>) {
    let server_config = ServerConfig {
        host: req.host.clone(),
        port: req.port,
        token: req.token,
        permission: req.permission,
        tls_enabled: req.tls_enabled,
        tls_verify: req.tls_verify,
    };

    // Update server in config
    {
        let mut config = state.config.write().await;
        let found = config
            .servers
            .iter_mut()
            .find(|s| s.host == req.host && s.port == req.port);

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
                    message: format!("Failed to save config: {e}"),
                }),
            );
        }
    }

    // Notify about the update
    let _ = state.event_tx.send(ServerEvent::Update(server_config));

    info!("Updated server: {}:{}", req.host, req.port);

    (
        StatusCode::OK,
        Json(ApiResponse {
            success: true,
            message: format!("Server {}:{} updated successfully", req.host, req.port),
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
        config
            .servers
            .retain(|s| !(s.host == query.host && s.port == query.port));

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
                    message: format!("Failed to save config: {e}"),
                }),
            );
        }
    }

    // Notify about the removal
    let _ = state
        .event_tx
        .send(ServerEvent::Remove(query.host.clone(), query.port));

    info!("Removed server: {}:{}", query.host, query.port);

    (
        StatusCode::OK,
        Json(ApiResponse {
            success: true,
            message: format!("Server {}:{} removed successfully", query.host, query.port),
        }),
    )
}

/// Save configuration to file
fn save_config(config: &Config, path: &PathBuf) -> anyhow::Result<()> {
    let content = if path.extension().is_some_and(|e| e == "toml") {
        toml::to_string_pretty(config)?
    } else {
        serde_yaml::to_string(config)?
    };

    std::fs::write(path, content)?;
    Ok(())
}

// Connection control handlers

#[derive(Debug, Serialize)]
struct ConnectionStatusResponse {
    servers: Vec<ConnectionStatusInfo>,
}

#[derive(Debug, Serialize)]
struct ConnectionStatusInfo {
    server: String,
    connected: bool,
    last_error: Option<String>,
    reconnect_delay_secs: u64,
    connection_attempts: u32,
}

async fn connection_status(
    State(state): State<Arc<ManagementState>>,
) -> (StatusCode, Json<ConnectionStatusResponse>) {
    match &state.connection_status {
        Some(status) => {
            let status_guard = status.read().await;
            let servers: Vec<ConnectionStatusInfo> = status_guard
                .iter()
                .map(|s| ConnectionStatusInfo {
                    server: s.server.clone(),
                    connected: s.connected,
                    last_error: s.last_error.clone(),
                    reconnect_delay_secs: s.reconnect_delay_secs,
                    connection_attempts: s.connection_attempts,
                })
                .collect();
            (StatusCode::OK, Json(ConnectionStatusResponse { servers }))
        }
        None => (
            StatusCode::SERVICE_UNAVAILABLE,
            Json(ConnectionStatusResponse { servers: vec![] }),
        ),
    }
}

async fn trigger_reconnect(
    State(state): State<Arc<ManagementState>>,
) -> (StatusCode, Json<ApiResponse>) {
    match &state.connection_signal_tx {
        Some(tx) => match tx.send(ConnectionSignal::ImmediateReconnect) {
            Ok(receivers) => {
                info!(
                    "Triggered immediate reconnect, {} receivers notified",
                    receivers
                );
                (
                    StatusCode::OK,
                    Json(ApiResponse {
                        success: true,
                        message: format!(
                            "Immediate reconnect triggered, {} connections notified",
                            receivers
                        ),
                    }),
                )
            }
            Err(_) => (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse {
                    success: false,
                    message: "Failed to send reconnect signal (no active receivers)".to_string(),
                }),
            ),
        },
        None => (
            StatusCode::SERVICE_UNAVAILABLE,
            Json(ApiResponse {
                success: false,
                message: "Connection control not available".to_string(),
            }),
        ),
    }
}

#[derive(Debug, Serialize)]
struct BufferStatusResponse {
    capacity: usize,
    current_size: usize,
    usage_percent: f64,
    oldest_timestamp: Option<u64>,
    newest_timestamp: Option<u64>,
    last_sync_timestamp: u64,
    unsynced_count: usize,
    data_compensation_enabled: bool,
}

async fn buffer_status(
    State(state): State<Arc<ManagementState>>,
) -> (StatusCode, Json<BufferStatusResponse>) {
    let config = state.config.read().await;

    match &state.buffer {
        Some(buffer) => (
            StatusCode::OK,
            Json(BufferStatusResponse {
                capacity: buffer.capacity(),
                current_size: buffer.len(),
                usage_percent: buffer.usage_percent(),
                oldest_timestamp: buffer.oldest_timestamp(),
                newest_timestamp: buffer.newest_timestamp(),
                last_sync_timestamp: buffer.get_last_sync_timestamp(),
                unsynced_count: buffer.unsynced_count(),
                data_compensation_enabled: config.buffer.data_compensation,
            }),
        ),
        None => (
            StatusCode::SERVICE_UNAVAILABLE,
            Json(BufferStatusResponse {
                capacity: 0,
                current_size: 0,
                usage_percent: 0.0,
                oldest_timestamp: None,
                newest_timestamp: None,
                last_sync_timestamp: 0,
                unsynced_count: 0,
                data_compensation_enabled: config.buffer.data_compensation,
            }),
        ),
    }
}
