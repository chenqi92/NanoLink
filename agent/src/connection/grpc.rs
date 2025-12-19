//! gRPC client implementation for NanoLink Agent
//!
//! Provides high-performance bidirectional streaming for metrics and commands.

use std::sync::Arc;
use std::time::Duration;

use anyhow::{Context, Result};
use tokio::sync::mpsc;
use tokio::time;
use tokio_stream::wrappers::ReceiverStream;
use tonic::transport::{Channel, ClientTlsConfig, Endpoint};
use tonic::{Request, Streaming};
use tracing::{debug, error, info, warn};

use crate::buffer::RingBuffer;
use crate::config::{Config, ServerConfig};
use crate::proto::{
    metrics_stream_request, metrics_stream_response,
    nano_link_service_client::NanoLinkServiceClient, AuthRequest, AuthResponse, Command,
    CommandResult, Heartbeat, Metrics, MetricsStreamRequest, MetricsStreamResponse,
};

/// gRPC client for communicating with NanoLink server
pub struct GrpcClient {
    client: NanoLinkServiceClient<Channel>,
    config: Arc<Config>,
    server_config: ServerConfig,
    permission_level: i32,
}

impl GrpcClient {
    /// Connect to a gRPC server
    pub async fn connect(server_config: &ServerConfig, config: &Arc<Config>) -> Result<Self> {
        let url = server_config
            .url
            .replace("grpc://", "http://")
            .replace("grpcs://", "https://");

        let mut endpoint = Endpoint::from_shared(url.clone())
            .context("Invalid server URL")?
            .timeout(Duration::from_secs(30))
            .connect_timeout(Duration::from_secs(10))
            .tcp_keepalive(Some(Duration::from_secs(30)));

        // Configure TLS if using secure connection
        if url.starts_with("https://") || server_config.url.starts_with("grpcs://") {
            let tls_config = if server_config.tls_verify {
                ClientTlsConfig::new()
            } else {
                ClientTlsConfig::new().with_native_roots()
            };
            endpoint = endpoint.tls_config(tls_config)?;
        }

        let channel = endpoint
            .connect()
            .await
            .context("Failed to connect to gRPC server")?;

        let client = NanoLinkServiceClient::new(channel);

        Ok(Self {
            client,
            config: config.clone(),
            server_config: server_config.clone(),
            permission_level: 0,
        })
    }

    /// Authenticate with the server
    pub async fn authenticate(&mut self) -> Result<AuthResponse> {
        let request = Request::new(AuthRequest {
            token: self.server_config.token.clone(),
            hostname: self.config.get_hostname(),
            agent_version: env!("CARGO_PKG_VERSION").to_string(),
            os: std::env::consts::OS.to_string(),
            arch: std::env::consts::ARCH.to_string(),
        });

        let response = self
            .client
            .authenticate(request)
            .await
            .context("Authentication failed")?;

        let auth_response = response.into_inner();

        if auth_response.success {
            self.permission_level = auth_response.permission_level;
            info!(
                "Authenticated with permission level: {}",
                self.permission_level
            );
        } else {
            error!("Authentication failed: {}", auth_response.error_message);
        }

        Ok(auth_response)
    }

    /// Start bidirectional streaming for metrics and commands
    pub async fn stream_metrics(
        &mut self,
        buffer: Arc<RingBuffer>,
        mut command_handler: impl FnMut(Command) -> CommandResult + Send + 'static,
    ) -> Result<()> {
        // Create channel for sending requests
        let (tx, rx) = mpsc::channel::<MetricsStreamRequest>(100);
        let request_stream = ReceiverStream::new(rx);

        // Start the bidirectional stream
        let response = self
            .client
            .stream_metrics(Request::new(request_stream))
            .await
            .context("Failed to start metrics stream")?;

        let mut response_stream: Streaming<MetricsStreamResponse> = response.into_inner();

        // Spawn task to send metrics
        let tx_clone = tx.clone();
        let config = self.config.clone();
        let buffer_clone = buffer.clone();

        let sender_handle = tokio::spawn(async move {
            let mut interval =
                time::interval(Duration::from_millis(config.collector.cpu_interval_ms));
            let mut heartbeat_interval =
                time::interval(Duration::from_secs(config.agent.heartbeat_interval));

            loop {
                tokio::select! {
                    _ = interval.tick() => {
                        // Get latest metrics from buffer
                        if let Some(metrics) = buffer_clone.latest() {
                            let request = MetricsStreamRequest {
                                request: Some(metrics_stream_request::Request::Metrics(metrics)),
                            };
                            if tx_clone.send(request).await.is_err() {
                                break;
                            }
                        }
                    }
                    _ = heartbeat_interval.tick() => {
                        let heartbeat = Heartbeat {
                            timestamp: chrono::Utc::now().timestamp_millis() as u64,
                            uptime_seconds: 0, // TODO: Calculate uptime
                        };
                        let request = MetricsStreamRequest {
                            request: Some(metrics_stream_request::Request::Heartbeat(heartbeat)),
                        };
                        if tx_clone.send(request).await.is_err() {
                            break;
                        }
                    }
                }
            }
        });

        // Handle responses from server
        while let Some(response) = response_stream.message().await? {
            match response.response {
                Some(metrics_stream_response::Response::Command(cmd)) => {
                    info!("Received command: {:?}", cmd.r#type);
                    let result = command_handler(cmd);

                    // Send command result back
                    let request = MetricsStreamRequest {
                        request: Some(metrics_stream_request::Request::CommandResult(result)),
                    };
                    if tx.send(request).await.is_err() {
                        break;
                    }
                }
                Some(metrics_stream_response::Response::HeartbeatAck(ack)) => {
                    debug!("Heartbeat acknowledged: {}", ack.timestamp);
                }
                Some(metrics_stream_response::Response::ConfigUpdate(config)) => {
                    info!("Received config update from server");
                    // TODO: Apply config update
                }
                None => {}
            }
        }

        sender_handle.abort();
        Ok(())
    }

    /// Report metrics using unary RPC (simpler, but less efficient)
    pub async fn report_metrics(&mut self, metrics: Metrics) -> Result<()> {
        let response = self
            .client
            .report_metrics(Request::new(metrics))
            .await
            .context("Failed to report metrics")?;

        let ack = response.into_inner();
        if !ack.success {
            warn!("Metrics report was not acknowledged");
        }

        Ok(())
    }

    /// Execute a command (used for testing or direct command execution)
    pub async fn execute_command(&mut self, command: Command) -> Result<CommandResult> {
        let response = self
            .client
            .execute_command(Request::new(command))
            .await
            .context("Failed to execute command")?;

        Ok(response.into_inner())
    }
}

/// gRPC connection manager
pub struct GrpcConnectionManager {
    config: Arc<Config>,
    buffer: Arc<RingBuffer>,
}

impl GrpcConnectionManager {
    /// Create a new gRPC connection manager
    pub fn new(config: Arc<Config>, buffer: Arc<RingBuffer>) -> Self {
        Self { config, buffer }
    }

    /// Run the gRPC connection manager
    pub async fn run(self) {
        info!(
            "gRPC connection manager started with {} server(s)",
            self.config.servers.len()
        );

        // Only connect to servers configured for gRPC
        let grpc_servers: Vec<_> = self
            .config
            .servers
            .iter()
            .filter(|s| s.url.starts_with("grpc://") || s.url.starts_with("grpcs://"))
            .cloned()
            .collect();

        if grpc_servers.is_empty() {
            info!("No gRPC servers configured");
            return;
        }

        let mut handles = Vec::new();

        for server_config in grpc_servers {
            let config = self.config.clone();
            let buffer = self.buffer.clone();

            let handle = tokio::spawn(async move {
                Self::manage_connection(config, buffer, server_config).await;
            });

            handles.push(handle);
        }

        for handle in handles {
            let _ = handle.await;
        }
    }

    /// Manage a single gRPC connection with reconnection logic
    async fn manage_connection(config: Arc<Config>, buffer: Arc<RingBuffer>, server: ServerConfig) {
        let mut reconnect_delay = config.agent.reconnect_delay;
        let max_delay = config.agent.max_reconnect_delay;

        loop {
            info!("Connecting to gRPC server: {}", server.url);

            match GrpcClient::connect(&server, &config).await {
                Ok(mut client) => {
                    reconnect_delay = config.agent.reconnect_delay;

                    // Authenticate
                    match client.authenticate().await {
                        Ok(auth) if auth.success => {
                            info!("gRPC authenticated successfully");

                            // Start streaming
                            if let Err(e) = client
                                .stream_metrics(buffer.clone(), |cmd| {
                                    // TODO: Implement command handler
                                    CommandResult {
                                        command_id: cmd.command_id,
                                        success: true,
                                        output: "Command received".to_string(),
                                        error: String::new(),
                                        file_content: vec![],
                                        processes: vec![],
                                        containers: vec![],
                                    }
                                })
                                .await
                            {
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
                "Reconnecting to gRPC server {} in {} seconds...",
                server.url, reconnect_delay
            );
            time::sleep(Duration::from_secs(reconnect_delay)).await;

            reconnect_delay = (reconnect_delay * 2).min(max_delay);
        }
    }
}
