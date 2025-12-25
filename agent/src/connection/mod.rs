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
        let initial_delay = config.agent.reconnect_delay;
        let max_delay = config.agent.max_reconnect_delay;
        let grpc_url = server.get_grpc_url();
        let mut connection_attempts: u32 = 0;
        let mut total_connected_time: u64 = 0;
        let mut was_previously_connected = false;
        let mut reconnect_delay = initial_delay;

        loop {
            connection_attempts += 1;
            info!(
                "Connecting to gRPC server: {} (attempt #{})",
                grpc_url, connection_attempts
            );

            // If we were previously connected, use fast retry for first few attempts
            if was_previously_connected && connection_attempts <= 3 {
                reconnect_delay = initial_delay; // Reset to initial delay for quick reconnect
            }

            let connect_start = std::time::Instant::now();
            match grpc::GrpcClient::connect(&server, &config).await {
                Ok(mut client) => {
                    let connect_elapsed = connect_start.elapsed();
                    let connection_start = std::time::Instant::now();
                    info!(
                        "gRPC connection established to {} (connect took {:?})",
                        grpc_url, connect_elapsed
                    );

                    // Reset reconnect delay and attempts on successful connection
                    reconnect_delay = initial_delay;
                    connection_attempts = 0;
                    was_previously_connected = true;

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

                            let connection_duration = connection_start.elapsed();
                            total_connected_time += connection_duration.as_secs();

                            match &stream_result {
                                Ok(_) => {
                                    warn!(
                                        "gRPC stream ended normally for {} after {:?} (server may have closed the connection)",
                                        grpc_url, connection_duration
                                    );
                                }
                                Err(e) => {
                                    error!(
                                        "gRPC stream error for {} after {:?}: {:?}",
                                        grpc_url, connection_duration, e
                                    );
                                }
                            }
                        }
                        Ok(auth) => {
                            error!(
                                "gRPC authentication failed for {}: {}",
                                grpc_url, auth.error_message
                            );
                        }
                        Err(e) => {
                            error!("gRPC authentication error for {}: {}", grpc_url, e);
                        }
                    }

                    warn!(
                        "gRPC connection to {} lost, will reconnect (total connected time: {}s)",
                        grpc_url, total_connected_time
                    );
                }
                Err(e) => {
                    let connect_elapsed = connect_start.elapsed();
                    error!(
                        "Failed to connect to gRPC server {} (attempt #{}, took {:?}): {:?}",
                        grpc_url, connection_attempts, connect_elapsed, e
                    );
                }
            }

            // Wait before reconnecting with exponential backoff
            info!(
                "Reconnecting to {} in {} seconds (next delay: {}s)...",
                grpc_url,
                reconnect_delay,
                (reconnect_delay * 2).min(max_delay)
            );
            time::sleep(Duration::from_secs(reconnect_delay)).await;

            // Exponential backoff, capped at max_delay
            reconnect_delay = (reconnect_delay * 2).min(max_delay);
        }
    }
}

/// Connection state for tracking connection lifecycle
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[allow(dead_code)]
pub enum ConnectionState {
    Disconnected,
    Connecting,
    Connected,
    Authenticating,
    Authenticated,
}
