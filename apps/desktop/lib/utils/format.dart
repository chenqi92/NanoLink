/// Lightweight formatting helpers for byte sizes and transfer rates.
class Fmt {
  static const _kib = 1024.0;
  static const _mib = 1024.0 * 1024.0;
  static const _gib = 1024.0 * 1024.0 * 1024.0;
  static const _tib = 1024.0 * 1024.0 * 1024.0 * 1024.0;

  /// Bytes → GiB (numeric).
  static double gib(num bytes) => bytes / _gib;

  /// Human byte size, e.g. "3.4 TiB", "612 GiB", "512 MiB".
  static String bytes(num b) {
    if (b >= _tib) return '${(b / _tib).toStringAsFixed(b / _tib >= 10 ? 0 : 1)} TiB';
    if (b >= _gib) return '${(b / _gib).toStringAsFixed(b / _gib >= 10 ? 0 : 1)} GiB';
    if (b >= _mib) return '${(b / _mib).toStringAsFixed(0)} MiB';
    if (b >= _kib) return '${(b / _kib).toStringAsFixed(0)} KiB';
    return '${b.toStringAsFixed(0)} B';
  }

  /// Transfer rate from bytes/second.
  static String rate(num bytesPerSec) {
    final b = bytesPerSec;
    if (b >= _gib) return '${(b / _gib).toStringAsFixed(1)} GB/s';
    if (b >= _mib) return '${(b / _mib).toStringAsFixed(1)} MB/s';
    if (b >= _kib) return '${(b / _kib).toStringAsFixed(0)} KB/s';
    return '${b.toStringAsFixed(0)} B/s';
  }

  /// Rate expressed in MB/s (numeric, for chart series / compact rows).
  static double mbps(num bytesPerSec) => bytesPerSec / _mib;

  /// Compact uptime from seconds, e.g. "47d 14h".
  static String uptime(int seconds) {
    if (seconds <= 0) return '—';
    final d = seconds ~/ 86400;
    final h = (seconds % 86400) ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (d > 0) return '${d}d ${h}h';
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  /// "x秒/分钟/小时前" relative time from a timestamp.
  static String ago(DateTime t) {
    final s = DateTime.now().difference(t).inSeconds;
    if (s < 60) return '${s}s';
    if (s < 3600) return '${s ~/ 60}m';
    if (s < 86400) return '${s ~/ 3600}h';
    return '${s ~/ 86400}d';
  }
}
