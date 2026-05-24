# وصلة — Wasla | Design Reference
> مستخرج من Figma | مايو 2026

---

## 🎨 Color Palette

### Primary Colors
```dart
// Accent / Brand
static const Color primaryCyan    = Color(0xFF00DBE7);  // #00DBE7 — الأساسي
static const Color primaryCyanAlt = Color(0xFF00F2FF);  // #00F2FF — glow version
static const Color primaryPurple  = Color(0xFF7000FF);  // #7000FF — gradient end

// Status Colors
static const Color statusOnline   = Color(0xFF00E476);  // #00E476 — أونلاين
static const Color statusBusy     = Color(0xFFD1BCFF);  // #D1BCFF — مشغول
static const Color statusOffline  = Color(0xFFFFB4AB);  // #FFB4AB — أوفلاين
static const Color statusIdle     = Color(0xFF849495);  // #849495 — خامل
```

### Background Colors
```dart
static const Color bgPrimary      = Color(0xFF121416);  // #121416 — الخلفية الرئيسية
static const Color bgSecondary    = Color(0xFF1E2022);  // #1E2022 — cards / elevated
static const Color bgTertiary     = Color(0xFF282A2C);  // #282A2C — input / buttons
static const Color bgQuaternary   = Color(0xFF333537);  // #333537 — search bar / tags
static const Color bgDeep         = Color(0xFF0C0E10);  // #0C0E10 — أعمق (code bg)
```

### Text Colors
```dart
static const Color textPrimary    = Color(0xFFE2E2E5);  // #E2E2E5 — النص الرئيسي
static const Color textSecondary  = Color(0xFFB9CACB);  // #B9CACB — النص الثانوي
static const Color textMuted      = Color(0xFF849495);  // #849495 — النص الخافت
```

### Border & Overlay
```dart
static const Color borderDefault  = Color(0x4D3A494B);  // rgba(58,73,75,0.3)
static const Color borderLight    = Color(0x1A3A494B);  // rgba(58,73,75,0.1)
static const Color overlayLight   = Color(0x0DFFFFFF);  // rgba(255,255,255,0.05)
```

### Danger
```dart
static const Color danger         = Color(0xFF93000A);  // #93000A — End Call
```

---

## 🌈 Gradients

```dart
// الـ Gradient الأساسي — يُستخدم في FAB + progress bar + active card border
static const LinearGradient primaryGradient = LinearGradient(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  colors: [Color(0xFF00DBE7), Color(0xFF7000FF)],
);

// Gradient البوردر للكارد النشط
static const LinearGradient activeBorderGradient = LinearGradient(
  colors: [Color(0xFF00DBE7), Color(0xFF7000FF)],
);

// Gradient الرسالة المُرسَلة
static const LinearGradient sentMessageGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xCC00F2FF), Color(0xCC7000FF)],
);

// Gradient الـ Screen Share progress
static const LinearGradient transferGradient = LinearGradient(
  colors: [Color(0xFF00DBE7), Color(0xFF00FB83)],
);
```

---

## ✍️ Typography

```dart
// Fonts المستخدمة في التصميم:
// - Hanken Grotesk  → العناوين الكبيرة (H1, H2, H3)
// - Geist           → الـ labels, timestamps, chips, IPs
// - Inter           → نص المحادثة (body text)
// - Liberation Mono → Code snippets

// Text Styles
static const TextStyle heading1 = TextStyle(
  fontFamily: 'HankenGrotesk',
  fontWeight: FontWeight.bold,
  fontSize: 28,
  letterSpacing: -0.4,
  color: textPrimary,
);

static const TextStyle heading2 = TextStyle(
  fontFamily: 'HankenGrotesk',
  fontWeight: FontWeight.bold,
  fontSize: 22,
  color: textPrimary,
);

static const TextStyle heading3 = TextStyle(
  fontFamily: 'HankenGrotesk',
  fontWeight: FontWeight.w600,
  fontSize: 18,
  color: textPrimary,
);

static const TextStyle bodyText = TextStyle(
  fontFamily: 'Inter',
  fontWeight: FontWeight.normal,
  fontSize: 14,
  height: 1.43,
  color: textPrimary,
);

static const TextStyle label = TextStyle(
  fontFamily: 'Geist',
  fontWeight: FontWeight.w500,
  fontSize: 12,
  letterSpacing: 0.6,
  color: textSecondary,
);

static const TextStyle labelSmall = TextStyle(
  fontFamily: 'Geist',
  fontWeight: FontWeight.w500,
  fontSize: 10,
  color: textSecondary,
);

static const TextStyle chip = TextStyle(
  fontFamily: 'Geist',
  fontWeight: FontWeight.w500,
  fontSize: 11,
  color: textSecondary,
);

static const TextStyle capsLabel = TextStyle(
  fontFamily: 'Geist',
  fontWeight: FontWeight.w500,
  fontSize: 12,
  letterSpacing: 1.2,
  color: textSecondary,
);
```

---

## 📐 Spacing & Border Radius

```dart
// Border Radius
static const double radiusSmall    = 4.0;
static const double radiusMedium   = 8.0;
static const double radiusDefault  = 12.0;
static const double radiusLarge    = 16.0;
static const double radiusXL       = 24.0;
static const double radiusPill     = 9999.0;

// Spacing
static const double spacingXS  = 4.0;
static const double spacingS   = 8.0;
static const double spacingM   = 12.0;
static const double spacingL   = 16.0;
static const double spacingXL  = 24.0;
static const double spacingXXL = 32.0;
```

---

## 🗂️ Screens Summary

### ١. Splash Screen
- **خلفية:** `bgPrimary` (#121416)
- **تأثيرات:** Cyan glow (blur 60px) + purple orbital glow + grid pattern (opacity 40%)
- **اللوجو:** 256x256 مع Glassmorphic backing
- **Progress Bar:** gradient من Cyan لـ Purple (نص: "ESTABLISHING MESH...")
- **الـ vibe:** تقنية، مظلمة، تشعر بالاتصال

### ٢. Connected Devices (Home)
- **Top Bar:** `bgSecondary` blur + اسم "Wasla" بلون `primaryCyan` + avatar
- **عنوان:** "Devices on Local Network" — `heading2`
- **Subnet Chip:** border + `statusOnline` dot + "192.168.1.x"
- **Search Bar:** `bgQuaternary` rounded-12
- **Device Cards:** 4 حالات:
  - `Active/Self` — border gradient + cyan glow shadow + "THIS DEVICE" badge
  - `Busy/Transferring` — purple overlay + progress bar
  - `Idle` — زرار Browse + Connect
  - `Offline` — opacity 60% + "Last seen"
- **Bottom Nav:** 4 tabs: Devices (active/purple) | Chats | Calls | Settings
- **FAB:** gradient دايري (Cyan → Purple) في الكونر

### ٣. Chat Screen
- **Top Bar:** blur + Device avatar + name + IP (لون `statusOnline`) + call buttons
- **الرسائل الواردة:** `bgTertiary` rounded بـ corner صغير في الشمال التحت
- **الرسائل المُرسَلة:** gradient (Cyan → Purple) مع بلور + opacity 80%
- **File Card:** Glassmorphism داخل الرسالة
- **Code Snippet:** `bgDeep` + copy button
- **Input Bar:** `bgDeep` border + attach icon + textarea + Send button بلون `primaryCyan`

### ٤. Active Call Screen
- **خلفية:** atmospheric glow (cyan + purple)
- **Top Bar:** زرار minimize + "End-to-End Encrypted" chip + signal bars
- **Avatar:** دايري كبير 160x160 مع ripple effects + device icon
- **اسم الجهاز:** `heading1` أبيض
- **IP:** `primaryCyan` uppercase
- **Timer:** pill صغير مع dot أخضر
- **Bottom Controls (Glassmorphism Pill):** blur + 5 buttons:
  - Mic | Camera | Screen Share | Add Device | End Call (أحمر/`danger`)
- **End Call:** أكبر من الباقيين (64x64 مقابل 56x56) + red glow

### ٥. Incoming Call Screen
- **مشابه للـ Active Call** في الـ vibe
- **Top:** "Secure Connection" chip
- **المتصل:** Avatar + اسم + "Incoming call" chip
- **Footer:** زرار Decline (أحمر) + Accept (أخضر) مع spacing واسع
- **Network Chip:** يظهر نوع الاتصال (LAN/5GHz)

---

## 🧩 Reusable Components

```
WaslaChip          → rounded pill مع dot ولون مميز
DeviceCard         → الكارد الرئيسي مع 4 حالات
CallControlButton  → أزرار المكالمة الدايرية
MessageBubble      → received + sent
FileCard           → Glassmorphism card للملفات
ProgressBar        → gradient مع animation
BottomNavBar       → blur + 4 tabs
StatusDot          → dot صغير يعبر عن الحالة
```

---

## ✨ Design Language Summary

| العنصر | القيمة |
|--------|--------|
| Theme | Dark فقط |
| Style | Glassmorphism + Subtle Gradients |
| Vibe | Tech / Cyberpunk / Minimal |
| Primary Accent | Cyan #00DBE7 |
| Secondary Accent | Purple #7000FF |
| Danger | Red #93000A |
| Font اللوجو | Hanken Grotesk |
| Font النصوص | Inter |
| Font الـ Labels | Geist |
| Border Radius | 12px default |
| Blur | Backdrop blur على headers وnavbars وpills |

---

## 📁 Assets من Figma

> الأصول دي على Figma servers وصالحة لمدة 7 أيام — حملها وضعها في `/assets/images/`

| الاسم | الاستخدام |
|-------|----------|
| Wasla Logo | Splash Screen |
| Device Icons | كارت كل جهاز (laptop, phone, tablet, pc) |
| Navigation Icons | Bottom Nav Bar |
| Action Icons | Call Controls |
