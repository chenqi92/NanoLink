//! Connection management for NanoLink Agent
//!
//! Manages gRPC connections to NanoLink servers with automatic reconnection.

pub mod grpc;
mod handler;

use std::path::PathBuf;
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
#[allow(dead_code)]
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
    /// Shared, mutable config used to persist server-pushed config_update.
    shared_config: Arc<RwLock<Config>>,
    /// Path to the on-disk config file (for persisting config_update).
    config_path: PathBuf,
    buffer: Arc<RingBuffer>,
    /// Broadcast sender for connection signals
    signal_tx: broadcast::Sender<ConnectionSignal>,
    /// Connection status for each server
    status: Arc<RwLock<Vec<ConnectionStatus>>>,
}

#[derive(Debug, Clone)]
struct ServerIdentity {
    host: String,
    port: u16,
}

impl ServerIdentity {
    fn matches(&self, server: &ServerConfig) -> bool {
        self.host == server.host && self.port == server.port
    }
}

fn connection_snapshot(
    config: &Config,
    identity: &ServerIdentity,
) -> Option<(Arc<Config>, ServerConfig)> {
    let server = config
        .servers
        .iter()
        .find(|server| identity.matches(server))?
        .clone();
    Some((Arc::new(config.clone()), server))
}

impl ConnectionManager {
    /// Create a new connection manager
    ///
    /// `config` is an immutable snapshot used to build streams; `shared_config`
    /// and `config_path` allow a server-pushed config_update to be persisted to
    /// disk before triggering a reconnect that rebuilds from fresh config.
    pub fn new(
        config: Arc<Config>,
        shared_config: Arc<RwLock<Config>>,
        config_path: PathBuf,
        buffer: Arc<RingBuffer>,
    ) -> Self {
        let (signal_tx, _) = broadcast::channel(16);
        let status = Arc::new(RwLock::new(Vec::new()));
        Self {
            config,
            shared_config,
            config_path,
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
        // JoinSet aborts all still-running connection tasks when this manager
        // future is cancelled by the service shutdown path.
        let mut handles = tokio::task::JoinSet::new();

        for (idx, server_config) in self.config.servers.iter().enumerate() {
            let shared_config = self.shared_config.clone();
            let config_path = self.config_path.clone();
            let buffer = self.buffer.clone();
            let server_identity = ServerIdentity {
                host: server_config.host.clone(),
                port: server_config.port,
            };
            let signal_rx = self.signal_tx.subscribe();
            let signal_tx = self.signal_tx.clone();
            let status = self.status.clone();

            info!(
                "Connecting to gRPC server: {}:{}",
                server_identity.host, server_identity.port
            );

            handles.spawn(async move {
                Self::manage_grpc_connection(
                    shared_config,
                    config_path,
                    buffer,
                    server_identity,
                    signal_rx,
                    signal_tx,
                    status,
                    idx,
                )
                .await;
            });
        }

        // Wait for all connections to complete (they shouldn't unless shutdown)
        while handles.join_next().await.is_some() {}
    }

    /// Manage a gRPC connection with reconnection logic
    #[allow(clippy::too_many_arguments)]
    async fn manage_grpc_connection(
        shared_config: Arc<RwLock<Config>>,
        config_path: PathBuf,
        buffer: Arc<RingBuffer>,
        server_identity: ServerIdentity,
        mut signal_rx: broadcast::Receiver<ConnectionSignal>,
        signal_tx: broadcast::Sender<ConnectionSignal>,
        status: Arc<RwLock<Vec<ConnectionStatus>>>,
        status_idx: usize,
    ) {
        let mut initial_delay: u64;
        let mut max_delay: u64;
        let mut grpc_url: String;
        let mut connection_attempts: u32 = 0;
        let mut total_connected_time: u64 = 0;
        let mut was_previously_connected = false;
        let mut reconnect_delay = 1;
        let pending_results: grpc::PendingCommandResults =
            Arc::new(tokio::sync::Mutex::new(std::collections::HashMap::new()));

        loop {
            // Always rebuild the connection from the latest shared configuration.
            // Management API token/TLS updates and server-pushed collector changes
            // are persisted there; reusing the startup snapshot would otherwise
            // make every reconnect retry stale credentials forever.
            let (config, server) = {
                let config = shared_config.read().await;
                let Some(snapshot) = connection_snapshot(&config, &server_identity) else {
                    info!(
                        "Server {}:{} was removed from configuration; stopping its connection task",
                        server_identity.host, server_identity.port
                    );
                    return;
                };
                snapshot
            };
            initial_delay = config.agent.reconnect_delay.max(1);
            max_delay = config.agent.max_reconnect_delay.max(initial_delay);
            reconnect_delay = reconnect_delay.clamp(initial_delay, max_delay);
            grpc_url = server.get_grpc_url();
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
            match grpc::GrpcClient::connect(
                &server,
                &config,
                shared_config.clone(),
                config_path.clone(),
                signal_tx.clone(),
            )
            .await
            {
                Ok(mut client) => {
                    let connect_elapsed = connect_start.elapsed();
                    let connection_start = std::time::Instant::now();
                    info!(
                        "gRPC connection established to {} (connect took {:?})",
                        grpc_url, connect_elapsed
                    );

                    // Authenticate
                    match client.authenticate().await {
                        Ok(auth) if auth.success => {
                            // A TCP handshake alone is not a healthy connection.
                            // Reset backoff only after credentials are accepted;
                            // otherwise an expired token retries forever at the
                            // minimum delay and can hammer the server.
                            reconnect_delay = initial_delay;
                            connection_attempts = 0;
                            was_previously_connected = true;
                            {
                                let mut s = status.write().await;
                                if let Some(st) = s.get_mut(status_idx) {
                                    st.connected = true;
                                    st.last_error = None;
                                    st.connection_attempts = 0;
                                }
                            }
                            info!(
                                "gRPC authenticated with permission level: {}",
                                auth.permission_level
                            );

                            // Data compensation: send buffered data if enabled
                            if config.buffer.data_compensation {
                                Self::send_compensated_data(&mut client, &buffer, &config).await;
                            }

                            // Start streaming metrics based on config
                            let use_layered_metrics = config.collector.enable_layered_metrics;
                            let message_handler = std::sync::Arc::new(MessageHandler::new(
                                config.clone(),
                                buffer.clone(),
                                auth.permission_level as u8,
                            ));
                            let stream_future = async {
                                if use_layered_metrics {
                                    info!("Using layered metrics stream");
                                    client
                                        .stream_layered_metrics(
                                            pending_results.clone(),
                                            move |cmd| {
                                                let handler = message_handler.clone();
                                                async move { handler.handle_command(cmd).await }
                                            },
                                        )
                                        .await
                                } else {
                                    info!("Using legacy metrics stream");
                                    client
                                        .stream_metrics(
                                            buffer.clone(),
                                            pending_results.clone(),
                                            move |cmd| {
                                                let handler = message_handler.clone();
                                                async move { handler.handle_command(cmd).await }
                                            },
                                        )
                                        .await
                                }
                            };
                            tokio::pin!(stream_future);

                            // A runtime token/TLS update must also interrupt a
                            // healthy stream. Previously signals were only polled
                            // after disconnection, so an online agent kept the old
                            // credential until the transport happened to fail.
                            let (stream_result, reconnect_now) = tokio::select! {
                                result = &mut stream_future => (Some(result), false),
                                signal = signal_rx.recv() => {
                                    match signal {
                                        Ok(ConnectionSignal::ImmediateReconnect) => {
                                            info!("Received immediate reconnect signal for {}", grpc_url);
                                            (None, true)
                                        }
                                        Ok(ConnectionSignal::Shutdown) => {
                                            info!("Received shutdown signal, stopping connection manager");
                                            return;
                                        }
                                        Err(error) => {
                                            warn!("Connection signal channel error: {}", error);
                                            (None, false)
                                        }
                                    }
                                }
                            };

                            let connection_duration = connection_start.elapsed();
                            total_connected_time += connection_duration.as_secs();

                            match &stream_result {
                                Some(Ok(_)) => {
                                    warn!(
                                        "gRPC stream ended normally for {} after {:?} (server may have closed the connection)",
                                        grpc_url, connection_duration
                                    );
                                }
                                Some(Err(e)) => {
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
                                None => {}
                            }

                            if reconnect_now {
                                let mut s = status.write().await;
                                if let Some(st) = s.get_mut(status_idx) {
                                    st.connected = false;
                                    st.reconnect_delay_secs = initial_delay;
                                }
                                continue;
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reconnect_snapshot_uses_updated_token_and_runtime_config() {
        let mut config = Config::sample();
        let identity = ServerIdentity {
            host: config.servers[0].host.clone(),
            port: config.servers[0].port,
        };
        config.servers[0].token = "rotated-token".to_string();
        config.agent.heartbeat_interval = 7;

        let (snapshot, server) = connection_snapshot(&config, &identity).unwrap();
        assert_eq!(server.token, "rotated-token");
        assert_eq!(snapshot.agent.heartbeat_interval, 7);
    }

    #[test]
    fn reconnect_snapshot_stops_removed_server() {
        let mut config = Config::sample();
        let identity = ServerIdentity {
            host: config.servers[0].host.clone(),
            port: config.servers[0].port,
        };
        config.servers.clear();

        assert!(connection_snapshot(&config, &identity).is_none());
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
