use anyhow::{Context, Result};
use futures_util::{SinkExt, StreamExt};
use prost::Message;
use std::sync::Arc;
use std::time::Duration;
use tokio::net::TcpStream;
use tokio::time::{self, Instant};
use tokio_tungstenite::{
    connect_async,
    tungstenite::{self, protocol::Message as WsMessage},
    MaybeTlsStream, WebSocketStream,
};
use tracing::{debug, error, info, warn};
use uuid::Uuid;

use crate::buffer::RingBuffer;
use crate::config::{Config, ServerConfig};
use crate::proto::{
    envelope::Payload, AuthRequest, AuthResponse, Envelope, Heartbeat, HeartbeatAck, Metrics,
    MetricsSync,
};

use super::handler::MessageHandler;

type WsStream = WebSocketStream<MaybeTlsStream<TcpStream>>;

/// WebSocket client for connecting to a server
pub struct WebSocketClient {
    stream: WsStream,
    server_config: ServerConfig,
    authenticated: bool,
    permission_level: i32,
    last_sync_timestamp: u64,
}

impl WebSocketClient {
    /// Connect to a WebSocket server
    pub async fn connect(server: &ServerConfig, config: &Config) -> Result<Self> {
        let (stream, _response) = connect_async(&server.url)
            .await
            .context("Failed to connect to WebSocket server")?;

        Ok(Self {
            stream,
            server_config: server.clone(),
            authenticated: false,
            permission_level: 0,
            last_sync_timestamp: 0,
        })
    }

    /// Run the WebSocket client
    pub async fn run(
        &mut self,
        handler: MessageHandler,
        config: &Config,
        buffer: &Arc<RingBuffer>,
    ) -> Result<()> {
        // Authenticate first
        self.authenticate(config).await?;

        // Sync buffered data if any
        self.sync_buffered_data(buffer).await?;

        // Start heartbeat and metrics sending
        let heartbeat_interval = Duration::from_secs(config.agent.heartbeat_interval);
        let metrics_interval = Duration::from_millis(config.collector.cpu_interval_ms);

        let mut heartbeat_ticker = time::interval(heartbeat_interval);
        let mut metrics_ticker = time::interval(metrics_interval);
        let mut last_heartbeat = Instant::now();

        loop {
            tokio::select! {
                // Handle incoming messages
                msg = self.stream.next() => {
                    match msg {
                        Some(Ok(WsMessage::Binary(data))) => {
                            if let Err(e) = self.handle_message(&data, &handler).await {
                                error!("Error handling message: {}", e);
                            }
                        }
                        Some(Ok(WsMessage::Ping(data))) => {
                            self.stream.send(WsMessage::Pong(data)).await?;
                        }
                        Some(Ok(WsMessage::Close(_))) => {
                            info!("Server closed connection");
                            break;
                        }
                        Some(Err(e)) => {
                            error!("WebSocket error: {}", e);
                            break;
                        }
                        None => {
                            info!("Connection closed");
                            break;
                        }
                        _ => {}
                    }
                }

                // Send heartbeat
                _ = heartbeat_ticker.tick() => {
                    if let Err(e) = self.send_heartbeat().await {
                        error!("Failed to send heartbeat: {}", e);
                        break;
                    }
                    last_heartbeat = Instant::now();
                }

                // Send metrics
                _ = metrics_ticker.tick() => {
                    if let Some(metrics) = buffer.latest() {
                        if let Err(e) = self.send_metrics(metrics).await {
                            error!("Failed to send metrics: {}", e);
                            // Don't break, metrics will be buffered
                        } else {
                            self.last_sync_timestamp = buffer.newest_timestamp().unwrap_or(0);
                        }
                    }
                }
            }

            // Check for heartbeat timeout
            if last_heartbeat.elapsed() > Duration::from_secs(config.agent.heartbeat_interval * 3) {
                warn!("Heartbeat timeout, reconnecting...");
                break;
            }
        }

        Ok(())
    }

    /// Authenticate with the server
    async fn authenticate(&mut self, config: &Config) -> Result<()> {
        let auth_request = AuthRequest {
            token: self.server_config.token.clone(),
            hostname: config.get_hostname(),
            agent_version: env!("CARGO_PKG_VERSION").to_string(),
            os: std::env::consts::OS.to_string(),
            arch: std::env::consts::ARCH.to_string(),
        };

        let envelope = Envelope {
            timestamp: Self::current_timestamp(),
            message_id: Uuid::new_v4().to_string(),
            payload: Some(Payload::AuthRequest(auth_request)),
        };

        self.send_envelope(&envelope).await?;

        // Wait for auth response
        let timeout = Duration::from_secs(10);
        let response = tokio::time::timeout(timeout, self.stream.next())
            .await
            .context("Authentication timeout")?;

        match response {
            Some(Ok(WsMessage::Binary(data))) => {
                let envelope = Envelope::decode(data.as_slice())?;
                if let Some(Payload::AuthResponse(auth_response)) = envelope.payload {
                    if auth_response.success {
                        self.authenticated = true;
                        self.permission_level = auth_response.permission_level;
                        info!(
                            "Authenticated successfully (permission level: {})",
                            self.permission_level
                        );
                        Ok(())
                    } else {
                        anyhow::bail!("Authentication failed: {}", auth_response.error_message);
                    }
                } else {
                    anyhow::bail!("Unexpected response during authentication");
                }
            }
            Some(Ok(_)) => anyhow::bail!("Unexpected message type during authentication"),
            Some(Err(e)) => anyhow::bail!("WebSocket error during authentication: {}", e),
            None => anyhow::bail!("Connection closed during authentication"),
        }
    }

    /// Sync buffered data after reconnection
    async fn sync_buffered_data(&mut self, buffer: &Arc<RingBuffer>) -> Result<()> {
        let buffered = buffer.get_since(self.last_sync_timestamp);
        if buffered.is_empty() {
            return Ok(());
        }

        info!("Syncing {} buffered metrics entries", buffered.len());

        let sync = MetricsSync {
            last_sync_timestamp: self.last_sync_timestamp,
            buffered_metrics: buffered,
        };

        let envelope = Envelope {
            timestamp: Self::current_timestamp(),
            message_id: Uuid::new_v4().to_string(),
            payload: Some(Payload::MetricsSync(sync)),
        };

        self.send_envelope(&envelope).await?;

        // Update last sync timestamp
        if let Some(ts) = buffer.newest_timestamp() {
            self.last_sync_timestamp = ts;
        }

        Ok(())
    }

    /// Send heartbeat
    async fn send_heartbeat(&mut self) -> Result<()> {
        let uptime = Self::get_uptime();

        let heartbeat = Heartbeat {
            timestamp: Self::current_timestamp(),
            uptime_seconds: uptime,
        };

        let envelope = Envelope {
            timestamp: Self::current_timestamp(),
            message_id: Uuid::new_v4().to_string(),
            payload: Some(Payload::Heartbeat(heartbeat)),
        };

        self.send_envelope(&envelope).await
    }

    /// Send metrics
    async fn send_metrics(&mut self, metrics: Metrics) -> Result<()> {
        let envelope = Envelope {
            timestamp: Self::current_timestamp(),
            message_id: Uuid::new_v4().to_string(),
            payload: Some(Payload::Metrics(metrics)),
        };

        self.send_envelope(&envelope).await
    }

    /// Handle incoming message
    async fn handle_message(&mut self, data: &[u8], handler: &MessageHandler) -> Result<()> {
        let envelope = Envelope::decode(data)?;

        match envelope.payload {
            Some(Payload::Command(command)) => {
                let result = handler.handle_command(command).await;
                let response = Envelope {
                    timestamp: Self::current_timestamp(),
                    message_id: Uuid::new_v4().to_string(),
                    payload: Some(Payload::CommandResult(result)),
                };
                self.send_envelope(&response).await?;
            }
            Some(Payload::HeartbeatAck(_)) => {
                debug!("Received heartbeat ack");
            }
            _ => {
                debug!("Received unknown message type");
            }
        }

        Ok(())
    }

    /// Send an envelope
    async fn send_envelope(&mut self, envelope: &Envelope) -> Result<()> {
        let data = envelope.encode_to_vec();
        self.stream.send(WsMessage::Binary(data)).await?;
        Ok(())
    }

    /// Get current timestamp in milliseconds
    fn current_timestamp() -> u64 {
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_millis() as u64
    }

    /// Get system uptime in seconds
    fn get_uptime() -> u64 {
        sysinfo::System::uptime()
    }
}
