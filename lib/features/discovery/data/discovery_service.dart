import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../domain/device_model.dart';
import 'device_registry.dart';
import 'mdns_service.dart';
import 'udp_broadcast_service.dart';
import 'package:flutter/foundation.dart';
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
    });

    // Poll for IP changes (e.g. WiFi disconnect/reconnect)
    Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (!ref.exists(discoveryServiceProvider)) {
        timer.cancel();
        return;
      }
      final network = NetworkInfo();
      final currentRawIp = await network.getWifiIP() ?? '127.0.0.1';
      final currentIp = normalizeDigits(currentRawIp);

      if (_selfUuid != null && _udp.selfDevice.localIp != currentIp) {
        debugPrint('[Discovery] Network changed! Re-binding UDP socket...');
        await _udp.stop(); // Destroy the dead socket
        
        final newSelf = _udp.selfDevice.copyWith(localIp: currentIp);
        _udp.selfDevice = newSelf;
        _mdns.selfDevice = newSelf;
        
        await _udp.start(); // Re-bind on the new IP
        _registry.upsert(newSelf);
        _udp.announceDevice(newSelf);
      }
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

  /// Update the local device's status (e.g. busy during a call, available after).
  /// Immediately re-broadcasts via UDP so peer devices reflect the change
  /// within seconds without waiting for the next 5-second announce cycle.
  void updateLocalStatus(DeviceStatus status) {
    final updated = _udp.selfDevice.copyWith(status: status);
    _udp.selfDevice = updated;
    _mdns.selfDevice = updated;
    _registry.upsert(updated);
    _udp.announceDevice(updated);
  }

  // Empty out _syncPeerNames instead of deleting entirely to avoid
  // breaking layout indices further down if needed

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
