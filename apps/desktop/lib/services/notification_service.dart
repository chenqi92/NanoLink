import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Thin wrapper over flutter_local_notifications for foreground alert pushes.
///
/// Only Android / iOS / macOS are supported; on other platforms (web, Windows)
/// every call is a guarded no-op so the rest of the app stays unaffected.
class NotificationService {
  static const _channelId = 'nanolink_alerts';
  static const _channelName = 'NanoOps 告警';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  Future<void> init() async {
    if (!_supported || _ready) return;
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwin = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: android,
          iOS: darwin,
          macOS: darwin,
        ),
      );

      // Android 13+ runtime permission + channel.
      final android13 = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android13?.requestNotificationsPermission();
      await android13?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          importance: Importance.high,
        ),
      );
      _ready = true;
    } catch (e) {
      debugPrint('[Notify] init failed: $e');
    }
  }

  /// Show a notification. [key] gives a stable id so re-firing the same alert
  /// replaces its banner instead of stacking duplicates.
  Future<void> show(String key, String title, String body) async {
    if (!_supported || !_ready) return;
    try {
      await _plugin.show(
        id: key.hashCode & 0x7fffffff,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
          macOS: DarwinNotificationDetails(),
        ),
      );
    } catch (e) {
      debugPrint('[Notify] show failed: $e');
    }
  }
}
