import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';

import '../data/call_manager.dart';
import '../domain/call_state.dart';
import '../../chat/data/chat_notification_service.dart';
import '../data/call_audio_service.dart';
import '../../discovery/data/discovery_service.dart';
import '../../discovery/domain/device_model.dart';

const _kUuidKey = 'wasla_device_uuid';
const _kNameKey = 'wasla_device_name';

// ── Provider ─────────────────────────────────────────────────────────────────

final callProvider = AsyncNotifierProvider<CallNotifier, CallSession>(
  CallNotifier.new,
);

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
    final rawName = await storage.read(key: _kNameKey);
    _selfName = (rawName == null || rawName.trim().isEmpty) 
        ? 'Wasla User' 
        : rawName.trim();

    await _startInviteListener();

    ref.onDispose(() {
      _inviteSocket?.close();
      _manager?.dispose();
    });

    return CallSession.idle;
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Initiate an outgoing call to a peer.
  Future<bool> startCall({
    required String peerId,
    required String peerName,
    required String peerIp,
  }) async {
    final currentState = state.valueOrNull?.state ?? CallState.idle;
    if (currentState != CallState.idle && currentState != CallState.ended) {
      debugPrint(
        '[CallProvider] Cannot start a new call while in $currentState state.',
      );
      return false; // Prevent navigation
    }

    _manager?.dispose();
    // Bug 2: mark self as busy so peer devices stop showing us as available
    ref
        .read(discoveryServiceProvider.notifier)
        .updateLocalStatus(DeviceStatus.busy);
    _manager = CallManager(
      selfUuid: _selfUuid,
      selfName: _selfName,
      onStateChanged: (s) {
        state = AsyncData(s);
        if (s.state == CallState.active) {
          // Cancel our custom notification — flutter_background owns the ongoing foreground one
          ChatNotificationService.instance.cancelCallNotification();
          // Broadcast inCall so peers see we are on a call
          ref
              .read(discoveryServiceProvider.notifier)
              .updateLocalStatus(DeviceStatus.inCall);
        } else if (s.state == CallState.ended || s.state == CallState.idle) {
          ChatNotificationService.instance.cancelCallNotification();
          ref
              .read(discoveryServiceProvider.notifier)
              .updateLocalStatus(DeviceStatus.available);
        }
      },
    );
    await _manager!.startCall(
      peerId: peerId,
      peerName: peerName,
      peerIp: peerIp,
    );
    return true;
  }

  /// Accept an incoming call after user taps "Accept".
  Future<void> acceptCall({
    required String callerIp,
    required int signalingPort,
    required String callerId,
    required String callerName,
  }) async {
    // Remove cancelCallNotification from here, handled cleanly in onStateChanged
    await CallAudioService.instance.stopAll();
    _manager?.dispose();
    // Bug 2: mark self as busy so peer devices stop showing us as available
    ref
        .read(discoveryServiceProvider.notifier)
        .updateLocalStatus(DeviceStatus.busy);
    _manager = CallManager(
      selfUuid: _selfUuid,
      selfName: _selfName,
      onStateChanged: (s) {
        state = AsyncData(s);
        if (s.state == CallState.active) {
          // Cancel our custom notification — flutter_background owns the ongoing foreground one
          ChatNotificationService.instance.cancelCallNotification();
          // Broadcast inCall so peers see we are on a call
          ref
              .read(discoveryServiceProvider.notifier)
              .updateLocalStatus(DeviceStatus.inCall);
        } else if (s.state == CallState.ended || s.state == CallState.idle) {
          ChatNotificationService.instance.cancelCallNotification();
          ref
              .read(discoveryServiceProvider.notifier)
              .updateLocalStatus(DeviceStatus.available);
        }
      },
    );
    // Pre-set session so screens show peer name immediately
    state = AsyncData(
      CallSession(
        state: CallState.connecting,
        peerId: callerId,
        peerName: callerName,
        peerIp: callerIp,
      ),
    );
    await _manager!.acceptCall(
      callerIp: callerIp,
      signalingPort: signalingPort,
    );
  }

  /// Decline an incoming call.
  Future<void> declineCall({
    required String callerIp,
    required int signalingPort,
  }) async {
    // Cancel the heads-up notification and stop ringtone
    await ChatNotificationService.instance.cancelCallNotification();
    await CallAudioService.instance.stopAll();
    _manager?.dispose();
    _manager = null;

    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      final payload = utf8.encode(
        jsonEncode({'type': 'call_declined', 'from': _selfUuid}),
      );
      socket.send(payload, InternetAddress(callerIp), kCallInviteUdpPort);
      socket.close();
    } catch (_) {}

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
      _inviteSocket!.listen((event) async {
        if (event != RawSocketEvent.read) return;
        final dg = _inviteSocket!.receive();
        if (dg == null) return;
        try {
          final json = jsonDecode(utf8.decode(dg.data)) as Map<String, dynamic>;

          // ── Incoming call invite ──────────────────────────────────────────
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

            final currentState = state.valueOrNull?.state ?? CallState.idle;
            final currentPeerId = state.valueOrNull?.peerId;

            // Reconnect check
            if ((currentState == CallState.active ||
                    currentState == CallState.connecting) &&
                currentPeerId == peerId) {
              _manager?.handleReconnectInvite(signalingPort, callerIp);
              return;
            }

            if (currentState != CallState.idle &&
                currentState != CallState.ended) {
              if (currentState == CallState.outgoing) {
                debugPrint(
                  '[Call] Glare detected (Simultaneous Call). Dropping incoming invite gracefully.',
                );
                // Send call_rejected so the other side doesn't wait indefinitely
                try {
                  RawDatagramSocket.bind(InternetAddress.anyIPv4, 0).then((
                    socket,
                  ) {
                    final payload = utf8.encode(
                      jsonEncode({'type': 'call_rejected', 'from': _selfUuid}),
                    );
                    socket.send(
                      payload,
                      InternetAddress(callerIp),
                      kCallInviteUdpPort,
                    );
                    socket.close();
                  });
                } catch (_) {}
                return;
              } else {
                // Already in an active call with someone else
                try {
                  RawDatagramSocket.bind(InternetAddress.anyIPv4, 0).then((
                    socket,
                  ) {
                    final payload = utf8.encode(
                      jsonEncode({'type': 'call_busy', 'from': _selfUuid}),
                    );
                    socket.send(
                      payload,
                      InternetAddress(callerIp),
                      kCallInviteUdpPort,
                    );
                    socket.close();
                  });
                } catch (_) {}
                return;
              }
            }

            // Mark callee provider as 'incoming' so ref.listen on
            // IncomingCallScreen can react to any future state change
            // (e.g. caller cancels → state becomes ended → screen pops)
            state = AsyncData(
              CallSession(
                state: CallState.incoming,
                peerId: peerId,
                peerName: peerName,
                peerIp: callerIp,
              ),
            );

            // Show system notification + play ringtone
            ChatNotificationService.instance.showCallNotification(
              callerName: peerName,
              callerId: peerId,
              callerIp: callerIp,
              signalingPort: signalingPort,
            );
            // Part 3 — play ringtone on notificationRingtone stream
            // (respects system silent/vibrate mode)
            CallAudioService.instance.playRingtone();

            onIncomingCall?.call({
              'peerId': peerId,
              'peerName': peerName,
              'callerIp': callerIp,
              'signalingPort': signalingPort,
            });
          }
          // ── Caller cancelled before callee answered ───────────────────────
          else if (json['type'] == 'call_cancelled') {
            if (json['from'] == _selfUuid) return;
            // Only dismiss if we are currently in incoming state for this peer
            final current = state.valueOrNull;
            if (current?.state == CallState.incoming &&
                current?.peerId == json['from']) {
              ChatNotificationService.instance.cancelCallNotification();
              CallAudioService.instance.stopAll(); // stop ringtone
              state = AsyncData(
                current!.copyWith(
                  state: CallState.ended,
                  endReason: CallEndReason.normal,
                ),
              );
            }
          }
          // ── Callee declined (via UDP) — notify caller ─────────────────────
          else if (json['type'] == 'call_declined') {
            if (json['from'] == _selfUuid) return;
            final current = state.valueOrNull;
            // Only react if we are the caller and are in outgoing state
            if (current?.state == CallState.outgoing) {
              final count = (current?.declineCount ?? 0) + 1;
              await CallAudioService.instance.stopAll(); // stop ringback on caller
              _manager?.dispose();
              _manager = null;
              state = AsyncData(
                current!.copyWith(
                  state: CallState.ended,
                  endReason: count >= 3
                      ? CallEndReason.busy
                      : CallEndReason.declined,
                  declineCount: count,
                ),
              );
            }
          }
          // ── Callee rejected (busy) (via UDP) — notify caller ────────────────
          else if (json['type'] == 'call_rejected' ||
              json['type'] == 'call_busy') {
            if (json['from'] == _selfUuid) return;
            final current = state.valueOrNull;
            if (current?.state == CallState.outgoing) {
              CallAudioService.instance.stopAll(); // stop ringback
              state = AsyncData(
                current!.copyWith(
                  state: CallState.ended,
                  endReason: json['type'] == 'call_busy'
                      ? CallEndReason.busy
                      : CallEndReason.declined,
                ),
              );
            }
          }
        } catch (_) {}
      });
    } catch (_) {
      // Port may already be bound — skip
    }
  }
}
