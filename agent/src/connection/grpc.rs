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
        let url = server_config.get_grpc_url();

        let mut endpoint = Endpoint::from_shared(url.clone())
            .context("Invalid server URL")?
            .timeout(Duration::from_secs(30))
            .connect_timeout(Duration::from_secs(10))
            .tcp_keepalive(Some(Duration::from_secs(30)));

        // Configure TLS if enabled
        if server_config.tls_enabled {
            let tls_config = ClientTlsConfig::new();
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
