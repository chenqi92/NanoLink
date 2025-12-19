mod handler;
mod websocket;
pub mod grpc;

use std::sync::Arc;
use std::time::Duration;
use tokio::sync::broadcast;
use tokio::time;
use tracing::{debug, error, info, warn};

use crate::buffer::RingBuffer;
use crate::config::{Config, Protocol, ServerConfig};
use crate::proto::Metrics;

pub use handler::MessageHandler;
pub use websocket::WebSocketClient;
pub use grpc::GrpcConnectionManager;

/// Manages connections to multiple servers
pub struct ConnectionManager {
    config: Arc<Config>,
    buffer: Arc<RingBuffer>,
}

impl ConnectionManager {
    /// Create a new connection manager
    pub fn new(config: Arc<Config>, buffer: Arc<RingBuffer>) -> Self {
        Self { config, buffer }
    }

    /// Run the connection manager
    pub async fn run(self) {
        info!(
            "Connection manager started with {} server(s)",
            self.config.servers.len()
        );

        // Separate servers by protocol
        let mut ws_servers = Vec::new();
        let mut grpc_servers = Vec::new();

        for server_config in &self.config.servers {
            match server_config.get_protocol() {
                Protocol::WebSocket => ws_servers.push(server_config.clone()),
                Protocol::Grpc => grpc_servers.push(server_config.clone()),
            }
        }

        info!(
            "Protocols: {} WebSocket, {} gRPC",
            ws_servers.len(),
            grpc_servers.len()
        );

        // Spawn WebSocket connection tasks
        let mut handles = Vec::new();

        for server_config in ws_servers {
            let config = self.config.clone();
            let buffer = self.buffer.clone();
            let server = server_config.clone();

            let handle = tokio::spawn(async move {
                Self::manage_websocket_connection(config, buffer, server).await;
            });

            handles.push(handle);
        }

        // Spawn gRPC connection tasks
        for server_config in grpc_servers {
            let config = self.config.clone();
            let buffer = self.buffer.clone();
            let server = server_config.clone();

            let handle = tokio::spawn(async move {
                Self::manage_grpc_connection(config, buffer, server).await;
            });

            handles.push(handle);
        }

        // Wait for all connections to complete (they shouldn't unless shutdown)
        for handle in handles {
            let _ = handle.await;
        }
    }

    /// Manage a gRPC connection with reconnection logic
    async fn manage_grpc_connection(config: Arc<Config>, buffer: Arc<RingBuffer>, server: ServerConfig) {
        let mut reconnect_delay = config.agent.reconnect_delay;
        let max_delay = config.agent.max_reconnect_delay;

        loop {
            info!("Connecting to gRPC server: {}", server.url);

            match grpc::GrpcClient::connect(&server, &config).await {
                Ok(mut client) => {
                    reconnect_delay = config.agent.reconnect_delay;

                    // Authenticate
                    match client.authenticate().await {
                        Ok(auth) if auth.success => {
                            info!("gRPC authenticated with permission level: {}", auth.permission_level);

                            // Start streaming
                            if let Err(e) = client.stream_metrics(
                                buffer.clone(),
                                |cmd| {
                                    // TODO: Integrate with executor module
                                    crate::proto::CommandResult {
                                        command_id: cmd.command_id,
                                        success: true,
                                        output: "Command received via gRPC".to_string(),
                                        error: String::new(),
                                        file_content: vec![],
                                        processes: vec![],
                                        containers: vec![],
                                    }
                                },
                            ).await {
                                error!("gRPC stream error: {}", e);
                            }
                        }
                        Ok(auth) => {
                            error!("gRPC authentication failed: {}", auth.error_message);
                        }
                        Err(e) => {
                            error!("gRPC authentication error: {}", e);
                        }
                    }

                    warn!("gRPC connection to {} lost", server.url);
                }
                Err(e) => {
                    error!("Failed to connect to gRPC server {}: {}", server.url, e);
                }
            }

            info!(
                "Reconnecting to gRPC {} in {} seconds...",
                server.url, reconnect_delay
            );
            time::sleep(Duration::from_secs(reconnect_delay)).await;

            reconnect_delay = (reconnect_delay * 2).min(max_delay);
        }
    }

    /// Manage a WebSocket connection with reconnection logic
    async fn manage_websocket_connection(config: Arc<Config>, buffer: Arc<RingBuffer>, server: ServerConfig) {
        let mut reconnect_delay = config.agent.reconnect_delay;
        let max_delay = config.agent.max_reconnect_delay;

        loop {
            info!("Connecting to {}", server.url);

            match WebSocketClient::connect(&server, &config).await {
                Ok(mut client) => {
                    // Reset reconnect delay on successful connection
                    reconnect_delay = config.agent.reconnect_delay;

                    // Create message handler
                    let handler = MessageHandler::new(
                        config.clone(),
                        buffer.clone(),
                        server.permission,
                    );

                    // Run the client
                    if let Err(e) = client.run(handler, &config, &buffer).await {
                        error!("Connection error: {}", e);
                    }

                    warn!("Connection to {} lost", server.url);
                }
                Err(e) => {
                    error!("Failed to connect to {}: {}", server.url, e);
                }
            }

            // Wait before reconnecting
            info!(
                "Reconnecting to {} in {} seconds...",
                server.url, reconnect_delay
            );
            time::sleep(Duration::from_secs(reconnect_delay)).await;

            // Exponential backoff
            reconnect_delay = (reconnect_delay * 2).min(max_delay);
        }
    }
}

/// Connection state
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConnectionState {
    Disconnected,
    Connecting,
    Connected,
    Authenticating,
    Authenticated,
}
