/// Voice call state machine.
enum CallState { idle, outgoing, incoming, connecting, active, ended }

/// Reason a call ended.
enum CallEndReason { normal, declined, missed, networkLoss, busy }

/// A snapshot of the current call session.
class CallSession {
  const CallSession({
    required this.state,
    required this.peerId,
    required this.peerName,
    required this.peerIp,
    this.sessionId = '',
    this.startedAt,
    this.endReason,
    this.isMuted = false,
    this.isSpeakerOn = false,
    this.declineCount = 0,
    this.isLocalVideoOn = false,
    this.isRemoteVideoOn = false,
    this.isScreenSharing = false,
    this.isFrontCamera = true,
  });

  final CallState state;
  final String peerId;
  final String peerName;
  final String peerIp;
  final String sessionId;
  final DateTime? startedAt;
  final CallEndReason? endReason;
  final bool isMuted;
  final bool isSpeakerOn;
  final bool isLocalVideoOn;
  final bool isRemoteVideoOn;
  final bool isScreenSharing;
  final bool isFrontCamera;

  /// How many times the remote peer has declined (3 → busy message).
  final int declineCount;

  static const CallSession idle = CallSession(
    state: CallState.idle,
    peerId: '',
    peerName: '',
    peerIp: '',
    sessionId: '',
  );

  CallSession copyWith({
    CallState? state,
    String? peerId,
    String? peerName,
    String? peerIp,
    String? sessionId,
    DateTime? startedAt,
    CallEndReason? endReason,
    bool? isMuted,
    bool? isSpeakerOn,
    bool? isLocalVideoOn,
    bool? isRemoteVideoOn,
    bool? isScreenSharing,
    bool? isFrontCamera,
    int? declineCount,
  }) {
    return CallSession(
      state: state ?? this.state,
      peerId: peerId ?? this.peerId,
      peerName: peerName ?? this.peerName,
      peerIp: peerIp ?? this.peerIp,
      sessionId: sessionId ?? this.sessionId,
      startedAt: startedAt ?? this.startedAt,
      endReason: endReason ?? this.endReason,
      isMuted: isMuted ?? this.isMuted,
      isSpeakerOn: isSpeakerOn ?? this.isSpeakerOn,
      isLocalVideoOn: isLocalVideoOn ?? this.isLocalVideoOn,
      isRemoteVideoOn: isRemoteVideoOn ?? this.isRemoteVideoOn,
      isScreenSharing: isScreenSharing ?? this.isScreenSharing,
      isFrontCamera: isFrontCamera ?? this.isFrontCamera,
      declineCount: declineCount ?? this.declineCount,
    );
  }
}
