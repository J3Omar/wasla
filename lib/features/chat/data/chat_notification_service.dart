import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Handles system notifications for incoming messages when the app is in background.
class ChatNotificationService {
  ChatNotificationService._();
  static final ChatNotificationService instance = ChatNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// Callback called when user taps a notification.
  /// Receives the peerId from the payload.
  Function(String peerId)? onNotificationTap;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const linuxSettings = LinuxInitializationSettings(
      defaultActionName: 'Open',
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      linux: linuxSettings,
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        final peerId = response.payload ?? '';
        if (peerId.isNotEmpty) {
          onNotificationTap?.call(peerId);
        }
      },
    );

    // Request Android notification permission (Android 13+)
    if (Platform.isAndroid) {
      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await androidPlugin?.requestNotificationsPermission();
    }
  }

  /// Show a heads-up notification for an incoming message.
  /// [peerId] is used as the notification ID (hashed) and payload for routing.
  Future<void> showMessageNotification({
    required String senderName,
    required String content,
    required String peerId,
  }) async {
    if (!_initialized) return;

    final notifId = peerId.hashCode.abs() % 100000;

    const androidDetails = AndroidNotificationDetails(
      'wasla_messages',
      'Messages',
      channelDescription: 'New chat messages from LAN devices',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      styleInformation: BigTextStyleInformation(''),
    );

    const linuxDetails = LinuxNotificationDetails(
      urgency: LinuxNotificationUrgency.normal,
    );

    const details = NotificationDetails(
      android: androidDetails,
      linux: linuxDetails,
    );

    await _plugin.show(notifId, senderName, content, details, payload: peerId);
  }

  /// Dismiss the notification for a specific peer (when chat is opened).
  Future<void> cancelNotification(String peerId) async {
    if (!_initialized) return;
    final notifId = peerId.hashCode.abs() % 100000;
    await _plugin.cancel(notifId);
  }

  /// Cancel all pending notifications.
  Future<void> cancelAll() async {
    if (!_initialized) return;
    await _plugin.cancelAll();
  }
}
