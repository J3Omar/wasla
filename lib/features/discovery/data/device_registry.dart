import 'dart:async';
import '../domain/device_model.dart';

/// Maintains the live map of discovered devices.
/// Devices that haven't been seen in [timeoutSeconds] are automatically evicted.
class DeviceRegistry {
  DeviceRegistry({this.timeoutSeconds = 10});

  final int timeoutSeconds;

  final Map<String, Device> _devices = {};
  final _controller = StreamController<Map<String, Device>>.broadcast();
  Timer? _evictionTimer;

  /// Stream of the current device map, emitted on every change.
  Stream<Map<String, Device>> get devicesStream => _controller.stream;

  /// Current snapshot.
  Map<String, Device> get devices => Map.unmodifiable(_devices);

  /// Start the eviction loop.
  void start() {
    _evictionTimer?.cancel();
    _evictionTimer = Timer.periodic(const Duration(seconds: 2), (_) => _evict());
  }

  /// Update or insert a device.
  void upsert(Device device) {
    _devices[device.uuid] = device;
    _emit();
  }

  /// Remove a device by UUID.
  void remove(String uuid) {
    if (_devices.remove(uuid) != null) _emit();
  }

  /// Mark own device so UI can badge it.
  void markSelf(String uuid) {
    final d = _devices[uuid];
    if (d != null && !d.isSelf) {
      _devices[uuid] = d.copyWith(isSelf: true);
      _emit();
    }
  }

  void _evict() {
    final cutoff = DateTime.now().subtract(Duration(seconds: timeoutSeconds));
    final stale = _devices.values
        .where((d) => !d.isSelf && d.lastSeen.isBefore(cutoff))
        .map((d) => d.uuid)
        .toList();
    if (stale.isNotEmpty) {
      for (final id in stale) {
        _devices.remove(id);
      }
      _emit();
    }
  }

  void _emit() {
    if (!_controller.isClosed) {
      _controller.add(Map.unmodifiable(_devices));
    }
  }

  void dispose() {
    _evictionTimer?.cancel();
    _controller.close();
  }
}
