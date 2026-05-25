import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../domain/device_model.dart';
import 'device_registry.dart';

const int _udpPort = 45678;
const _broadcastAddress = '255.255.255.255';
const _announceInterval = Duration(seconds: 5);

/// UDP Broadcast — primary discovery transport.
/// Announces self every 5 s and listens for other devices.
class UdpBroadcastService {
  UdpBroadcastService({
    required this.registry,
    required this.selfDevice,
  });

  final DeviceRegistry registry;
  final Device selfDevice;

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
        reusePort: true,
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

  void _sendAnnounce() {
    if (_socket == null || !_running) return;
    try {
      final payload = utf8.encode(jsonEncode(selfDevice.toJson()));
      _socket!.send(
        payload,
        InternetAddress(_broadcastAddress),
        _udpPort,
      );
    } catch (_) {}
  }

  void _onPacket(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final dg = _socket?.receive();
    if (dg == null) return;
    try {
      final raw = utf8.decode(dg.data);
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final device = Device.fromJson(json);
      if (device.uuid != selfDevice.uuid) {
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
