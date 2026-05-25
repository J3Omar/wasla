# Progress: Device Discovery

## Status: 🟡 In Progress

---

## Changelog

| Date       | What                                                      | Status       |
|------------|-----------------------------------------------------------|--------------|
| 2026-05-25 | Created git branch `feature/device-discovery`             | ✅ Done      |
| 2026-05-25 | Added Android permissions to `AndroidManifest.xml`        | ✅ Done      |
| 2026-05-25 | `domain/device_model.dart` — Device + DeviceStatus enum  | ✅ Done      |
| 2026-05-25 | `data/device_registry.dart` — live map + eviction timer  | ✅ Done      |
| 2026-05-25 | `data/udp_broadcast_service.dart` — UDP announce/listen  | ✅ Done      |
| 2026-05-25 | `data/mdns_service.dart` — mDNS discover loop            | ✅ Done      |
| 2026-05-25 | `data/discovery_service.dart` — Riverpod AsyncNotifier   | ✅ Done      |
| 2026-05-25 | `presentation/home_screen.dart` — device list UI         | ✅ Done      |
| 2026-05-25 | Router wired: `/` → redirect → `/home` (HomeScreen)       | ✅ Done      |

---

## Issues
- `MdnsClient` in `multicast_dns` package has no registration API — announcing
  is handled by UDP broadcast; mDNS is discovery-only. Will revisit if a native
  plugin becomes available.
- Need real-device testing on the same Wi-Fi subnet.

---

## Testing Results

- [ ] Android → Android (same subnet)
- [ ] Linux → Android
- [ ] Windows → Android
- [ ] Android → Windows
- [ ] Linux → Windows
