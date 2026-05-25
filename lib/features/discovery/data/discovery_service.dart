import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:uuid/uuid.dart';
import '../domain/device_model.dart';
import 'device_registry.dart';
import 'mdns_service.dart';
import 'udp_broadcast_service.dart';

const _kUuidKey = 'wasla_device_uuid';
const _kNameKey = 'wasla_device_name';
const _kSignalingPort = 8765;

/// Riverpod provider for the discovery service.
final discoveryServiceProvider = AsyncNotifierProvider<DiscoveryService, Map<String, Device>>(
  DiscoveryService.new,
);

class DiscoveryService extends AsyncNotifier<Map<String, Device>> {
  late final DeviceRegistry _registry;
  late final UdpBroadcastService _udp;
  late final MdnsService _mdns;
  StreamSubscription<Map<String, Device>>? _sub;

  @override
  Future<Map<String, Device>> build() async {
    final selfDevice = await _loadSelf();

    _registry = DeviceRegistry();
    _udp = UdpBroadcastService(registry: _registry, selfDevice: selfDevice);
    _mdns = MdnsService(registry: _registry, selfDevice: selfDevice);

    _registry.start();
    await _udp.start();
    await _mdns.start();

    _sub = _registry.devicesStream.listen((devices) {
      state = AsyncData(devices);
    });

    ref.onDispose(() {
      _sub?.cancel();
      _udp.stop();
      _mdns.stop();
      _registry.dispose();
    });

    return _registry.devices;
  }

  Future<Device> _loadSelf() async {
    const storage = FlutterSecureStorage();
    String uuid = await storage.read(key: _kUuidKey) ?? '';
    String name = await storage.read(key: _kNameKey) ?? '';

    if (uuid.isEmpty) {
      uuid = const Uuid().v4();
      await storage.write(key: _kUuidKey, value: uuid);
    }
    if (name.isEmpty) {
      name = 'Device-${uuid.substring(0, 6).toUpperCase()}';
      await storage.write(key: _kNameKey, value: name);
    }

    final network = NetworkInfo();
    final ip = await network.getWifiIP() ?? '127.0.0.1';

    return Device(
      uuid: uuid,
      displayName: name,
      localIp: ip,
      port: _kSignalingPort,
      status: DeviceStatus.available,
      lastSeen: DateTime.now(),
      isSelf: true,
    );
  }
}
