import 'package:flutter/foundation.dart';

/// Represents a single device discovered on the LAN.
enum DeviceStatus { available, inCall, busy, offline }

@immutable
class Device {
  const Device({
    required this.uuid,
    required this.displayName,
    required this.localIp,
    required this.port,
    required this.status,
    required this.lastSeen,
    this.isSelf = false,
  });

  final String uuid;
  final String displayName;
  final String localIp;
  final int port; // WebSocket signaling port
  final DeviceStatus status;
  final DateTime lastSeen;
  final bool isSelf;

  Device copyWith({
    String? uuid,
    String? displayName,
    String? localIp,
    int? port,
    DeviceStatus? status,
    DateTime? lastSeen,
    bool? isSelf,
  }) {
    return Device(
      uuid: uuid ?? this.uuid,
      displayName: displayName ?? this.displayName,
      localIp: localIp ?? this.localIp,
      port: port ?? this.port,
      status: status ?? this.status,
      lastSeen: lastSeen ?? this.lastSeen,
      isSelf: isSelf ?? this.isSelf,
    );
  }

  /// Serialize to JSON payload for UDP/mDNS announcements.
  Map<String, dynamic> toJson() => {
    'uuid': uuid,
    'name': displayName,
    'ip': localIp,
    'port': port,
    'status': status.name,
  };

  /// Deserialize from a JSON payload.
  factory Device.fromJson(Map<String, dynamic> json) {
    return Device(
      uuid: json['uuid'] as String,
      displayName: json['name'] as String,
      localIp: json['ip'] as String,
      port: (json['port'] as num).toInt(),
      status: DeviceStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => DeviceStatus.available,
      ),
      lastSeen: DateTime.now(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Device && uuid == other.uuid;

  @override
  int get hashCode => uuid.hashCode;

  @override
  String toString() => 'Device($displayName @ $localIp, $status)';
}
