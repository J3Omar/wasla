import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../data/call_manager.dart';
import '../domain/call_state.dart';
import '../../chat/data/chat_notification_service.dart';

const _kUuidKey = 'wasla_device_uuid';
const _kNameKey = 'wasla_device_name';

// ── Provider ─────────────────────────────────────────────────────────────────

final callProvider =
    AsyncNotifierProvider<CallNotifier, CallSession>(CallNotifier.new);

// ── Notifier ──────────────────────────────────────────────────────────────────

class CallNotifier extends AsyncNotifier<CallSession> {
  CallManager? _manager;
  RawDatagramSocket? _inviteSocket;

  String _selfUuid = '';
  String _selfName = '';

  // Fired when an incoming call invite arrives (before user accepts/declines)
  // Carries: {peerId, peerName, callerIp, signalingPort}
  Function(Map<String, dynamic>)? onIncomingCall;

  @override
  Future<CallSession> build() async {
    const storage = FlutterSecureStorage();
    _selfUuid = await storage.read(key: _kUuidKey) ?? '';
    _selfName = await storage.read(key: _kNameKey) ?? 'Wasla User';

    await _startInviteListener();

    ref.onDispose(() {
      _inviteSocket?.close();
      _manager?.dispose();
    });

    return CallSession.idle;
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Initiate an outgoing call to a peer.
  Future<void> startCall({
    required String peerId,
    required String peerName,
    required String peerIp,
  }) async {
    _manager?.dispose();
    _manager = CallManager(
      selfUuid: _selfUuid,
      selfName: _selfName,
      onStateChanged: (s) => state = AsyncData(s),
    );
    await _manager!.startCall(
        peerId: peerId, peerName: peerName, peerIp: peerIp);
  }

  /// Accept an incoming call after user taps "Accept".
  Future<void> acceptCall({
    required String callerIp,
    required int signalingPort,
    required String callerId,
    required String callerName,
  }) async {
    // Cancel the heads-up notification now that the user has responded
    await ChatNotificationService.instance.cancelCallNotification();
    _manager?.dispose();
    _manager = CallManager(
      selfUuid: _selfUuid,
      selfName: _selfName,
      onStateChanged: (s) => state = AsyncData(s),
    );
    // Pre-set session so screens show peer name immediately
    state = AsyncData(CallSession(
      state: CallState.connecting,
      peerId: callerId,
      peerName: callerName,
      peerIp: callerIp,
    ));
    await _manager!.acceptCall(
        callerIp: callerIp, signalingPort: signalingPort);
  }

  /// Decline an incoming call.
  Future<void> declineCall({
    required String callerIp,
    required int signalingPort,
  }) async {
    // Cancel the heads-up notification now that the user has responded
    await ChatNotificationService.instance.cancelCallNotification();
    _manager?.dispose();
    _manager = CallManager(
      selfUuid: _selfUuid,
      selfName: _selfName,
      onStateChanged: (s) => state = AsyncData(s),
    );
    await _manager!.declineCall(
        callerIp: callerIp, signalingPort: signalingPort);
    _manager = null;
    state = const AsyncData(CallSession.idle);
  }

  void toggleMute() => _manager?.toggleMute();
  void toggleSpeaker() => _manager?.toggleSpeaker();

  Future<void> endCall() async {
    await _manager?.endCall();
    _manager = null;
    state = const AsyncData(CallSession.idle);
  }

  // ── UDP invite listener ───────────────────────────────────────────────────

  Future<void> _startInviteListener() async {
    try {
      _inviteSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        kCallInviteUdpPort,
        reuseAddress: true,
      );
      _inviteSocket!.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = _inviteSocket!.receive();
        if (dg == null) return;
        try {
          final json =
              jsonDecode(utf8.decode(dg.data)) as Map<String, dynamic>;
          if (json['type'] == 'call_invite') {
            // Don't answer our own broadcasts
            if (json['from'] == _selfUuid) return;

            final peerId = json['from'] as String;
            final peerName = json['fromName'] as String? ?? 'Unknown';
            // Prefer the embedded callerIp (set via getBestLocalIpFor) over
            // UDP source address — critical for hotspot hosts
            final callerIp = (json['callerIp'] as String?)?.isNotEmpty == true
                ? json['callerIp'] as String
                : dg.address.address;
            final signalingPort = json['signalingPort'] as int;

            // Show system notification so the user sees the call even when
            // the app is in the background
            ChatNotificationService.instance.showCallNotification(
              callerName: peerName,
              callerId: peerId,
            );

            onIncomingCall?.call({
              'peerId': peerId,
              'peerName': peerName,
              'callerIp': callerIp,
              'signalingPort': signalingPort,
            });
          }
        } catch (_) {}
      });
    } catch (_) {
      // Port may already be bound — skip
    }
  }
}
