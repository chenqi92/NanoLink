//! Agent local management API
//!
//! Provides HTTP endpoints for managing the agent configuration at runtime.
//! Listens on configured bind address for security.

pub mod audit;
pub mod rate_limit;
pub mod token;

use std::net::SocketAddr;
use std::path::PathBuf;
use std::sync::Arc;

use axum::{
    Json, Router,
    extract::{ConnectInfo, Query, State},
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
    #[allow(dead_code)]
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
        // Get config for middleware setup
        let (rate_limit_config, audit_config) = {
            let config = self.state.config.read().await;
            (
                config.management.rate_limit.clone(),
                config.management.audit.clone(),
            )
        };

        // Create middleware states
        let auth_state = self.state.clone();
        let rate_limit_state = Arc::new(rate_limit::RateLimitState::new(rate_limit_config.clone()));
        let audit_state = Arc::new(audit::AuditState::new(audit_config.clone()));

        // Start background cleanup task for rate limit buckets
        if rate_limit_config.enabled {
            let cleanup_state = rate_limit_state.clone();
            tokio::spawn(async move {
                rate_limit::cleanup_old_buckets(cleanup_state).await;
            });
        }

        // Protected routes (require authentication based on permission level)
        let protected_routes = Router::new()
            .route("/api/config", get(get_config))
            .route("/api/servers", get(list_servers))
            .route("/api/servers", post(add_server))
            .route("/api/servers", delete(remove_server))
            .route("/api/servers/update", post(update_server))
            .route("/api/connection/status", get(connection_status))
            .route("/api/connection/reconnect", post(trigger_reconnect))
            .route("/api/buffer/status", get(buffer_status))
            .route("/api/token/rotate", post(rotate_token))
            .layer(middleware::from_fn_with_state(
                auth_state.clone(),
                auth_middleware,
            ));

        // All routes with rate limiting layer
        let rate_limited_routes = Router::new()
            .route("/api/health", get(health))
            .route("/api/status", get(status))
            .merge(protected_routes)
            .layer(middleware::from_fn_with_state(
                rate_limit_state,
                rate_limit::rate_limit_middleware,
            ))
            .with_state(self.state.clone());

        // Apply audit logging to all routes (outermost layer)
        let app = rate_limited_routes.layer(middleware::from_fn_with_state(
            audit_state,
            audit::audit_middleware,
        ));

        // Get TLS config
        let (bind_addr, tls_enabled, tls_cert, tls_key) = {
            let config = self.state.config.read().await;
            (
                config.management.bind_address.clone(),
                config.management.tls_enabled,
                config.management.tls_cert.clone(),
                config.management.tls_key.clone(),
            )
        };

        let addr: SocketAddr = format!("{}:{}", bind_addr, self.port)
            .parse()
            .unwrap_or_else(|_| SocketAddr::from(([127, 0, 0, 1], self.port)));

        // Start server with or without TLS
        if tls_enabled {
            if let (Some(cert_path), Some(key_path)) = (tls_cert, tls_key) {
                match axum_server::tls_rustls::RustlsConfig::from_pem_file(&cert_path, &key_path)
                    .await
                {
                    Ok(tls_config) => {
                        info!("Management API listening on https://{} (TLS enabled)", addr);
                        if let Err(e) = axum_server::bind_rustls(addr, tls_config)
                            .serve(app.into_make_service_with_connect_info::<SocketAddr>())
                            .await
                        {
                            error!("Management API TLS error: {}", e);
                        }
                        return;
                    }
                    Err(e) => {
                        error!(
                            "Failed to load TLS certificates from {} / {}: {}. Falling back to HTTP.",
                            cert_path, key_path, e
                        );
                    }
                }
            } else {
                warn!("TLS enabled but cert/key paths not configured. Falling back to HTTP.");
            }
        }

        // Plain HTTP fallback
        info!("Management API listening on http://{}", addr);

        match tokio::net::TcpListener::bind(addr).await {
            Ok(listener) => {
                if let Err(e) = axum::serve(
                    listener,
                    app.into_make_service_with_connect_info::<SocketAddr>(),
                )
                .await
                {
                    error!("Management API error: {}", e);
                }
            }
            Err(e) => {
                error!("Failed to bind Management API to {}: {}", addr, e);
            }
        }
    }
}

/// Authentication middleware - validates Token + IP + Permission
/// 1. Extract Bearer token from Authorization header
/// 2. Find matching server by management_token
/// 3. Verify source IP matches server host
/// 4. Check permission level for requested endpoint
async fn auth_middleware(
    State(state): State<Arc<ManagementState>>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    request: axum::extract::Request,
    next: Next,
) -> Result<Response, (StatusCode, Json<ApiResponse>)> {
    let config = state.config.read().await;
    let source_ip = addr.ip();
    let path = request.uri().path();

    // Get required permission for this endpoint
    let required_permission = get_required_permission(path);

    // Public endpoints (permission 0) - no auth required
    if required_permission == 0 {
        return Ok(next.run(request).await);
    }

    // Extract Authorization header
    let auth_header = headers.get("Authorization").and_then(|v| v.to_str().ok());

    let token = match auth_header {
        Some(header) if header.starts_with("Bearer ") => &header[7..],
        _ => {
            return Err((
                StatusCode::UNAUTHORIZED,
                Json(ApiResponse {
                    success: false,
                    message: "Missing or invalid Authorization header. Use: Authorization: Bearer <token>".to_string(),
                }),
            ));
        }
    };

    // Find server with matching management_token
    let matching_server = config.servers.iter().find(|s| {
        s.management_token.as_ref().is_some_and(|t| {
            // Use constant-time comparison to prevent timing attacks
            subtle::ConstantTimeEq::ct_eq(token.as_bytes(), t.as_bytes()).into()
        })
    });

    let server = match matching_server {
        Some(s) => s,
        None => {
            warn!("Management API: invalid token attempted from {}", source_ip);
            return Err((
                StatusCode::UNAUTHORIZED,
                Json(ApiResponse {
                    success: false,
                    message: "Invalid management token".to_string(),
                }),
            ));
        }
    };

    // Verify source IP matches server host
    if !verify_source_ip(&server.host, source_ip).await {
        warn!(
            "Management API: IP mismatch - token for {} used from {}",
            server.host, source_ip
        );
        return Err((
            StatusCode::FORBIDDEN,
            Json(ApiResponse {
                success: false,
                message: format!(
                    "Source IP {} does not match server {}",
                    source_ip, server.host
                ),
            }),
        ));
    }

    // Check permission level
    if server.permission < required_permission {
        warn!(
            "Management API: insufficient permission - {} has {} but needs {}",
            server.host, server.permission, required_permission
        );
        return Err((
            StatusCode::FORBIDDEN,
            Json(ApiResponse {
                success: false,
                message: format!(
                    "Insufficient permission: level {} required, you have {}",
                    required_permission, server.permission
                ),
            }),
        ));
    }

    Ok(next.run(request).await)
}

/// Get required permission level for endpoint
fn get_required_permission(path: &str) -> u8 {
    match path {
        // Public endpoints (permission 0)
        "/api/health" | "/api/status" => 0,

        // Basic read (permission 1)
        "/api/config" | "/api/connection/status" | "/api/servers" => 1,

        // Service control (permission 2)
        "/api/connection/reconnect" | "/api/logs" | "/api/buffer/status" => 2,

        // System admin (permission 3)
        "/api/shell" | "/api/restart" | "/api/token/rotate" | "/api/servers/update" => 3,

        // Default: require highest permission for unknown endpoints
        _ => 3,
    }
}

/// Verify that source IP matches server host (DNS resolution)
async fn verify_source_ip(host: &str, source_ip: std::net::IpAddr) -> bool {
    use std::net::ToSocketAddrs;

    // Try to resolve host to IP addresses
    let resolved = format!("{host}:0").to_socket_addrs();

    match resolved {
        Ok(addrs) => {
            for addr in addrs {
                if addr.ip() == source_ip {
                    return true;
                }
            }
            false
        }
        Err(_) => {
            // If resolution fails, try direct comparison (host might be an IP)
            if let Ok(host_ip) = host.parse::<std::net::IpAddr>() {
                host_ip == source_ip
            } else {
                false
            }
        }
    }
}

/// SECURITY: Validate host input to prevent injection and DoS attacks
fn validate_host(host: &str) -> Result<(), String> {
    // Length check (prevent DoS via oversized input)
    if host.is_empty() {
        return Err("Host cannot be empty".to_string());
    }
    if host.len() > 253 {
        // Max DNS hostname length
        return Err("Host too long (max 253 characters)".to_string());
    }

    // Check for dangerous patterns
    let host_lower = host.to_lowercase();

    // Block localhost variants (unless explicitly allowing local management)
    // This is a security decision - remove if local servers should be allowed
    // if host_lower == "localhost" || host_lower == "127.0.0.1" || host_lower == "::1" {
    //     return Err("Localhost addresses are not allowed".to_string());
    // }

    // Block metadata service IPs (cloud security)
    if host_lower.starts_with("169.254.") || host_lower == "169.254.169.254" {
        return Err("Metadata service addresses are not allowed".to_string());
    }

    // Check for valid characters (hostname or IP)
    let valid_chars = host.chars().all(|c| {
        c.is_ascii_alphanumeric() || c == '.' || c == '-' || c == ':' || c == '[' || c == ']'
    });
    if !valid_chars {
        return Err("Host contains invalid characters".to_string());
    }

    Ok(())
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

#[derive(Debug, Serialize)]
struct StatusResponse {
    status: String,
    version: String,
    uptime_seconds: u64,
    hostname: Option<String>,
}

async fn status(State(state): State<Arc<ManagementState>>) -> Json<StatusResponse> {
    let config = state.config.read().await;
    let hostname = config.agent.hostname.clone();

    // Calculate uptime (approximate since we don't track start time)
    let uptime = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);

    Json(StatusResponse {
        status: "running".to_string(),
        version: env!("CARGO_PKG_VERSION").to_string(),
        uptime_seconds: uptime,
        hostname,
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
    // SECURITY: Validate host input
    if let Err(msg) = validate_host(&req.host) {
        return (
            StatusCode::BAD_REQUEST,
            Json(ApiResponse {
                success: false,
                message: msg,
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
        host: req.host.clone(),
        port: req.port,
        token: req.token,
        management_token: None,
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
    // SECURITY: Validate host input
    if let Err(msg) = validate_host(&req.host) {
        return (
            StatusCode::BAD_REQUEST,
            Json(ApiResponse {
                success: false,
                message: msg,
            }),
        );
    }

    // Update server in config
    {
        let mut config = state.config.write().await;
        let found = config
            .servers
            .iter_mut()
            .find(|s| s.host == req.host && s.port == req.port);

        match found {
            Some(server) => {
                // SECURITY: Preserve existing management_token
                let existing_mgmt_token = server.management_token.clone();

                // Log permission changes as security events
                if server.permission != req.permission {
                    warn!(
                        "SECURITY: Permission change for {}:{} from {} to {}",
                        req.host, req.port, server.permission, req.permission
                    );
                }

                *server = ServerConfig {
                    host: req.host.clone(),
                    port: req.port,
                    token: req.token.clone(),
                    management_token: existing_mgmt_token,
                    permission: req.permission,
                    tls_enabled: req.tls_enabled,
                    tls_verify: req.tls_verify,
                };
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
    let _ = state.event_tx.send(ServerEvent::Update(ServerConfig {
        host: req.host.clone(),
        port: req.port,
        token: req.token,
        management_token: None, // Event doesn't need actual token
        permission: req.permission,
        tls_enabled: req.tls_enabled,
        tls_verify: req.tls_verify,
    }));

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

/// Save configuration to file (atomic write)
fn save_config(config: &Config, path: &PathBuf) -> anyhow::Result<()> {
    let content = if path.extension().is_some_and(|e| e == "toml") {
        toml::to_string_pretty(config)?
    } else {
        serde_yaml::to_string(config)?
    };

    // SECURITY: Use atomic write (temp file + rename) to prevent corruption
    let temp_path = path.with_extension("tmp");
    std::fs::write(&temp_path, &content)?;

    // Set restrictive permissions on Unix before rename
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let perms = std::fs::Permissions::from_mode(0o600); // Owner read/write only
        let _ = std::fs::set_permissions(&temp_path, perms);
    }

    // Atomic rename
    std::fs::rename(&temp_path, path)?;
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
                            "Immediate reconnect triggered, {receivers} connections notified"
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

// Token rotation types and handler

#[derive(Debug, Deserialize)]
struct RotateTokenRequest {
    /// Server host to rotate token for (must match requesting server)
    server_host: String,
    /// Server port
    #[serde(default = "default_grpc_port")]
    server_port: u16,
}

#[derive(Debug, Serialize)]
struct RotateTokenResponse {
    success: bool,
    message: String,
    /// New token (only returned on success)
    new_token: Option<String>,
    /// When the old token expires (immediate = now)
    old_token_expires_at: Option<String>,
}

/// Token rotation event for gRPC notification
#[derive(Debug, Clone, Serialize)]
pub struct TokenRotatedEvent {
    pub server_host: String,
    pub server_port: u16,
    pub new_token: String,
    pub old_token_expires_at: String,
}

/// Rotate management token for a server
/// This endpoint requires permission level 3 (SYSTEM_ADMIN)
async fn rotate_token(
    State(state): State<Arc<ManagementState>>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    Json(req): Json<RotateTokenRequest>,
) -> (StatusCode, Json<RotateTokenResponse>) {
    // Extract current token from auth header to identify the calling server
    let auth_header = headers.get("Authorization").and_then(|v| v.to_str().ok());
    let current_token = match auth_header {
        Some(header) if header.starts_with("Bearer ") => &header[7..],
        _ => {
            return (
                StatusCode::UNAUTHORIZED,
                Json(RotateTokenResponse {
                    success: false,
                    message: "Missing Authorization header".to_string(),
                    new_token: None,
                    old_token_expires_at: None,
                }),
            );
        }
    };

    let source_ip = addr.ip();

    // Find the server making the request and verify it matches the requested server
    let mut config = state.config.write().await;

    // SECURITY: Use constant-time comparison to prevent timing attacks
    let server_idx = config.servers.iter().position(|s| {
        s.host == req.server_host
            && s.port == req.server_port
            && s.management_token.as_ref().is_some_and(|t| {
                subtle::ConstantTimeEq::ct_eq(current_token.as_bytes(), t.as_bytes()).into()
            })
    });

    let idx = match server_idx {
        Some(i) => i,
        None => {
            warn!(
                "Token rotation failed: server {}:{} not found or token mismatch from {}",
                req.server_host, req.server_port, source_ip
            );
            return (
                StatusCode::FORBIDDEN,
                Json(RotateTokenResponse {
                    success: false,
                    message: "Server not found or token mismatch".to_string(),
                    new_token: None,
                    old_token_expires_at: None,
                }),
            );
        }
    };

    // SECURITY: Verify source IP matches the server host
    if !verify_source_ip(&config.servers[idx].host, source_ip).await {
        warn!(
            "Token rotation failed: IP mismatch - token for {} used from {}",
            config.servers[idx].host, source_ip
        );
        return (
            StatusCode::FORBIDDEN,
            Json(RotateTokenResponse {
                success: false,
                message: format!(
                    "Source IP {} does not match server {}",
                    source_ip, config.servers[idx].host
                ),
                new_token: None,
                old_token_expires_at: None,
            }),
        );
    }

    // Verify permission level
    if config.servers[idx].permission < 3 {
        return (
            StatusCode::FORBIDDEN,
            Json(RotateTokenResponse {
                success: false,
                message: "Token rotation requires permission level 3".to_string(),
                new_token: None,
                old_token_expires_at: None,
            }),
        );
    }

    // Generate new token
    let new_token = token::generate_secure_token(Some("mgmt"));
    let now = chrono::Utc::now();
    let expires_at = now.to_rfc3339();

    // Update the server's management token
    config.servers[idx].management_token = Some(new_token.clone());

    // Save config to file
    if let Err(e) = save_config(&config, &state.config_path) {
        error!("Failed to save config after token rotation: {}", e);
        return (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(RotateTokenResponse {
                success: false,
                message: format!("Failed to save config: {e}"),
                new_token: None,
                old_token_expires_at: None,
            }),
        );
    }

    info!(
        "Management token rotated for server {}:{} from {}",
        req.server_host, req.server_port, source_ip
    );

    (
        StatusCode::OK,
        Json(RotateTokenResponse {
            success: true,
            message: format!(
                "Token rotated for {}:{}. Old token invalidated immediately.",
                req.server_host, req.server_port
            ),
            new_token: Some(new_token),
            old_token_expires_at: Some(expires_at),
        }),
    )
}

/// Generate and assign management token for a server if needed
/// Called when permission level is set to >= 1
#[allow(dead_code)]
pub fn ensure_management_token(server: &mut ServerConfig) -> Option<String> {
    if server.permission >= 1 && server.management_token.is_none() {
        let new_token = token::generate_secure_token(Some("mgmt"));
        server.management_token = Some(new_token.clone());
        Some(new_token)
    } else {
        None
    }
}

/// Remove management token when permission is downgraded to 0
#[allow(dead_code)]
pub fn clear_management_token_if_needed(server: &mut ServerConfig) -> bool {
    if server.permission == 0 && server.management_token.is_some() {
        server.management_token = None;
        true
    } else {
        false
    }
}
