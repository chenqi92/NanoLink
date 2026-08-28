import Foundation

/// Lightweight formatting helpers for byte sizes and transfer rates.
/// Ports `format.dart` (binary units: KiB/MiB/GiB/TiB).
enum Fmt {
    private static let kib = 1024.0
    private static let mib = 1024.0 * 1024.0
    private static let gib = 1024.0 * 1024.0 * 1024.0
    private static let tib = 1024.0 * 1024.0 * 1024.0 * 1024.0

    private static func fixed(_ v: Double, _ digits: Int) -> String {
        String(format: "%.\(digits)f", v)
    }

    /// Bytes → GiB (numeric).
    static func gib(_ bytes: Double) -> Double { bytes / gib }

    /// Human byte size, e.g. "3.4 TiB", "612 GiB", "512 MiB".
    static func bytes(_ b: Double) -> String {
        if b >= tib { return "\(fixed(b / tib, b / tib >= 10 ? 0 : 1)) TiB" }
        if b >= gib { return "\(fixed(b / gib, b / gib >= 10 ? 0 : 1)) GiB" }
        if b >= mib { return "\(fixed(b / mib, 0)) MiB" }
        if b >= kib { return "\(fixed(b / kib, 0)) KiB" }
        return "\(fixed(b, 0)) B"
    }

    /// Transfer rate from bytes/second.
    static func rate(_ bytesPerSec: Double) -> String {
        let b = bytesPerSec
        if b >= gib { return "\(fixed(b / gib, 1)) GB/s" }
        if b >= mib { return "\(fixed(b / mib, 1)) MB/s" }
        if b >= kib { return "\(fixed(b / kib, 0)) KB/s" }
        return "\(fixed(b, 0)) B/s"
    }

    /// Rate expressed in MB/s (numeric).
    static func mbps(_ bytesPerSec: Double) -> Double { bytesPerSec / mib }

    /// Compact uptime from seconds, e.g. "47d 14h".
    static func uptime(_ seconds: Int) -> String {
        if seconds <= 0 { return "—" }
        let d = seconds / 86400
        let h = (seconds % 86400) / 3600
        let m = (seconds % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    /// Relative time from a timestamp, e.g. "5s", "3m", "2h", "4d".
    static func ago(_ t: Date) -> String {
        let s = Int(Date().timeIntervalSince(t))
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        if s < 86400 { return "\(s / 3600)h" }
        return "\(s / 86400)d"
    }
}
