use parking_lot::RwLock;
use std::collections::VecDeque;

use crate::proto::Metrics;

/// Thread-safe Ring Buffer for caching metrics data
///
/// This buffer stores the most recent N metrics for offline caching.
/// When the network is disconnected, data continues to be collected
/// and stored in this buffer. Upon reconnection, buffered data can
/// be synced to the server.
pub struct RingBuffer {
    buffer: RwLock<VecDeque<Metrics>>,
    capacity: usize,
}

#[allow(dead_code)]
impl RingBuffer {
    /// Create a new ring buffer with specified capacity
    pub fn new(capacity: usize) -> Self {
        Self {
            buffer: RwLock::new(VecDeque::with_capacity(capacity)),
            capacity,
        }
    }

    /// Push a new metrics entry into the buffer
    /// If the buffer is full, the oldest entry will be removed
    pub fn push(&self, metrics: Metrics) {
        let mut buffer = self.buffer.write();
        if buffer.len() >= self.capacity {
            buffer.pop_front();
        }
        buffer.push_back(metrics);
    }

    /// Get the latest metrics entry
    pub fn latest(&self) -> Option<Metrics> {
        self.buffer.read().back().cloned()
    }

    /// Get all metrics since the given timestamp
    pub fn get_since(&self, timestamp: u64) -> Vec<Metrics> {
        self.buffer
            .read()
            .iter()
            .filter(|m| m.timestamp > timestamp)
            .cloned()
            .collect()
    }

    /// Get all buffered metrics
    pub fn get_all(&self) -> Vec<Metrics> {
        self.buffer.read().iter().cloned().collect()
    }

    /// Get the number of items in the buffer
    pub fn len(&self) -> usize {
        self.buffer.read().len()
    }

    /// Check if the buffer is empty
    pub fn is_empty(&self) -> bool {
        self.buffer.read().is_empty()
    }

    /// Clear all buffered data
    pub fn clear(&self) {
        self.buffer.write().clear();
    }

    /// Get the oldest timestamp in the buffer
    pub fn oldest_timestamp(&self) -> Option<u64> {
        self.buffer.read().front().map(|m| m.timestamp)
    }

    /// Get the newest timestamp in the buffer
    pub fn newest_timestamp(&self) -> Option<u64> {
        self.buffer.read().back().map(|m| m.timestamp)
    }

    /// Get buffer capacity
    pub fn capacity(&self) -> usize {
        self.capacity
    }

    /// Get buffer usage as percentage
    pub fn usage_percent(&self) -> f64 {
        let len = self.buffer.read().len();
        (len as f64 / self.capacity as f64) * 100.0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn create_test_metrics(timestamp: u64) -> Metrics {
        Metrics {
            timestamp,
            cpu: None,
            memory: None,
            disks: vec![],
            networks: vec![],
            load_average: vec![],
            hostname: "test".to_string(),
            gpus: vec![],
            npus: vec![],
            system_info: None,
            is_initial: false,
            metrics_type: 0,
            user_sessions: vec![],
        }
    }

    #[test]
    fn test_ring_buffer_push_and_capacity() {
        let buffer = RingBuffer::new(3);

        buffer.push(create_test_metrics(1));
        buffer.push(create_test_metrics(2));
        buffer.push(create_test_metrics(3));

        assert_eq!(buffer.len(), 3);

        // Push one more, should evict oldest
        buffer.push(create_test_metrics(4));
        assert_eq!(buffer.len(), 3);

        // Oldest should be timestamp 2 now
        assert_eq!(buffer.oldest_timestamp(), Some(2));
        assert_eq!(buffer.newest_timestamp(), Some(4));
    }

    #[test]
    fn test_get_since() {
        let buffer = RingBuffer::new(5);

        for i in 1..=5 {
            buffer.push(create_test_metrics(i));
        }

        let since_3 = buffer.get_since(3);
        assert_eq!(since_3.len(), 2);
        assert_eq!(since_3[0].timestamp, 4);
        assert_eq!(since_3[1].timestamp, 5);
    }

    #[test]
    fn test_latest() {
        let buffer = RingBuffer::new(3);

        assert!(buffer.latest().is_none());

        buffer.push(create_test_metrics(1));
        buffer.push(create_test_metrics(2));

        assert_eq!(buffer.latest().unwrap().timestamp, 2);
    }
}
