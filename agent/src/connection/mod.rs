//! Connection management for NanoLink Agent
//!
//! Manages gRPC connections to NanoLink servers with automatic reconnection.

pub mod grpc;
mod handler;

use std::sync::Arc;
use std::time::Duration;
use tokio::sync::{RwLock, broadcast};
use tokio::time;
use tracing::{error, info, warn};

use crate::buffer::RingBuffer;
use crate::config::{Config, ServerConfig};

pub use handler::MessageHandler;

/// Signal types for connection control
#[derive(Debug, Clone)]
pub enum ConnectionSignal {
    /// Trigger immediate reconnection attempt
    ImmediateReconnect,
    /// Shutdown the connection
    Shutdown,
}

/// Connection status for external monitoring
#[derive(Debug, Clone)]
pub struct ConnectionStatus {
    pub server: String,
    pub connected: bool,
    pub last_error: Option<String>,
    pub reconnect_delay_secs: u64,
    pub connection_attempts: u32,
}

/// Manages gRPC connections to multiple servers
pub struct ConnectionManager {
    config: Arc<Config>,
    buffer: Arc<RingBuffer>,
    /// Broadcast sender for connection signals
    signal_tx: broadcast::Sender<ConnectionSignal>,
    /// Connection status for each server
    status: Arc<RwLock<Vec<ConnectionStatus>>>,
}

impl ConnectionManager {
    /// Create a new connection manager
    pub fn new(config: Arc<Config>, buffer: Arc<RingBuffer>) -> Self {
        let (signal_tx, _) = broadcast::channel(16);
        let status = Arc::new(RwLock::new(Vec::new()));
        Self {
            config,
            buffer,
            signal_tx,
            status,
        }
    }

    /// Get a signal sender for external control
    pub fn get_signal_sender(&self) -> broadcast::Sender<ConnectionSignal> {
        self.signal_tx.clone()
    }

    /// Get connection status
    pub fn get_status(&self) -> Arc<RwLock<Vec<ConnectionStatus>>> {
        self.status.clone()
    }

    /// Run the connection manager
    pub async fn run(self) {
        info!(
            "Connection manager started with {} server(s)",
            self.config.servers.len()
        );

        // Initialize status for each server
        {
            let mut status = self.status.write().await;
            for server in &self.config.servers {
                status.push(ConnectionStatus {
                    server: format!("{}:{}", server.host, server.port),
                    connected: false,
                    last_error: None,
                    reconnect_delay_secs: self.config.agent.reconnect_delay,
                    connection_attempts: 0,
                });
            }
        }

        // Spawn gRPC connection tasks for each server
        let mut handles = Vec::new();

        for (idx, server_config) in self.config.servers.iter().enumerate() {
            let config = self.config.clone();
            let buffer = self.buffer.clone();
            let server = server_config.clone();
            let signal_rx = self.signal_tx.subscribe();
            let status = self.status.clone();

            info!("Connecting to gRPC server: {}:{}", server.host, server.port);

            let handle = tokio::spawn(async move {
                Self::manage_grpc_connection(config, buffer, server, signal_rx, status, idx).await;
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
        mut signal_rx: broadcast::Receiver<ConnectionSignal>,
        status: Arc<RwLock<Vec<ConnectionStatus>>>,
        status_idx: usize,
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

            // Update status
            {
                let mut s = status.write().await;
                if let Some(st) = s.get_mut(status_idx) {
                    st.connection_attempts = connection_attempts;
                    st.reconnect_delay_secs = reconnect_delay;
                }
            }

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

                    // Update status - connected
                    {
                        let mut s = status.write().await;
                        if let Some(st) = s.get_mut(status_idx) {
                            st.connected = true;
                            st.last_error = None;
                            st.connection_attempts = 0;
                        }
                    }

                    // Authenticate
                    match client.authenticate().await {
                        Ok(auth) if auth.success => {
                            info!(
                                "gRPC authenticated with permission level: {}",
                                auth.permission_level
                            );

                            // Data compensation: send buffered data if enabled
                            if config.buffer.data_compensation {
                                Self::send_compensated_data(&mut client, &buffer, &config).await;
                            }

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
                                    // Update status with error
                                    let mut s = status.write().await;
                                    if let Some(st) = s.get_mut(status_idx) {
                                        st.last_error = Some(e.to_string());
                                    }
                                }
                            }
                        }
                        Ok(auth) => {
                            error!(
                                "gRPC authentication failed for {}: {}",
                                grpc_url, auth.error_message
                            );
                            let mut s = status.write().await;
                            if let Some(st) = s.get_mut(status_idx) {
                                st.last_error = Some(auth.error_message.clone());
                            }
                        }
                        Err(e) => {
                            error!("gRPC authentication error for {}: {}", grpc_url, e);
                            let mut s = status.write().await;
                            if let Some(st) = s.get_mut(status_idx) {
                                st.last_error = Some(e.to_string());
                            }
                        }
                    }

                    // Update status - disconnected
                    {
                        let mut s = status.write().await;
                        if let Some(st) = s.get_mut(status_idx) {
                            st.connected = false;
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
                    // Update status with error
                    let mut s = status.write().await;
                    if let Some(st) = s.get_mut(status_idx) {
                        st.last_error = Some(e.to_string());
                    }
                }
            }

            // Update status before waiting
            {
                let mut s = status.write().await;
                if let Some(st) = s.get_mut(status_idx) {
                    st.reconnect_delay_secs = reconnect_delay;
                }
            }

            // Wait before reconnecting with exponential backoff
            // But check for immediate reconnect signal
            info!(
                "Reconnecting to {} in {} seconds (next delay: {}s)...",
                grpc_url,
                reconnect_delay,
                (reconnect_delay * 2).min(max_delay)
            );

            // Use select to either wait for timeout or receive immediate reconnect signal
            let sleep_duration = Duration::from_secs(reconnect_delay);
            tokio::select! {
                _ = time::sleep(sleep_duration) => {
                    // Normal timeout, continue with backoff
                }
                signal = signal_rx.recv() => {
                    match signal {
                        Ok(ConnectionSignal::ImmediateReconnect) => {
                            info!("Received immediate reconnect signal, attempting connection now");
                            reconnect_delay = initial_delay; // Reset delay for immediate retry
                            continue;
                        }
                        Ok(ConnectionSignal::Shutdown) => {
                            info!("Received shutdown signal, stopping connection manager");
                            return;
                        }
                        Err(_) => {
                            // Channel closed, continue normally
                        }
                    }
                }
            }

            // Exponential backoff, capped at max_delay
            reconnect_delay = (reconnect_delay * 2).min(max_delay);
        }
    }

    /// Send compensated (buffered) data after reconnection
    async fn send_compensated_data(
        client: &mut grpc::GrpcClient,
        buffer: &Arc<RingBuffer>,
        config: &Arc<Config>,
    ) {
        let unsynced = buffer.get_unsynced();
        let count = unsynced.len();

        if count == 0 {
            info!("No unsynced data to compensate");
            return;
        }

        info!(
            "Starting data compensation: {} unsynced metrics to send",
            count
        );

        let batch_size = config.buffer.compensation_batch_size;
        let mut sent = 0;
        let mut last_timestamp = buffer.get_last_sync_timestamp();

        for batch in unsynced.chunks(batch_size) {
            for metrics in batch {
                match client.report_metrics(metrics.clone()).await {
                    Ok(_) => {
                        sent += 1;
                        if metrics.timestamp > last_timestamp {
                            last_timestamp = metrics.timestamp;
                        }
                    }
                    Err(e) => {
                        warn!(
                            "Failed to send compensated metrics (timestamp: {}): {}",
                            metrics.timestamp, e
                        );
                        // Update sync timestamp to last successful
                        buffer.set_last_sync_timestamp(last_timestamp);
                        info!(
                            "Data compensation interrupted: sent {}/{} metrics",
                            sent, count
                        );
                        return;
                    }
                }
            }

            // Small delay between batches to avoid overwhelming the server
            if batch.len() == batch_size {
                time::sleep(Duration::from_millis(50)).await;
            }
        }

        // Update sync timestamp after successful compensation
        buffer.set_last_sync_timestamp(last_timestamp);
        info!(
            "Data compensation completed: sent {}/{} metrics",
            sent, count
        );
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
