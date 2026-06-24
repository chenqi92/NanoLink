//! gRPC client implementation for NanoLink Agent
//!
//! Provides high-performance bidirectional streaming for metrics and commands.

use std::path::PathBuf;
use std::sync::{Arc, OnceLock};
use std::time::{Duration, Instant};

use anyhow::{Context, Result};
use tokio::sync::{RwLock, broadcast, mpsc};
use tokio::task::JoinHandle;
use tokio::time;
use tokio_stream::wrappers::ReceiverStream;
use tonic::metadata::MetadataValue;
use tonic::transport::{Channel, ClientTlsConfig, Endpoint};
use tonic::{Request, Streaming};
use tracing::{debug, error, info, warn};

use crate::buffer::RingBuffer;
use crate::collector::layered::{DataRequest, LayeredCollector, LayeredMetricsMessage};
use crate::config::{Config, ServerConfig};
use crate::connection::ConnectionSignal;
use crate::proto::{
    AgentInit, AuthRequest, AuthResponse, Command, CommandResult, DataRequestType, Heartbeat,
    Metrics, MetricsStreamRequest, MetricsStreamResponse, metrics_stream_request,
    metrics_stream_response, nano_link_service_client::NanoLinkServiceClient,
};

/// Process start time, captured the first time `agent_uptime_seconds` is called.
///
/// We don't take this from boot in main() because the gRPC layer is the only
/// consumer (heartbeat reporting), so lazy-init keeps the dependency direction
/// clean. Once captured, the same instant is reused for every heartbeat across
/// reconnects.
static AGENT_START: OnceLock<Instant> = OnceLock::new();

fn agent_uptime_seconds() -> u64 {
    AGENT_START.get_or_init(Instant::now).elapsed().as_secs()
}

/// Guard that ensures spawned tasks are aborted when dropped.
/// This is critical for cleanup when stream errors cause early returns via `?`.
struct TaskCleanupGuard {
    handles: Vec<JoinHandle<()>>,
}

impl TaskCleanupGuard {
    fn new() -> Self {
        Self {
            handles: Vec::new(),
        }
    }

    fn add(&mut self, handle: JoinHandle<()>) {
        self.handles.push(handle);
    }
}

impl Drop for TaskCleanupGuard {
    fn drop(&mut self) {
        for handle in &self.handles {
            handle.abort();
        }
        if !self.handles.is_empty() {
            debug!(
                "TaskCleanupGuard: aborted {} background tasks",
                self.handles.len()
            );
        }
    }
}

/// gRPC client for communicating with NanoLink server
pub struct GrpcClient {
    client: NanoLinkServiceClient<Channel>,
    config: Arc<Config>,
    server_config: ServerConfig,
    permission_level: i32,
    /// Shared, mutable agent configuration used to persist server-pushed
    /// config_update values to disk.
    shared_config: Arc<RwLock<Config>>,
    /// Path to the on-disk config file (for persisting config_update).
    config_path: PathBuf,
    /// Sender used to trigger an immediate reconnect so a persisted
    /// config_update is picked up by rebuilding the stream from fresh config.
    signal_tx: broadcast::Sender<ConnectionSignal>,
}

impl GrpcClient {
    /// Connect to a gRPC server
    pub async fn connect(
        server_config: &ServerConfig,
        config: &Arc<Config>,
        shared_config: Arc<RwLock<Config>>,
        config_path: PathBuf,
        signal_tx: broadcast::Sender<ConnectionSignal>,
    ) -> Result<Self> {
        let url = server_config.get_grpc_url();

        let mut endpoint = Endpoint::from_shared(url.clone())
            .context("Invalid server URL")?
            // Note: Don't set .timeout() here - it kills streaming RPCs
            // Use connect_timeout for connection establishment instead
            // Keep this SHORT to detect failures quickly and allow fast reconnection
            .connect_timeout(Duration::from_secs(15))
            // TCP keepalive - OS level (aggressive for NAT/firewall environments)
            .tcp_keepalive(Some(Duration::from_secs(20)))
            // HTTP/2 keepalive - gRPC level (must match server settings)
            // Server: keepAliveTime=30s, keepAliveTimeout=10s
            .http2_keep_alive_interval(Duration::from_secs(20))
            .keep_alive_timeout(Duration::from_secs(10))
            .keep_alive_while_idle(true);

        // Configure TLS if enabled
        if server_config.tls_enabled {
            let tls_config = ClientTlsConfig::new();
            endpoint = endpoint.tls_config(tls_config)?;
        }

        info!(
            "Connecting to gRPC server: {} with HTTP/2 keepalive enabled",
            url
        );

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
            shared_config,
            config_path,
            signal_tx,
        })
    }

    /// Persist a server-pushed config_update into the on-disk config and trigger
    /// an immediate reconnect so the stream is rebuilt from the fresh config
    /// (re-creating the tokio interval tickers with the new intervals).
    ///
    /// Field mapping (proto `ServerConfig` -> [`Config`]):
    /// - `metrics_interval_ms`     -> `collector.realtime_interval_ms` + `collector.cpu_interval_ms`
    /// - `heartbeat_interval_ms`   -> `agent.heartbeat_interval` (ms -> s, min 1s)
    /// - `enable_detailed_metrics` -> `collector.enable_per_core_cpu`
    /// - `enabled_collectors`      -> no Config equivalent, skipped
    async fn apply_config_update(&self, new_cfg: &crate::proto::ServerConfig) {
        {
            let mut cfg = self.shared_config.write().await;

            if new_cfg.metrics_interval_ms > 0 {
                cfg.collector.realtime_interval_ms = new_cfg.metrics_interval_ms;
                cfg.collector.cpu_interval_ms = new_cfg.metrics_interval_ms;
            }
            if new_cfg.heartbeat_interval_ms > 0 {
                // Config stores heartbeat in whole seconds.
                cfg.agent.heartbeat_interval = (new_cfg.heartbeat_interval_ms / 1000).max(1);
            }
            cfg.collector.enable_per_core_cpu = new_cfg.enable_detailed_metrics;

            if let Err(e) = cfg.save(&self.config_path) {
                error!(
                    "Failed to persist config_update to {:?}: {}",
                    self.config_path, e
                );
                return;
            }
        }

        info!(
            "config_update persisted to {:?} (metrics_interval_ms={}, heartbeat_interval_ms={}, \
             enable_detailed_metrics={}); enabled_collectors={:?} has no Config field and was skipped. \
             Triggering immediate reconnect to apply.",
            self.config_path,
            new_cfg.metrics_interval_ms,
            new_cfg.heartbeat_interval_ms,
            new_cfg.enable_detailed_metrics,
            new_cfg.enabled_collectors,
        );

        if let Err(e) = self.signal_tx.send(ConnectionSignal::ImmediateReconnect) {
            warn!(
                "Failed to send ImmediateReconnect after config_update: {}",
                e
            );
        }
    }

    fn with_agent_auth<T>(&self, mut request: Request<T>) -> Result<Request<T>> {
        let resolved_token = self
            .server_config
            .resolve_token()
            .map_err(|e| anyhow::anyhow!("Token resolution failed: {e}"))?;
        let auth_value = format!("Bearer {resolved_token}");
        let metadata_value = MetadataValue::try_from(auth_value.as_str())
            .context("Invalid agent authentication metadata")?;
        request
            .metadata_mut()
            .insert("authorization", metadata_value);
        Ok(request)
    }

    /// Authenticate with the server
    pub async fn authenticate(&mut self) -> Result<AuthResponse> {
        // Resolve token (supports environment variables and file references)
        let resolved_token = self
            .server_config
            .resolve_token()
            .map_err(|e| anyhow::anyhow!("Token resolution failed: {e}"))?;

        let request = Request::new(AuthRequest {
            token: resolved_token,
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
    pub async fn stream_metrics<F, Fut>(
        &mut self,
        buffer: Arc<RingBuffer>,
        command_handler: F,
    ) -> Result<()>
    where
        F: Fn(Command) -> Fut + Send + Sync + 'static,
        Fut: std::future::Future<Output = CommandResult> + Send,
    {
        // Create channel for sending requests
        let (tx, rx) = mpsc::channel::<MetricsStreamRequest>(100);
        let request_stream = ReceiverStream::new(rx);

        // Start the bidirectional stream
        let request = self.with_agent_auth(Request::new(request_stream))?;
        let response = self
            .client
            .stream_metrics(request)
            .await
            .context("Failed to start metrics stream")?;

        let mut response_stream: Streaming<MetricsStreamResponse> = response.into_inner();

        // Spawn task to send metrics with cleanup guard
        let tx_clone = tx.clone();
        let config = self.config.clone();
        let buffer_clone = buffer.clone();

        // Use cleanup guard to ensure task is aborted on any exit (including ? early returns)
        let mut cleanup_guard = TaskCleanupGuard::new();

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
                            uptime_seconds: agent_uptime_seconds(),
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
        cleanup_guard.add(sender_handle);

        // Handle responses from server
        // Note: cleanup_guard will abort tasks when dropped (including on ? early return)
        while let Some(response) = response_stream.message().await? {
            match response.response {
                Some(metrics_stream_response::Response::Command(cmd)) => {
                    info!("Received command: {:?}", cmd.r#type);
                    let result = command_handler(cmd).await;

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
                Some(metrics_stream_response::Response::ConfigUpdate(new_cfg)) => {
                    info!(
                        "Received config_update from server: metrics_interval_ms={}, \
                         heartbeat_interval_ms={}, enable_detailed_metrics={}, enabled_collectors={:?}",
                        new_cfg.metrics_interval_ms,
                        new_cfg.heartbeat_interval_ms,
                        new_cfg.enable_detailed_metrics,
                        new_cfg.enabled_collectors,
                    );
                    // Persist the new config and trigger an immediate reconnect so
                    // the stream is rebuilt from fresh config. The reconnect tears
                    // down this loop (the signal also breaks us out via the
                    // returning stream), so apply before returning.
                    self.apply_config_update(&new_cfg).await;
                    break;
                }
                Some(metrics_stream_response::Response::DataRequest(req)) => {
                    info!("Received data request: {:?}", req.request_type);
                    // In legacy stream_metrics, we don't have layered support
                    // Just log the request for now
                }
                None => {}
            }
        }

        // cleanup_guard is dropped here and aborts the task
        Ok(())
    }

    /// Report metrics using unary RPC (simpler, but less efficient)
    #[allow(dead_code)]
    pub async fn report_metrics(&mut self, metrics: Metrics) -> Result<()> {
        let request = self.with_agent_auth(Request::new(metrics))?;
        let response = self
            .client
            .report_metrics(request)
            .await
            .context("Failed to report metrics")?;

        let ack = response.into_inner();
        if !ack.success {
            warn!("Metrics report was not acknowledged");
        }

        Ok(())
    }

    /// Execute a command (used for testing or direct command execution)
    #[allow(dead_code)]
    pub async fn execute_command(&mut self, command: Command) -> Result<CommandResult> {
        let request = self.with_agent_auth(Request::new(command))?;
        let response = self
            .client
            .execute_command(request)
            .await
            .context("Failed to execute command")?;

        Ok(response.into_inner())
    }

    /// Test connection to a server without full authentication
    ///
    /// This method attempts to connect and authenticate with the server,
    /// returning the server version if successful.
    /// Now also takes the locally configured permission level to show comparison.
    pub async fn test_server_connection(
        server_config: &ServerConfig,
        configured_permission: u8,
    ) -> Result<String> {
        let url = server_config.get_grpc_url();

        let mut endpoint = Endpoint::from_shared(url.clone())
            .context("Invalid server URL")?
            .connect_timeout(Duration::from_secs(10))
            .tcp_keepalive(Some(Duration::from_secs(20)));

        // Configure TLS if enabled
        if server_config.tls_enabled {
            let tls_config = ClientTlsConfig::new();
            endpoint = endpoint.tls_config(tls_config)?;
        }

        let channel = endpoint
            .connect()
            .await
            .context("Failed to connect to server")?;

        let mut client = NanoLinkServiceClient::new(channel);

        // Resolve token and authenticate
        let resolved_token = server_config
            .resolve_token()
            .map_err(|e| anyhow::anyhow!("Token resolution failed: {e}"))?;

        let request = Request::new(AuthRequest {
            token: resolved_token,
            hostname: hostname::get()
                .map(|h| h.to_string_lossy().to_string())
                .unwrap_or_else(|_| "unknown".to_string()),
            agent_version: env!("CARGO_PKG_VERSION").to_string(),
            os: std::env::consts::OS.to_string(),
            arch: std::env::consts::ARCH.to_string(),
        });

        let response = client
            .authenticate(request)
            .await
            .context("Authentication failed")?;

        let auth_response = response.into_inner();

        if auth_response.success {
            // Show configured permission vs server-granted permission
            Ok(format!(
                "Configured: {}, Server: {}",
                configured_permission, auth_response.permission_level
            ))
        } else {
            Err(anyhow::anyhow!(
                "Authentication failed: {}",
                auth_response.error_message
            ))
        }
    }

    /// Start bidirectional streaming with layered metrics support
    ///
    /// This method uses the LayeredCollector to send different types of metrics
    /// at different intervals (realtime, periodic, static).
    pub async fn stream_layered_metrics<F, Fut>(&mut self, command_handler: F) -> Result<()>
    where
        F: Fn(Command) -> Fut + Send + Sync + 'static,
        Fut: std::future::Future<Output = CommandResult> + Send,
    {
        // Create channel for sending requests
        let (tx, rx) = mpsc::channel::<MetricsStreamRequest>(100);
        let request_stream = ReceiverStream::new(rx);

        // Queue AgentInit as the FIRST message BEFORE opening the stream. The
        // server blocks on Recv() for the first message before sending any
        // response headers, so awaiting the stream open with an empty request
        // stream would deadlock (server waits for our message, we wait for the
        // server's headers). The bounded channel buffers it until tonic starts
        // draining the request stream.
        let agent_init = AgentInit {
            agent_id: self.config.agent.agent_id.clone().unwrap_or_default(),
            hostname: self.config.get_hostname(),
            os: std::env::consts::OS.to_string(),
            arch: std::env::consts::ARCH.to_string(),
            agent_version: env!("CARGO_PKG_VERSION").to_string(),
        };
        info!("Sending AgentInit with agent_id: {}", agent_init.agent_id);
        tx.send(MetricsStreamRequest {
            request: Some(metrics_stream_request::Request::AgentInit(agent_init)),
        })
        .await
        .context("Failed to send AgentInit")?;

        // Start the bidirectional stream
        let request = self.with_agent_auth(Request::new(request_stream))?;
        let response = self
            .client
            .stream_metrics(request)
            .await
            .context("Failed to start metrics stream")?;

        let mut response_stream: Streaming<MetricsStreamResponse> = response.into_inner();

        // Create layered collector with cleanup guard
        let (metrics_tx, mut metrics_rx) = mpsc::channel::<LayeredMetricsMessage>(100);
        let (request_tx, request_rx) = mpsc::channel::<DataRequest>(10);

        let config = self.config.clone();
        let collector = LayeredCollector::new(config.clone());

        // Use cleanup guard to ensure tasks are aborted on any exit (including ? early returns)
        let mut cleanup_guard = TaskCleanupGuard::new();

        // Spawn the layered collector
        let collector_handle = tokio::spawn(async move {
            collector.run(metrics_tx, request_rx).await;
        });
        cleanup_guard.add(collector_handle);

        // Spawn task to forward layered messages to gRPC stream
        let tx_clone = tx.clone();
        let heartbeat_interval = self.config.agent.heartbeat_interval;

        let sender_handle = tokio::spawn(async move {
            let mut heartbeat_ticker = time::interval(Duration::from_secs(heartbeat_interval));

            loop {
                tokio::select! {
                    Some(msg) = metrics_rx.recv() => {
                        let request = match msg {
                            LayeredMetricsMessage::Static(static_info) => {
                                debug!("Sending static info");
                                MetricsStreamRequest {
                                    request: Some(metrics_stream_request::Request::StaticInfo(static_info)),
                                }
                            }
                            LayeredMetricsMessage::Realtime(realtime) => {
                                MetricsStreamRequest {
                                    request: Some(metrics_stream_request::Request::Realtime(realtime)),
                                }
                            }
                            LayeredMetricsMessage::Periodic(periodic) => {
                                debug!("Sending periodic data");
                                MetricsStreamRequest {
                                    request: Some(metrics_stream_request::Request::Periodic(periodic)),
                                }
                            }
                            LayeredMetricsMessage::Full(metrics) => {
                                debug!("Sending full metrics (initial={})", metrics.is_initial);
                                MetricsStreamRequest {
                                    request: Some(metrics_stream_request::Request::Metrics(metrics)),
                                }
                            }
                        };

                        if tx_clone.send(request).await.is_err() {
                            error!("Failed to send to gRPC stream");
                            break;
                        }
                    }
                    _ = heartbeat_ticker.tick() => {
                        let heartbeat = Heartbeat {
                            timestamp: chrono::Utc::now().timestamp_millis() as u64,
                            uptime_seconds: agent_uptime_seconds(),
                        };
                        let request = MetricsStreamRequest {
                            request: Some(metrics_stream_request::Request::Heartbeat(heartbeat)),
                        };
                        if tx_clone.send(request).await.is_err() {
                            error!("Failed to send heartbeat");
                            break;
                        }
                    }
                }
            }
        });
        cleanup_guard.add(sender_handle);

        // Handle responses from server
        // Note: cleanup_guard will abort tasks when dropped (including on ? early return)
        while let Some(response) = response_stream.message().await? {
            match response.response {
                Some(metrics_stream_response::Response::Command(cmd)) => {
                    info!("Received command: {:?}", cmd.r#type);
                    let result = command_handler(cmd).await;

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
                Some(metrics_stream_response::Response::ConfigUpdate(new_cfg)) => {
                    info!(
                        "Received config_update from server: metrics_interval_ms={}, \
                         heartbeat_interval_ms={}, enable_detailed_metrics={}, enabled_collectors={:?}",
                        new_cfg.metrics_interval_ms,
                        new_cfg.heartbeat_interval_ms,
                        new_cfg.enable_detailed_metrics,
                        new_cfg.enabled_collectors,
                    );
                    // Persist the new config and trigger an immediate reconnect so
                    // the layered collector / tickers are rebuilt from fresh config.
                    self.apply_config_update(&new_cfg).await;
                    break;
                }
                Some(metrics_stream_response::Response::DataRequest(data_req)) => {
                    info!("Received data request: {:?}", data_req.request_type);
                    // Forward the request to the layered collector
                    let request_type = DataRequestType::try_from(data_req.request_type)
                        .unwrap_or(DataRequestType::DataRequestFull);
                    let _ = request_tx.send(DataRequest::from(request_type)).await;
                }
                None => {}
            }
        }

        // cleanup_guard is dropped here and aborts both tasks
        debug!("Layered metrics stream ended, cleanup guard will abort tasks");
        Ok(())
    }
}
