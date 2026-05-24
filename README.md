# وصلة — Wasla 🔗

> **LAN Communication App** — تواصل كامل بدون إنترنت، على شبكتك المنزلية

[![Flutter](https://img.shields.io/badge/Flutter-3.x-blue?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.x-blue?logo=dart)](https://dart.dev)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20Windows%20%7C%20Linux-green)](https://flutter.dev/multi-platform)
[![Status](https://img.shields.io/badge/Status-Phase%200%20%E2%80%94%20Design-yellow)](./docs/PROGRESS.md)

---

## 💡 عن المشروع

**وصلة (Wasla)** هو تطبيق Flutter للتواصل داخل الشبكة المنزلية (LAN) بدون استهلاك إنترنت.

**المشكلة:** النت في مصر محدود، وأي مكالمة على تليجرام أو واتساب بتستهلك من الباقة، حتى لو الشخص التاني في نفس البيت على نفس الراوتر.

**الحل:** تطبيق تواصل كامل يشتغل على الـ WiFi الداخلي فقط — **صوت + فيديو + chat + ملفات + screen share** — بدون أي خروج للإنترنت.

---

## ✨ المميزات

| الميزة | الوصف | الحالة |
|--------|-------|--------|
| 🔍 Device Discovery | اكتشاف الأجهزة على الشبكة تلقائياً | 🔴 Not Started |
| 💬 Chat | رسائل نصية محلية ومشفرة | 🔴 Not Started |
| 📞 Voice Call | مكالمات صوتية فردية وجماعية | 🔴 Not Started |
| 📹 Video Call | مكالمات فيديو بجودة 720p | 🔴 Not Started |
| 🖥️ Screen Share | مشاركة الشاشة في الاتجاهين | 🔴 Not Started |
| 📁 File Sharing | إرسال ملفات أثناء المحادثة | 🔴 Not Started |

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────┐
│         Local WebSocket (Signaling)          │
│         الـ Caller ينشئ Server مؤقت          │
└─────────────┬───────────────────────────────┘
              │ تبادل بيانات الاتصال فقط (LAN)
┌─────────────▼───────────────────────────────┐
│           WebRTC P2P — على الـ LAN           │
│   صوت + فيديو + screen share + ملفات         │
│     100% محلي — لا يخرج أي شيء للإنترنت     │
└─────────────────────────────────────────────┘
```

**الأمان:**
- WebRTC يشفر كل الميديا تلقائياً بـ DTLS-SRTP
- كل البيانات والمحادثات محفوظة محلياً ومشفرة
- لا يوجد accounts أو servers خارجية

---

## 🧱 التقنيات المستخدمة

| الطبقة | التقنية |
|--------|---------|
| UI + Logic | Flutter / Dart |
| صوت / فيديو / screen | `flutter_webrtc` |
| Signaling | Local WebSocket Server |
| Device Discovery | mDNS + UDP Broadcast |
| Chat Storage | Drift / SQLite (local) |
| Device ID | `flutter_secure_storage` |
| التصميم | Google Stitch (AI UI Generator) |

---

## 📱 الشاشات

| # | الشاشة | الحالة |
|---|--------|--------|
| 1 | Splash Screen | 🟡 Designed |
| 2 | Onboarding (اسم الجهاز) | 🔴 Pending |
| 3 | Home — Connected Devices | 🟡 Designed |
| 4 | Chat Screen | 🟡 Designed |
| 5 | Outgoing Call Screen | 🔴 Pending |
| 6 | Incoming Call Screen | 🟡 Designed |
| 7 | Active Voice Call | 🟡 Designed |
| 8 | Active Video Call | 🔴 Pending |
| 9 | Screen Share Screen | 🔴 Pending |
| 10 | Settings Screen | 🔴 Pending |

---

## 🖥️ الأجهزة المدعومة

| الجهاز | النظام | الحد الأدنى |
|--------|--------|-------------|
| Android | Android | 5.0 (API 21)+ |
| Windows | Windows | 10+ |
| Linux | Linux | GTK 3.0+ |

---

## 📁 هيكل المشروع

```
wasla/
├── docs/
│   ├── PRD.md                    ← متطلبات المنتج
│   ├── ARCHITECTURE.md           ← التصميم التقني
│   ├── PROGRESS.md               ← تقدم المشروع الكلي
│   └── features/
│       ├── onboarding/
│       ├── device_discovery/
│       ├── chat/
│       ├── voice_call/
│       ├── video_call/
│       ├── file_sharing/
│       └── screen_share/
├── design/
│   ├── design_reference.md       ← نظام الألوان والخطوط
│   ├── design_system.md          ← Design System من Stitch
│   └── screens/                  ← Screenshots من Stitch
├── lib/
│   ├── core/
│   │   ├── config/
│   │   ├── theme/
│   │   ├── router/
│   │   └── utils/
│   └── features/
│       ├── onboarding/
│       ├── discovery/
│       ├── chat/
│       ├── voice_call/
│       ├── video_call/
│       ├── file_sharing/
│       └── screen_share/
├── assets/
│   ├── images/
│   └── fonts/
└── test/
```

---

## 🚀 تشغيل المشروع

```bash
# تثبيت الـ dependencies
flutter pub get

# تشغيل على Android
flutter run -d android

# تشغيل على Linux
flutter run -d linux

# تشغيل على Windows
flutter run -d windows
```

---

📊 **تفاصيل التقدم:** [PROGRESS.md](./docs/PROGRESS.md)

---

## 🎨 التصميم

التصميم مبني على **Google Stitch** بـ design system اسمه **Kinetic Ether**:
- **Theme:** Dark فقط
- **Style:** Glassmorphism + Subtle Gradients
- **Vibe:** Tech / Cyberpunk / Minimal
- **Primary:** Cyan `#00DBE7`
- **Secondary:** Purple `#7000FF`
- **Fonts:** Hanken Grotesk + Inter + Geist

📐 **التفاصيل الكاملة:** [design/design_reference.md](./design/design_reference.md)

---

## 📋 الـ Features Spec

| الفيتشر | Spec | Progress |
|---------|------|----------|
| Onboarding | [spec.md](./docs/features/onboarding/spec.md) | [progress.md](./docs/features/onboarding/progress.md) |
| Device Discovery | [spec.md](./docs/features/device_discovery/spec.md) | [progress.md](./docs/features/device_discovery/progress.md) |
| Chat | [spec.md](./docs/features/chat/spec.md) | [progress.md](./docs/features/chat/progress.md) |
| Voice Call | [spec.md](./docs/features/voice_call/spec.md) | [progress.md](./docs/features/voice_call/progress.md) |
| Video Call | [spec.md](./docs/features/video_call/spec.md) | [progress.md](./docs/features/video_call/progress.md) |
| File Sharing | [spec.md](./docs/features/file_sharing/spec.md) | [progress.md](./docs/features/file_sharing/progress.md) |
| Screen Share | [spec.md](./docs/features/screen_share/spec.md) | [progress.md](./docs/features/screen_share/progress.md) |


*مشروع شخصي — لا يوجد سيرفرات خارجية، كل شيء على شبكتك المنزلية.*
