import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../domain/device_model.dart';
import '../../chat/data/chat_repository.dart';
import 'device_registry.dart';
import 'mdns_service.dart';
import 'udp_broadcast_service.dart';
import '../../../core/utils/string_utils.dart';

const _kUuidKey = 'wasla_device_uuid';
const _kNameKey = 'wasla_device_name';
const _kSignalingPort = 8765;

/// Riverpod provider for the discovery service.
final discoveryServiceProvider =
    AsyncNotifierProvider<DiscoveryService, Map<String, Device>>(
      DiscoveryService.new,
    );

class DiscoveryService extends AsyncNotifier<Map<String, Device>> {
  late DeviceRegistry _registry;
  late UdpBroadcastService _udp;
  late MdnsService _mdns;
  StreamSubscription<Map<String, Device>>? _sub;
  String? _selfUuid;

  @override
  Future<Map<String, Device>> build() async {
    final selfDevice = await _loadSelf();
    _selfUuid = selfDevice.uuid;

    _registry = DeviceRegistry();
    _udp = UdpBroadcastService(registry: _registry, selfDevice: selfDevice);
    _mdns = MdnsService(registry: _registry, selfDevice: selfDevice);

    _registry.start();
    await _udp.start();
    await _mdns.start();

    _sub = _registry.devicesStream.listen((devices) {
      state = AsyncData(devices);
      // Keep chat DB peer names in sync so that when a peer renames their
      // device, the next UDP broadcast updates the Chats tab automatically
      // (within ~5 s) without requiring a restart on either device.
      _syncPeerNames(devices);
    });

    ref.onDispose(() {
      _sub?.cancel();
      _udp.stop();
      _mdns.stop();
      _registry.dispose();
    });

    return _registry.devices;
  }

  /// Call after saving a new device name.
  /// Reloads self from storage, updates the registry immediately (home screen
  /// reflects the new name at once) and sends a UDP broadcast so other devices
  /// on the LAN see the updated name within seconds — no service restart needed.
  Future<void> updateSelfName() async {
    final newSelf = await _loadSelf();
    _selfUuid = newSelf.uuid;
    _registry.upsert(newSelf);
    _registry.markSelf(newSelf.uuid);
    _udp.selfDevice = newSelf;
    _mdns.selfDevice = newSelf;
    _udp.announceDevice(newSelf);
  }

  /// For every discovered (non-self) device, ensure the Drift DB has an
  /// up-to-date peerName row. Creates the row if absent, updates it if the
  /// name changed (peer renamed their device).
  void _syncPeerNames(Map<String, Device> devices) {
    final chatRepo = ref.read(chatRepositoryProvider);
    for (final device in devices.values) {
      if (device.uuid != _selfUuid) {
        chatRepo.ensureConversation(
          peerUuid: device.uuid,
          peerName: device.displayName,
        );
      }
    }
  }

  Future<Map<String, String>> _loadIdentityBackup() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/.wasla_id');
      if (await file.exists()) {
        final content = await file.readAsString();
        final parts = content.split('|');
        if (parts.length >= 2) {
          return {'uuid': parts[0], 'name': parts[1]};
        }
      }
    } catch (_) {}
    return {};
  }

  Future<void> _saveIdentityBackup(String uuid, String name) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/.wasla_id');
      await file.writeAsString('$uuid|$name');
    } catch (_) {}
  }

  Future<Device> _loadSelf() async {
    const storage = FlutterSecureStorage();
    String uuid = '';
    String name = '';

    try {
      uuid = await storage.read(key: _kUuidKey) ?? '';
      name = await storage.read(key: _kNameKey) ?? '';
    } catch (_) {}

    if (uuid.isEmpty || name.isEmpty) {
      final backup = await _loadIdentityBackup();
      if (uuid.isEmpty && backup['uuid'] != null) {
        uuid = backup['uuid']!;
        try {
          await storage.write(key: _kUuidKey, value: uuid);
        } catch (_) {}
      }
      if (name.isEmpty && backup['name'] != null) {
        name = backup['name']!;
        try {
          await storage.write(key: _kNameKey, value: name);
        } catch (_) {}
      }
    }

    if (uuid.isEmpty) {
      uuid = const Uuid().v4();
      try {
        await storage.write(key: _kUuidKey, value: uuid);
      } catch (_) {}
    }
    if (name.isEmpty) {
      name = 'Device-${uuid.substring(0, 6).toUpperCase()}';
      try {
        await storage.write(key: _kNameKey, value: name);
      } catch (_) {}
    }

    await _saveIdentityBackup(uuid, name);

    final network = NetworkInfo();
    final rawIp = await network.getWifiIP() ?? '127.0.0.1';
    final ip = normalizeDigits(rawIp);

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
