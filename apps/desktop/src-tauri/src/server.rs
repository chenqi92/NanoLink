use futures_util::{SinkExt, StreamExt};
use tokio_tungstenite::{connect_async, tungstenite::Message};

pub async fn connect(url: &str, token: &str) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
    let ws_url = format!("{}?token={}", url, token);

    let (ws_stream, _) = connect_async(&ws_url).await?;
    let (mut write, mut read) = ws_stream.split();

    // Send auth message
    let auth_msg = serde_json::json!({
        "type": "auth",
        "timestamp": chrono_timestamp(),
        "payload": {
            "token": token,
            "clientType": "desktop"
        }
    });

    write.send(Message::Text(auth_msg.to_string())).await?;

    // Wait for response
    if let Some(msg) = read.next().await {
        match msg? {
            Message::Text(text) => {
                return Ok(text);
            }
            _ => {}
        }
    }

    Ok("Connected".to_string())
}

fn chrono_timestamp() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_millis() as u64
}
