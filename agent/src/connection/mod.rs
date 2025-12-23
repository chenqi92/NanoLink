//! Connection management for NanoLink Agent
//!
//! Manages gRPC connections to NanoLink servers with automatic reconnection.

pub mod grpc;
mod handler;

use std::sync::Arc;
use std::time::Duration;
use tokio::time;
use tracing::{error, info, warn};

use crate::buffer::RingBuffer;
use crate::config::{Config, ServerConfig};

pub use handler::MessageHandler;

/// Manages gRPC connections to multiple servers
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

        // Spawn gRPC connection tasks for each server
        let mut handles = Vec::new();

        for server_config in &self.config.servers {
            let config = self.config.clone();
            let buffer = self.buffer.clone();
            let server = server_config.clone();

            info!("Connecting to gRPC server: {}:{}", server.host, server.port);

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
    async fn manage_grpc_connection(
        config: Arc<Config>,
        buffer: Arc<RingBuffer>,
        server: ServerConfig,
    ) {
        let mut reconnect_delay = config.agent.reconnect_delay;
        let max_delay = config.agent.max_reconnect_delay;
        let grpc_url = server.get_grpc_url();

        loop {
            info!("Connecting to gRPC server: {}", grpc_url);

            match grpc::GrpcClient::connect(&server, &config).await {
                Ok(mut client) => {
                    // Reset reconnect delay on successful connection
                    reconnect_delay = config.agent.reconnect_delay;

                    // Authenticate
                    match client.authenticate().await {
                        Ok(auth) if auth.success => {
                            info!(
                                "gRPC authenticated with permission level: {}",
                                auth.permission_level
                            );

                            // Start streaming metrics based on config
                            let stream_result = if config.collector.enable_layered_metrics {
                                info!("Using layered metrics stream");
                                // Create MessageHandler with all executors and permission checker
                                let message_handler = std::sync::Arc::new(MessageHandler::new(
                                    config.clone(),
                                    buffer.clone(),
                                    auth.permission_level as u8,
                                ));

                                client
                                    .stream_layered_metrics(move |cmd| {
                                        let handler = message_handler.clone();
                                        async move { handler.handle_command(cmd).await }
                                    })
                                    .await
                            } else {
                                info!("Using legacy metrics stream");
                                // Create MessageHandler with all executors and permission checker
                                let message_handler = std::sync::Arc::new(MessageHandler::new(
                                    config.clone(),
                                    buffer.clone(),
                                    auth.permission_level as u8,
                                ));

                                client
                                    .stream_metrics(buffer.clone(), move |cmd| {
                                        let handler = message_handler.clone();
                                        async move { handler.handle_command(cmd).await }
                                    })
                                    .await
                            };

                            if let Err(e) = stream_result {
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

                    warn!("gRPC connection to {} lost", grpc_url);
                }
                Err(e) => {
                    error!("Failed to connect to gRPC server {}: {}", grpc_url, e);
                }
            }

            // Wait before reconnecting with exponential backoff
            info!(
                "Reconnecting to {} in {} seconds...",
                grpc_url, reconnect_delay
            );
            time::sleep(Duration::from_secs(reconnect_delay)).await;

            // Exponential backoff, capped at max_delay
            reconnect_delay = (reconnect_delay * 2).min(max_delay);
        }
    }
}

/// Connection state for tracking connection lifecycle
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConnectionState {
    Disconnected,
    Connecting,
    Connected,
    Authenticating,
    Authenticated,
}
