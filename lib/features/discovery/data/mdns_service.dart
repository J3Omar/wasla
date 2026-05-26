import 'dart:async';
import 'dart:convert';
import 'package:multicast_dns/multicast_dns.dart';
import '../domain/device_model.dart';
import 'device_registry.dart';

const _serviceType = '_wasla._tcp';
const _domain = 'local';

/// Handles mDNS announcing and discovery.
class MdnsService {
  MdnsService({required this.registry, required this.selfDevice});

  final DeviceRegistry registry;
  Device selfDevice;

  MDnsClient? _client;
  Timer? _announceTimer;
  bool _running = false;

  Future<void> start() async {
    if (_running) return;
    _running = true;

    _client = MDnsClient();
    try {
      await _client!.start();
    } catch (e) {
      _client = null;
      _running = false;
      return;
    }

    // Add ourselves immediately
    registry.upsert(selfDevice);
    registry.markSelf(selfDevice.uuid);

    // Start discovery loop
    _startDiscovery();

    // Announce ourselves periodically
    _announceTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _announceOnce();
    });
    _announceOnce();
  }

  void _startDiscovery() {
    Future.microtask(() async {
      while (_running && _client != null) {
        try {
          await for (final ptr in _client!.lookup<PtrResourceRecord>(
            ResourceRecordQuery.serverPointer('$_serviceType.$_domain'),
          )) {
            if (!_running) break;
            await for (final _ in _client!.lookup<SrvResourceRecord>(
              ResourceRecordQuery.service(ptr.domainName),
            )) {
              if (!_running) break;
              // Look for TXT records carrying our JSON payload
              await for (final txt in _client!.lookup<TxtResourceRecord>(
                ResourceRecordQuery.text(ptr.domainName),
              )) {
                if (!_running) break;
                try {
                  final payload = txt.text;
                  final json = jsonDecode(payload) as Map<String, dynamic>;
                  final device = Device.fromJson(json);
                  if (device.uuid != selfDevice.uuid) {
                    registry.upsert(device);
                  }
                } catch (_) {}
              }
            }
          }
        } catch (_) {}
        await Future.delayed(const Duration(seconds: 3));
      }
    });
  }

  void _announceOnce() {
    // mDNS in flutter/dart doesn't have a built-in registration API,
    // so we use the TXT record lookup as a side channel — actual
    // announcement happens via UDP broadcast fallback in UdpBroadcastService.
    // This method intentionally left for future native plugin support.
  }

  Future<void> stop() async {
    _running = false;
    _announceTimer?.cancel();
    _client?.stop();
    _client = null;
  }
}
