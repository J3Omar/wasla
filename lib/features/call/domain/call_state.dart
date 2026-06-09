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
    this.startedAt,
    this.endReason,
    this.isMuted = false,
    this.isSpeakerOn = false,
    this.declineCount = 0,
    this.isLocalVideoOn = false,
    this.isRemoteVideoOn = false,
    this.isFrontCamera = true,
  });

  final CallState state;
  final String peerId;
  final String peerName;
  final String peerIp;
  final DateTime? startedAt;
  final CallEndReason? endReason;
  final bool isMuted;
  final bool isSpeakerOn;
  final bool isLocalVideoOn;
  final bool isRemoteVideoOn;
  final bool isFrontCamera;

  /// How many times the remote peer has declined (3 → busy message).
  final int declineCount;

  static const CallSession idle = CallSession(
    state: CallState.idle,
    peerId: '',
    peerName: '',
    peerIp: '',
  );

  CallSession copyWith({
    CallState? state,
    String? peerId,
    String? peerName,
    String? peerIp,
    DateTime? startedAt,
    CallEndReason? endReason,
    bool? isMuted,
    bool? isSpeakerOn,
    bool? isLocalVideoOn,
    bool? isRemoteVideoOn,
    bool? isFrontCamera,
    int? declineCount,
  }) {
    return CallSession(
      state: state ?? this.state,
      peerId: peerId ?? this.peerId,
      peerName: peerName ?? this.peerName,
      peerIp: peerIp ?? this.peerIp,
      startedAt: startedAt ?? this.startedAt,
      endReason: endReason ?? this.endReason,
      isMuted: isMuted ?? this.isMuted,
      isSpeakerOn: isSpeakerOn ?? this.isSpeakerOn,
      isLocalVideoOn: isLocalVideoOn ?? this.isLocalVideoOn,
      isRemoteVideoOn: isRemoteVideoOn ?? this.isRemoteVideoOn,
      isFrontCamera: isFrontCamera ?? this.isFrontCamera,
      declineCount: declineCount ?? this.declineCount,
    );
  }
}
