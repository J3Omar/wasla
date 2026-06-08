import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../../core/router/app_router.dart';
import '../../call/presentation/incoming_call_screen.dart';

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
        if (response.payload == null || response.payload!.isEmpty) return;

        try {
          final data = jsonDecode(response.payload!);
          if (data is Map<String, dynamic>) {
            if (data['type'] == 'call') {
              // Synchronous guard — relies on screen lifecycle, not router state
              if (IncomingCallScreen.isActive) {
                debugPrint('IncomingCallScreen already active, ignoring tap.');
                return;
              }
              appRouter.push('/call/incoming', extra: data);
            } else if (data['type'] == 'chat') {
              appRouter.go('/home');
            }
          }
        } catch (e) {
          // Fallback for old payloads
          if (response.payload!.startsWith('chat:')) {
            appRouter.go('/home');
          }
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
      'wasla_messages_v2',
      'Messages',
      channelDescription: 'New chat messages from LAN devices',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('notification'),
      audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
      autoCancel: true,
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

  // ── Voice Call Notifications ───────────────────────────────────────────────

  static const _kCallNotifId = 99999;

  /// Show a heads-up (or full-screen on Android) notification for an incoming
  /// voice call. Used when the app is in background/killed so the user still
  /// sees the call. Reuses the [flutter_local_notifications] plugin already
  /// initialized in [initialize()].
  Future<void> showCallNotification({
    required String callerName,
    required String callerId,
    required String callerIp,
    required int signalingPort,
  }) async {
    if (!_initialized) return;

    const androidDetails = AndroidNotificationDetails(
      'wasla_calls_v2',
      'Voice Calls',
      channelDescription: 'Incoming voice calls from LAN devices',
      importance: Importance.max,
      priority: Priority.max,
      // fullScreenIntent shows the incoming-call UI even on lock screen
      fullScreenIntent: true,
      showWhen: false,
      enableVibration: true,
      playSound: false, // Mute system notification to avoid double-audio
      autoCancel: false,
      ongoing: true, // stays visible until explicitly cancelled
      category: AndroidNotificationCategory.call,
    );

    const linuxDetails = LinuxNotificationDetails(
      urgency: LinuxNotificationUrgency.critical,
    );

    const details = NotificationDetails(
      android: androidDetails,
      linux: linuxDetails,
    );

    final payloadMap = {
      'type': 'call',
      'callerId': callerId,
      'callerName': callerName,
      'callerIp': callerIp,
      'signalingPort': signalingPort,
    };

    await _plugin.show(
      _kCallNotifId,
      '📞 Incoming call',
      '$callerName is calling…',
      details,
      payload: jsonEncode(payloadMap),
    );
  }

  /// Dismiss the incoming call notification (when accepted or declined).
  Future<void> cancelCallNotification() async {
    if (!_initialized) return;
    await _plugin.cancel(_kCallNotifId);
  }

  Future<void> updateToOngoingCall({required String peerName}) async {
    if (!_initialized) return;
    const androidDetails = AndroidNotificationDetails(
      'wasla_calls_v2',
      'Voice Calls',
      ongoing: true,
      playSound: false,
      autoCancel: false,
      importance:
          Importance.low, // Lower importance so it stays quiet in status bar
    );
    await _plugin.show(
      _kCallNotifId,
      'Ongoing Call',
      'Talking to $peerName',
      const NotificationDetails(android: androidDetails),
    );
  }
}
