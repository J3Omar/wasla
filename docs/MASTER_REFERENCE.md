# LanConnect — Master Reference Document
> آخر تحديث: مايو 2026 | الحالة: 🟡 Phase 0 — التصميم

---

## 📌 الفكرة

تطبيق Flutter للتواصل داخل الشبكة المنزلية (LAN) بدون استهلاك إنترنت.  
الهدف: صوت + فيديو + screen share + chat + ملفات — كلها على الـ WiFi الداخلي فقط.

**السبب:** النت في مصر محدود، وأي مكالمة تليجرام بتاكل من الباقة.

---

## 💻 الأجهزة المستهدفة

| الجهاز | النظام |
|--------|--------|
| لاب | Windows 11 |
| لاب | Linux Mint |
| تابلت | Android 8.1.0 |
| تليفون | Android 12 |

> أي جهاز تاني ينزّل التطبيق هيشتغل — مش محكور على الأجهزة دي.

---

## 🧱 الـ Stack التقني

| الطبقة | التقنية | السبب |
|--------|---------|-------|
| UI + Logic | Flutter | cross-platform لكل الأجهزة بكود واحد |
| صوت / فيديو / screen | `flutter_webrtc` | معيار الصناعة، مشفر by default |
| Signaling | Supabase Realtime | مجاني، سريع، بدون سيرفر خاص |
| Auth | Supabase Auth | Email + Password |
| Presence | Supabase Presence | مين أونلاين على الشبكة |
| Chat History | Supabase DB | حفظ الرسائل |
| التصميم | Google Stitch | AI يولد UI من prompt |
| IDE | Antigravity | يقرأ Stitch عبر MCP ويكتب Flutter code |

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────┐
│         Supabase (إنترنت — بضع KB فقط)       │
│  Auth + Signaling + Presence + Chat History  │
└─────────────┬───────────────────────────────┘
              │ تبادل بيانات الاتصال فقط
┌─────────────▼───────────────────────────────┐
│           WebRTC P2P — على الـ LAN           │
│   صوت + فيديو + screen share + ملفات         │
│     مش بيخرج أي ميديا للإنترنت خالص          │
└─────────────────────────────────────────────┘
```

**الأمان:**
- WebRTC بيشفر كل الميديا تلقائياً بـ DTLS-SRTP
- Supabase Auth بيمنع أي حد من برا يوصل للـ Signaling
- الـ ICE Candidates هتكون LAN IPs بس — مش محتاج STUN/TURN

---

## 📱 الشاشات (١١ شاشة)

| # | الشاشة | الوصف |
|---|--------|-------|
| ١ | Splash Screen | لوجو + اسم التطبيق |
| ٢ | Register Screen | Email + Password + Confirm |
| ٣ | Login Screen | Email + Password |
| ٤ | Home Screen | قائمة الأجهزة الأونلاين على الـ LAN |
| ٥ | Chat Screen | المحادثة مع جهاز معين |
| ٦ | Outgoing Call Screen | شاشة "جاري الاتصال بـ..." |
| ٧ | Incoming Call Screen | شاشة "فيه حد بيتصل بيك" |
| ٨ | Active Voice Call | المكالمة الصوتية شغالة |
| ٩ | Active Video Call | المكالمة بالفيديو شغالة |
| ١٠ | Screen Share Screen | عرض الشاشة |
| ١١ | Settings Screen | اسم الجهاز + logout |

---

## 🔧 الفيتشرز — مرتبة حسب المراحل

### المرحلة ١ — الأساس
- [ ] Splash Screen
- [ ] Auth — Register / Login بـ Email
- [ ] Device Discovery — مين فاتح البرنامج على نفس الـ LAN
- [ ] Home Screen — قائمة الأجهزة

### المرحلة ٢ — التواصل
- [ ] Chat — رسائل نصية
- [ ] Voice Call
- [ ] Video Call
- [ ] Incoming / Outgoing Call Screens

### المرحلة ٣ — الميديا
- [ ] File Sharing — أثناء المحادثة
- [ ] Screen Share — bidirectional (لاب ← → موبايل)
- [ ] حفظ الملفات الواردة على الجهاز

### المرحلة ٤ — مستقبلاً
- [ ] Friends System
- [ ] Remote Control
- [ ] Device Vibration

---

## 🎛️ تفاصيل تقنية مهمة

### Device Discovery
- البرنامج لازم يكون **فاتح** عشان الجهاز يظهر
- بيظهر بس الأجهزة اللي على **نفس الـ LAN**
- مش زي WhatsApp — مفيش "online" لو البرنامج مغلق

### سلوك المكالمة
- الطرف المتصل يشوف Incoming Call Screen
- لو رفض ٣ مرات → رسالة "الجهاز مشغول"
- المكالمة الحالية لازم تخلص الأول عشان تبدأ جديدة

### أثناء المكالمة
- ✅ Mute / Unmute ميكروفون
- ✅ تشغيل / إيقاف كاميرا
- ✅ بدء / إيقاف Screen Share
- ✅ مشاركة صوت الجهاز مع Screen Share أو لأ (اختياري)
- ✅ إرسال رسائل نصية
- ✅ إرسال ملفات

### حفظ الملفات
```
Android → /storage/emulated/0/LanConnect/
Windows → C:\Users\[name]\Documents\LanConnect\
Linux   → ~/LanConnect/
```
Packages: `path_provider` + `permission_handler`

### الحد الأدنى للأنظمة
| النظام | الحد الأدنى |
|--------|------------|
| Android | 5.0 (API 21) |
| iOS | 12.0+ |
| Linux | أي توزيعة عندها GTK 3.0+ |
| Windows | Windows 10+ |

---

## 🎨 التصميم — Google Stitch

### ما هو Stitch؟
- AI tool من Google Labs يحول text prompts أو wireframes لـ UI
- مجاني: 350 Standard + 200 Pro generation في الشهر
- بيتبع Material Design 3 — مثالي لـ Flutter
- الرابط: https://stitch.withgoogle.com

### ربط Stitch بـ Antigravity عبر MCP
```
١. افتح Antigravity
٢. Settings → Extensions → ابحث عن "Stitch" → Install
٣. افتح stitch.withgoogle.com
٤. Profile → Stitch Settings → API Section → Create Key
٥. انسخ الـ API Key في Antigravity
٦. تحقق: اكتب في Antigravity: "List my Stitch projects"
```

### Prompt Template لكل شاشة
```
A mobile app [اسم الشاشة] for a LAN communication app 
called "LanConnect". Dark theme, modern minimal design,
Material Design 3 style. [وصف تفاصيل الشاشة]
```

---

## 🗂️ هيكل ملفات المشروع

```
lan_connect/
│
├── docs/
│   ├── PRD.md
│   ├── ARCHITECTURE.md
│   └── features/
│       ├── auth/
│       │   ├── spec.md
│       │   └── progress.md
│       ├── device_discovery/
│       │   ├── spec.md
│       │   └── progress.md
│       ├── chat/
│       │   ├── spec.md
│       │   └── progress.md
│       ├── voice_call/
│       │   ├── spec.md
│       │   └── progress.md
│       ├── video_call/
│       │   ├── spec.md
│       │   └── progress.md
│       ├── file_sharing/
│       │   ├── spec.md
│       │   └── progress.md
│       └── screen_share/
│           ├── spec.md
│           └── progress.md
│
├── design/
│   ├── design_reference.md      ← الألوان + الخطوط + الـ vibe
│   ├── inspiration/             ← screenshots من Stitch
│   └── theme/                   ← output من Material Theme Builder
│
├── lib/
│   ├── core/
│   │   ├── config/              ← supabase, env
│   │   ├── theme/               ← colors, text styles
│   │   ├── router/              ← navigation
│   │   └── utils/
│   └── features/
│       ├── auth/
│       │   ├── data/
│       │   ├── domain/
│       │   └── presentation/
│       ├── discovery/
│       ├── chat/
│       ├── voice_call/
│       ├── video_call/
│       ├── file_sharing/
│       └── screen_share/
│
├── .env                         ← Supabase keys (مش في GitHub)
├── .gitignore
└── README.md
```

---

## 📋 Template — spec.md

```markdown
# Feature: [اسم الفيتشر]

## الهدف
[وصف قصير]

## User Stories
- [ ] كـ مستخدم، عايز أـ...

## Screens
- [اسم الشاشة]

## Supabase Tables / Channels
- table: ``
- channel: `` (Realtime)

## الملفات اللي هتتعمل
- lib/features/[feature]/
  - data/
  - domain/
  - presentation/

## اختبارات القبول
- [ ] ...
```

---

## 📋 Template — progress.md

```markdown
# Progress: [اسم الفيتشر]

## Status: 🔴 Not Started

## Changelog
| Date | What | Who | Status |
|------|------|-----|--------|
| -    | -    | -   | -      |

## Issues
- لا يوجد

## Testing Results
- [ ] Windows → Android:
- [ ] Android → Windows:
- [ ] Android → Android:
- [ ] Linux → Android:
```

---

## 🗺️ الـ Workflow الكامل

```
PHASE 0 — التصميم ✅ ← أنت هنا
│
├── ١. 🟡 افتح Stitch → اعمل prompt للـ ١١ شاشة
├── ٢. ⬜ راجع التصاميم وعدّل بالـ chat
└── ٣. ⬜ اعمل design_reference.md (ألوان + خطوط + vibe)

PHASE 1 — الإعداد التقني
│
├── ٤. ⬜ افتح Antigravity → ربط Stitch بالـ MCP
├── ٥. ⬜ اكتب ملفات الـ docs (PRD + ARCHITECTURE + specs)
├── ٦. ⬜ flutter create lan_connect في Antigravity
├── ٧. ⬜ GitHub repo + .gitignore + README
├── ٨. ⬜ Supabase project → Tables + Auth setup
└── ٩. ⬜ .env + ربط Supabase بالمشروع

PHASE 2 — التنفيذ (فيتشر فيتشر)
│
├── لكل فيتشر:
│   ├── ⬜ Antigravity يقرأ spec.md
│   ├── ⬜ يجيب التصميم من Stitch بالـ MCP
│   ├── ⬜ يكتب الكود
│   ├── ⬜ اختبار على الأجهزة
│   ├── ⬜ تحديث progress.md
│   └── ⬜ git commit

PHASE 3 — الرفع والنشر
│
├── ⬜ GitHub Actions → builds لكل platform
│   ├── Windows .exe
│   ├── Linux .deb / .AppImage
│   └── Android .apk
├── ⬜ README كامل مع screenshots
└── ⬜ LinkedIn post
```

---

## ⏭️ الخطوة الحالية

### 🟡 Phase 0 — الخطوة ١: التصميم في Google Stitch

**المطلوب منك دلوقتي:**

١. افتح https://stitch.withgoogle.com
٢. اعمل **New Project** واسمه `LanConnect`
٣. اعمل prompt لكل شاشة من الـ ١١ دول واحدة واحدة

**مثال على الـ Splash Screen:**
```
A mobile app splash screen for a LAN communication app 
called "LanConnect". Dark theme, modern minimal design, 
logo with a network/connection symbol, app name centered.
Material Design 3 style. Purple or deep blue accent color.
```

**بعد ما تخلص الـ ١١ شاشة:**
- خد screenshot لكل شاشة
- لاحظ الألوان اللي Stitch اختارها
- ارجع وقولي وهنعمل الـ `design_reference.md` سوا

---

## ❓ قرارات لسا معلقة

| القرار | الخيارات | الاختيار |
|--------|----------|----------|
| Auth type | Email فقط / + Google Sign-in مستقبلاً | Email أولاً ✅ |
| Friends system | كل المسجلين / Friends فقط | مستقبلاً ⏳ |
| Chat offline | يتحفظ في Supabase / محلي بس | Supabase ✅ |
| Notifications background | Background service / مش مطلوب دلوقتي | مستقبلاً ⏳ |

---

## 📎 روابط مهمة

| الأداة | الرابط |
|--------|--------|
| Google Stitch | https://stitch.withgoogle.com |
| Supabase | https://supabase.com |
| Flutter Docs | https://flutter.dev/docs |
| flutter_webrtc | https://pub.dev/packages/flutter_webrtc |
| Material Theme Builder | https://m3.material.io/theme-builder |

---

*الملف ده هو المرجع الرئيسي للمشروع — حدّثه مع كل خطوة.*
