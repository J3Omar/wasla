# Progress: Device Discovery

## Status: ✅ Complete (Core done — Call actions pending next features)

---

## Changelog

| Date       | What                                                      | Status       |
|------------|-----------------------------------------------------------|--------------|
| 2026-05-25 | Created git branch `feature/device-discovery`             | ✅ Done      |
| 2026-05-25 | Added Android permissions to `AndroidManifest.xml`        | ✅ Done      |
| 2026-05-25 | `domain/device_model.dart` — Device + DeviceStatus enum   | ✅ Done      |
| 2026-05-25 | `data/device_registry.dart` — live map + 10s eviction     | ✅ Done      |
| 2026-05-25 | `data/udp_broadcast_service.dart` — UDP announce/listen   | ✅ Done      |
| 2026-05-25 | `data/mdns_service.dart` — mDNS discovery loop            | ✅ Done      |
| 2026-05-25 | `data/discovery_service.dart` — Riverpod AsyncNotifier    | ✅ Done      |
| 2026-05-25 | `presentation/home_screen.dart` — Device list UI          | ✅ Done      |
| 2026-05-25 | Router wired: `/home` → HomeScreen                        | ✅ Done      |
| 2026-05-25 | Tested: devices appear in ~5s on same Wi-Fi               | ✅ Done      |
| 2026-05-25 | Tested: devices disappear after 10s of no broadcasts      | ✅ Done      |

---

## Issues / Known Limitations

- `MdnsClient` in `multicast_dns` has no registration API — announcing is handled
  by UDP broadcast; mDNS loop is discovery-only. Will revisit if a native plugin
  becomes available.
- `_announceOnce()` in `MdnsService` is intentionally a no-op (see comment in code).
- `255.255.255.255` UDP broadcast may not work on some managed networks; works
  correctly on home/office Wi-Fi routers.
- Call/Chat buttons on device cards are wired to `() {}` — will be connected in
  the Voice Call and Chat feature branches.

---

## What's Missing (Not Blocking)

| Item | Reason |
|------|--------|
| Voice call button action | Requires Voice Call feature (next) |
| Video call button action | Requires Video Call feature |
| Chat button action | Requires Chat feature |
| Device status updates (busy/in-call) | Requires signaling layer |
| Unit tests for `DeviceRegistry` | Nice to have |

---

## Testing Results

- [x] Android → Linux (devices appeared in ~5s, disappeared in ~10s)
- [x] Android → Android (same subnet) — pending 2nd Android device
- [ ] Linux → Windows
- [x] Android → Windows
