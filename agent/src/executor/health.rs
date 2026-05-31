use std::collections::HashMap;
use std::net::{TcpStream, ToSocketAddrs};
use std::time::{Duration, Instant};
use tracing::info;

use crate::proto::{CommandResult, HealthCheckItem, HealthCheckResult};

/// Connectivity / health probe executor.
pub struct HealthExecutor;

impl HealthExecutor {
    pub fn new() -> Self {
        Self
    }

    /// Perform a TCP connectivity probe to `target` and report latency.
    /// `target` accepts "host:port", "http(s)://host[:port]" or a bare host.
    pub async fn connectivity_test(&self, target: &str, params: &HashMap<String, String>) -> CommandResult {
        let timeout_ms: u64 = params.get("timeoutMs").and_then(|s| s.parse().ok()).unwrap_or(3000);
        let (host, port) = parse_target(target);
        info!("[AUDIT] ConnectivityTest: {host}:{port}");

        let start = Instant::now();
        let outcome = connect(&host, port, Duration::from_millis(timeout_ms));
        let duration_ms = start.elapsed().as_millis() as i64;
        let (passed, message) = match outcome {
            Ok(()) => (true, format!("Connected to {host}:{port}")),
            Err(e) => (false, e.to_string()),
        };

        let item = HealthCheckItem {
            name: target.to_string(),
            passed,
            message,
            duration_ms,
            details: HashMap::new(),
        };
        CommandResult {
            command_id: String::new(),
            success: true,
            output: String::new(),
            error: String::new(),
            health_result: Some(HealthCheckResult {
                healthy: passed,
                checks: vec![item],
            }),
            ..Default::default()
        }
    }
}

impl Default for HealthExecutor {
    fn default() -> Self {
        Self::new()
    }
}

fn parse_target(target: &str) -> (String, u16) {
    let t = target.trim();
    if let Some(rest) = t.strip_prefix("https://") {
        return split_host_port(rest.split('/').next().unwrap_or(rest), 443);
    }
    if let Some(rest) = t.strip_prefix("http://") {
        return split_host_port(rest.split('/').next().unwrap_or(rest), 80);
    }
    split_host_port(t, 80)
}

fn split_host_port(s: &str, default_port: u16) -> (String, u16) {
    if let Some((h, p)) = s.rsplit_once(':') {
        if let Ok(port) = p.parse::<u16>() {
            return (h.to_string(), port);
        }
    }
    (s.to_string(), default_port)
}

fn connect(host: &str, port: u16, timeout: Duration) -> std::io::Result<()> {
    let mut addrs = format!("{host}:{port}").to_socket_addrs()?;
    let addr = addrs
        .next()
        .ok_or_else(|| std::io::Error::new(std::io::ErrorKind::NotFound, "DNS resolution failed"))?;
    TcpStream::connect_timeout(&addr, timeout)?;
    Ok(())
}
