# Wasla — Design System (Kinetic Ether)

> مستخرج من Google Stitch | مايو 2026

---

## معلومات الـ Design System

| | |
|---|---|
| **الاسم** | Kinetic Ether |
| **المصدر** | Google Stitch — Project: Wasla LAN Messenger |
| **الـ Project ID** | `7134726932797865114` |
| **Color Mode** | DARK |
| **Roundness** | ROUND_EIGHT (8px) |

---

## 🎨 الألوان الكاملة (Material 3)

### Brand Colors

| الاسم | Hex | الاستخدام |
|-------|-----|-----------|
| Primary (Cyan) | `#00DBE7` | الأكشن الرئيسي، الاتصال النشط |
| Primary Container | `#00F2FF` | خلفية الأزرار الرئيسية |
| Secondary (Purple) | `#7000FF` | الأكشن الثانوي، الاتصالات المشفرة |
| Tertiary (Green) | `#00FB83` | Online Status، التحويل الناجح |

### Surface Colors

| الاسم | Hex | المستوى |
|-------|-----|---------|
| Surface / Background | `#121416` | الخلفية الرئيسية (Level 0) |
| Surface Container Low | `#1A1C1E` | - |
| Surface Container | `#1E2022` | Cards / Lists (Level 1) |
| Surface Container High | `#282A2C` | Input fields |
| Surface Container Highest | `#333537` | Search bars / Tags |
| Surface Container Lowest | `#0C0E10` | Code blocks |
| Surface Bright | `#37393B` | Active elements |

### Text Colors

| الاسم | Hex | الاستخدام |
|-------|-----|-----------|
| On Surface (Primary Text) | `#E2E2E5` | النص الرئيسي |
| On Surface Variant (Secondary Text) | `#B9CACB` | النص الثانوي |
| Outline (Muted) | `#849495` | النص الخافت، الـ borders |
| Outline Variant | `#3A494B` | الـ borders الخفية |

### Status Colors

| الحالة | الاسم | Hex |
|--------|-------|-----|
| Online ✅ | Tertiary Fixed Dim | `#00E476` |
| Busy 🟣 | Secondary | `#D1BCFF` |
| Offline ❌ | Error | `#FFB4AB` |
| Idle ⚪ | Outline | `#849495` |

### Danger

| | Hex |
|---|---|
| End Call / Error | `#93000A` |

---

## ✍️ Typography

### Fonts المستخدمة

| الخط | الاستخدام |
|------|-----------|
| **Hanken Grotesk** | العناوين الكبيرة (Headline) |
| **Inter** | نص المحادثة والمحتوى (Body) |
| **Geist** | الـ Labels، الـ Timestamps، الـ IPs |

### Text Scale

| Style | Font | Size | Weight | Line Height |
|-------|------|------|--------|-------------|
| Headline LG | Hanken Grotesk | 32px | 700 | 40px |
| Headline LG Mobile | Hanken Grotesk | 28px | 700 | 36px |
| Headline MD | Hanken Grotesk | 24px | 600 | 32px |
| Body LG | Inter | 16px | 400 | 24px |
| Body MD | Inter | 14px | 400 | 20px |
| Label MD | Geist | 12px | 500 | 16px |

---

## 📐 Spacing & Radius

### Border Radius

| الاسم | القيمة |
|-------|--------|
| sm | 4px (0.25rem) |
| DEFAULT | 8px (0.5rem) |
| md | 12px (0.75rem) |
| lg | 16px (1rem) |
| xl | 24px (1.5rem) |
| full / pill | 9999px |

### Spacing Scale (Base: 8px)

| الاسم | القيمة |
|-------|--------|
| Base | 8px |
| Gutter | 16px |
| Margin Mobile | 16px |
| Margin Desktop | 32px |
| Container Max Width | 1200px |

---

## 🌈 Gradients

```dart
// Primary Gradient — FAB + Progress + Active borders
LinearGradient primaryGradient = LinearGradient(
  colors: [Color(0xFF00DBE7), Color(0xFF7000FF)],
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
);

// Sent Message Gradient
LinearGradient sentMessageGradient = LinearGradient(
  colors: [Color(0xCC00F2FF), Color(0xCC7000FF)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

// Transfer Progress Gradient
LinearGradient transferGradient = LinearGradient(
  colors: [Color(0xFF00DBE7), Color(0xFF00FB83)],
);
```

---

## 🏗️ Elevation & Depth (Glassmorphism)

| Level | الوصف | التأثير |
|-------|-------|---------|
| 0 | Background | `#121416` — لا شيء |
| 1 | Cards/Lists | Surface + 5% white overlay |
| 2 | Modals/Overlays | 10% translucent + 20px blur + 1px ghost border |
| Active | Interactive | Inner glow بـ Primary أو Secondary |

---

## 🧩 الكومبوننتس الرئيسية

```
WaslaChip          → Pill مع dot ولون مميز (status, network type)
DeviceCard         → الكارد الرئيسي — 4 حالات: Active/Busy/Idle/Offline
CallControlButton  → أزرار المكالمة الدايرية (56x56 / 64x64 End Call)
MessageBubble      → Received (bgTertiary) + Sent (gradient)
FileCard           → Glassmorphism card للملفات داخل المحادثة
ProgressBar        → Gradient + animation
BottomNavBar       → Blur + 4 tabs: Devices | Chats | Calls | Settings
StatusDot          → Dot صغير بلون الحالة
```

---

## 🖼️ الشاشات المصممة في Stitch

| # | الشاشة | الحالة |
|---|--------|--------|
| 1 | Splash Screen | ✅ جاهزة |
| 2 | Connected Devices (Home) | ✅ جاهزة |
| 3 | Chat Screen | ✅ جاهزة |
| 4 | Active Call Screen | ✅ جاهزة |
| 5 | Incoming Call Screen | ✅ جاهزة |

> الـ Screenshots في: `design/screens/`

---

## Flutter Code Reference

```dart
// lib/core/theme/app_colors.dart

class AppColors {
  // Brand
  static const Color primaryCyan    = Color(0xFF00DBE7);
  static const Color primaryCyanAlt = Color(0xFF00F2FF);
  static const Color primaryPurple  = Color(0xFF7000FF);

  // Status
  static const Color statusOnline   = Color(0xFF00E476);
  static const Color statusBusy     = Color(0xFFD1BCFF);
  static const Color statusOffline  = Color(0xFFFFB4AB);
  static const Color statusIdle     = Color(0xFF849495);

  // Backgrounds
  static const Color bgPrimary      = Color(0xFF121416);
  static const Color bgSecondary    = Color(0xFF1E2022);
  static const Color bgTertiary     = Color(0xFF282A2C);
  static const Color bgQuaternary   = Color(0xFF333537);
  static const Color bgDeep         = Color(0xFF0C0E10);

  // Text
  static const Color textPrimary    = Color(0xFFE2E2E5);
  static const Color textSecondary  = Color(0xFFB9CACB);
  static const Color textMuted      = Color(0xFF849495);

  // Borders
  static const Color borderDefault  = Color(0x4D3A494B);
  static const Color borderLight    = Color(0x1A3A494B);

  // Danger
  static const Color danger         = Color(0xFF93000A);
}
```
