use parking_lot::RwLock;
use std::collections::VecDeque;
use std::sync::atomic::{AtomicU64, Ordering};

use crate::proto::Metrics;

/// Thread-safe Ring Buffer for caching metrics data
///
/// This buffer stores the most recent N metrics for offline caching.
/// When the network is disconnected, data continues to be collected
/// and stored in this buffer. Upon reconnection, buffered data can
/// be synced to the server.
pub struct RingBuffer {
    /// Each entry carries a monotonic sequence number so sync tracking does not
    /// collide when several metrics share the same millisecond timestamp.
    buffer: RwLock<VecDeque<(u64, Metrics)>>,
    capacity: usize,
    /// Sequence number assigned to the next pushed entry
    next_seq: AtomicU64,
    /// Sequence watermark of the last successfully synced metrics
    last_sync_seq: AtomicU64,
}

#[allow(dead_code)]
impl RingBuffer {
    /// Create a new ring buffer with specified capacity
    pub fn new(capacity: usize) -> Self {
        Self {
            buffer: RwLock::new(VecDeque::with_capacity(capacity)),
            capacity,
            next_seq: AtomicU64::new(1),
            last_sync_seq: AtomicU64::new(0),
        }
    }

    /// Push a new metrics entry into the buffer
    /// If the buffer is full, the oldest entry will be removed
    pub fn push(&self, metrics: Metrics) {
        let seq = self.next_seq.fetch_add(1, Ordering::Relaxed);
        let mut buffer = self.buffer.write();
        if buffer.len() >= self.capacity {
            buffer.pop_front();
        }
        buffer.push_back((seq, metrics));
    }

    /// Get the latest metrics entry
    pub fn latest(&self) -> Option<Metrics> {
        self.buffer.read().back().map(|(_, m)| m.clone())
    }

    /// Get all metrics since the given timestamp
    pub fn get_since(&self, timestamp: u64) -> Vec<Metrics> {
        self.buffer
            .read()
            .iter()
            .filter(|(_, m)| m.timestamp > timestamp)
            .map(|(_, m)| m.clone())
            .collect()
    }

    /// Get all buffered metrics
    pub fn get_all(&self) -> Vec<Metrics> {
        self.buffer.read().iter().map(|(_, m)| m.clone()).collect()
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
        self.buffer.read().front().map(|(_, m)| m.timestamp)
    }

    /// Get the newest timestamp in the buffer
    pub fn newest_timestamp(&self) -> Option<u64> {
        self.buffer.read().back().map(|(_, m)| m.timestamp)
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

    /// Get the timestamp at the current sync watermark (for status reporting)
    pub fn get_last_sync_timestamp(&self) -> u64 {
        let last_sync_seq = self.last_sync_seq.load(Ordering::Relaxed);
        self.buffer
            .read()
            .iter()
            .filter(|(seq, _)| *seq <= last_sync_seq)
            .map(|(_, m)| m.timestamp)
            .next_back()
            .unwrap_or(0)
    }

    /// Advance the sync watermark to cover every entry whose timestamp is <= the
    /// given timestamp. Sequence numbers (not raw timestamps) drive the watermark so
    /// metrics sharing a millisecond are never dropped on a partial resync.
    pub fn set_last_sync_timestamp(&self, timestamp: u64) {
        let seq = self
            .buffer
            .read()
            .iter()
            .filter(|(_, m)| m.timestamp <= timestamp)
            .map(|(seq, _)| *seq)
            .next_back();
        if let Some(seq) = seq {
            // Only ever move the watermark forward.
            self.last_sync_seq.fetch_max(seq, Ordering::Relaxed);
        }
    }

    /// Get all unsynced metrics (entries with sequence > last synced sequence)
    pub fn get_unsynced(&self) -> Vec<Metrics> {
        let last_sync_seq = self.last_sync_seq.load(Ordering::Relaxed);
        self.buffer
            .read()
            .iter()
            .filter(|(seq, _)| *seq > last_sync_seq)
            .map(|(_, m)| m.clone())
            .collect()
    }

    /// Get unsynced metrics count
    pub fn unsynced_count(&self) -> usize {
        let last_sync_seq = self.last_sync_seq.load(Ordering::Relaxed);
        self.buffer
            .read()
            .iter()
            .filter(|(seq, _)| *seq > last_sync_seq)
            .count()
    }

    /// Mark all current data as synced (advance watermark to the newest sequence)
    pub fn mark_all_synced(&self) {
        if let Some((seq, _)) = self.buffer.read().back() {
            self.last_sync_seq.fetch_max(*seq, Ordering::Relaxed);
        }
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

    #[test]
    fn test_unsynced_no_collision_on_same_timestamp() {
        // Two metrics sharing a millisecond must both be tracked independently.
        let buffer = RingBuffer::new(5);
        buffer.push(create_test_metrics(100));
        buffer.push(create_test_metrics(100));
        buffer.push(create_test_metrics(100));

        assert_eq!(buffer.unsynced_count(), 3);
        assert_eq!(buffer.get_unsynced().len(), 3);

        // Marking timestamp 100 as synced advances the sequence watermark to the
        // newest entry sharing that timestamp; none are dropped before that point.
        buffer.set_last_sync_timestamp(100);
        assert_eq!(buffer.unsynced_count(), 0);

        // A new same-timestamp entry pushed afterwards is still detected as unsynced.
        buffer.push(create_test_metrics(100));
        assert_eq!(buffer.unsynced_count(), 1);
    }
}
