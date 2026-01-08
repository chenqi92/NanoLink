//! Rate limiting middleware for Management API
//!
//! Implements per-endpoint and default rate limiting using token bucket algorithm.

use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::{Duration, Instant};

use axum::{
    Json,
    extract::{ConnectInfo, State},
    http::StatusCode,
    middleware::Next,
    response::Response,
};
use serde::Serialize;
use tokio::sync::RwLock;

use crate::config::RateLimitConfig;

/// State for rate limiting
pub struct RateLimitState {
    /// Rate limit configuration
    config: RateLimitConfig,
    /// Token buckets per IP:endpoint
    buckets: RwLock<HashMap<String, TokenBucket>>,
}

impl RateLimitState {
    pub fn new(config: RateLimitConfig) -> Self {
        Self {
            config,
            buckets: RwLock::new(HashMap::new()),
        }
    }
}

/// Token bucket for rate limiting
struct TokenBucket {
    tokens: f64,
    last_update: Instant,
    max_tokens: f64,
    refill_rate: f64, // tokens per second
}

impl TokenBucket {
    fn new(requests_per_minute: u32, burst: u32) -> Self {
        let refill_rate = requests_per_minute as f64 / 60.0;
        Self {
            tokens: burst as f64,
            last_update: Instant::now(),
            max_tokens: burst as f64,
            refill_rate,
        }
    }

    fn try_consume(&mut self) -> bool {
        let now = Instant::now();
        let elapsed = now.duration_since(self.last_update).as_secs_f64();

        // Refill tokens
        self.tokens = (self.tokens + elapsed * self.refill_rate).min(self.max_tokens);
        self.last_update = now;

        // Try to consume a token
        if self.tokens >= 1.0 {
            self.tokens -= 1.0;
            true
        } else {
            false
        }
    }

    fn time_until_available(&self) -> Duration {
        if self.tokens >= 1.0 {
            Duration::ZERO
        } else {
            let needed = 1.0 - self.tokens;
            Duration::from_secs_f64(needed / self.refill_rate)
        }
    }
}

#[derive(Debug, Serialize)]
pub struct RateLimitResponse {
    pub success: bool,
    pub message: String,
    pub retry_after_ms: Option<u64>,
}

/// Rate limiting middleware
pub async fn rate_limit_middleware(
    State(state): State<Arc<RateLimitState>>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    request: axum::extract::Request,
    next: Next,
) -> Result<Response, (StatusCode, Json<RateLimitResponse>)> {
    // Skip if rate limiting is disabled
    if !state.config.enabled {
        return Ok(next.run(request).await);
    }

    let path = request.uri().path().to_string();
    let source_ip = addr.ip();
    let bucket_key = format!("{source_ip}:{path}");

    // Get endpoint-specific or default rate limit
    let (requests_per_minute, burst) = state
        .config
        .endpoints
        .get(&path)
        .map(|e| (e.requests_per_minute, e.burst))
        .unwrap_or((state.config.requests_per_minute, state.config.burst));

    let mut buckets = state.buckets.write().await;

    let bucket = buckets
        .entry(bucket_key)
        .or_insert_with(|| TokenBucket::new(requests_per_minute, burst));

    if bucket.try_consume() {
        drop(buckets);
        Ok(next.run(request).await)
    } else {
        let retry_after = bucket.time_until_available();
        Err((
            StatusCode::TOO_MANY_REQUESTS,
            Json(RateLimitResponse {
                success: false,
                message: format!("Rate limit exceeded for {path}. Try again later."),
                retry_after_ms: Some(retry_after.as_millis() as u64),
            }),
        ))
    }
}

/// Cleanup old buckets periodically (call this from a background task)
pub async fn cleanup_old_buckets(state: Arc<RateLimitState>) {
    let mut interval = tokio::time::interval(Duration::from_secs(300)); // Every 5 minutes

    loop {
        interval.tick().await;

        let mut buckets = state.buckets.write().await;
        let now = Instant::now();

        // Remove buckets that haven't been used in 10 minutes
        buckets
            .retain(|_, bucket| now.duration_since(bucket.last_update) < Duration::from_secs(600));
    }
}
