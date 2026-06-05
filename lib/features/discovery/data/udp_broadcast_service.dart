import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../domain/device_model.dart';
import 'device_registry.dart';

/// Get all valid local IPs (not loopback, not link-local)
Future<List<String>> getAllLocalIPs() async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLoopback: false,
  );

  final ips = <String>[];
  for (final interface in interfaces) {
    for (final addr in interface.addresses) {
      final ip = addr.address;
      // Skip loopback and link-local
      if (ip.startsWith('127.') || ip.startsWith('169.254.')) continue;
      ips.add(ip);
    }
  }
  return ips;
}

const int _udpPort = 45678;
const _broadcastAddress = '255.255.255.255';
const _announceInterval = Duration(seconds: 5);

/// UDP Broadcast — primary discovery transport.
/// Announces self every 5 s and listens for other devices.
class UdpBroadcastService {
  UdpBroadcastService({required this.registry, required this.selfDevice});

  final DeviceRegistry registry;
  Device selfDevice;

  RawDatagramSocket? _socket;
  Timer? _announceTimer;
  bool _running = false;

  Future<void> start() async {
    if (_running) return;
    _running = true;

    // Add self immediately
    registry.upsert(selfDevice);
    registry.markSelf(selfDevice.uuid);

    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _udpPort,
        reuseAddress: true,
      );
      _socket!.broadcastEnabled = true;
      _socket!.listen(_onPacket);
    } catch (e) {
      _running = false;
      return;
    }

    // Announce right away then on interval
    _sendAnnounce();
    _announceTimer = Timer.periodic(_announceInterval, (_) => _sendAnnounce());
  }

  void _sendAnnounce() async {
    if (_socket == null || !_running) return;
    final payload = utf8.encode(jsonEncode(selfDevice.toJson()));

    try {
      // Send to global broadcast
      _socket!.send(payload, InternetAddress(_broadcastAddress), _udpPort);
    } catch (_) {}

    try {
      // Send to all subnet broadcasts to cover Hotspot and WiFi simultaneously
      final ips = await getAllLocalIPs();
      for (final ip in ips) {
        final parts = ip.split('.');
        if (parts.length == 4) {
          parts[3] = '255';
          final subnetBroadcast = parts.join('.');
          _socket!.send(payload, InternetAddress(subnetBroadcast), _udpPort);
        }
      }
    } catch (_) {}
  }

  /// Send a one-shot announce with an arbitrary [device] payload.
  void announceDevice(Device device) async {
    if (_socket == null || !_running) return;
    final payload = utf8.encode(jsonEncode(device.toJson()));

    try {
      _socket!.send(payload, InternetAddress(_broadcastAddress), _udpPort);
    } catch (_) {}

    try {
      final ips = await getAllLocalIPs();
      for (final ip in ips) {
        final parts = ip.split('.');
        if (parts.length == 4) {
          parts[3] = '255';
          final subnetBroadcast = parts.join('.');
          _socket!.send(payload, InternetAddress(subnetBroadcast), _udpPort);
        }
      }
    } catch (_) {}
  }

  void _onPacket(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final dg = _socket?.receive();
    if (dg == null) return;
    try {
      final raw = utf8.decode(dg.data);
      final json = jsonDecode(raw) as Map<String, dynamic>;
      var device = Device.fromJson(json);
      if (device.uuid != selfDevice.uuid) {
        // Use the actual UDP source address — this is always reachable from us,
        // even when the sender is a hotspot host announcing a different interface IP.
        final sourceIp = dg.address.address;
        if (sourceIp != device.localIp && !sourceIp.startsWith('127.')) {
          device = device.copyWith(localIp: sourceIp);
        }
        registry.upsert(device);
      }
    } catch (_) {}
  }

  Future<void> stop() async {
    _running = false;
    _announceTimer?.cancel();
    _socket?.close();
    _socket = null;
  }
}
