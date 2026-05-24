import 'package:flutter/material.dart';

/// Wasla — Kinetic Ether Design System
/// All colors extracted from design/design_reference.md
abstract final class AppColors {
  // ── Brand Accents ────────────────────────────────────────────────────────
  static const Color primaryCyan = Color(0xFF00DBE7);
  static const Color primaryCyanBright = Color(0xFF00F2FF);
  static const Color primaryPurple = Color(0xFF7000FF);
  static const Color tertiaryGreen = Color(0xFF00FB83);

  // ── Backgrounds (darkest → lightest) ─────────────────────────────────────
  static const Color bgDeep = Color(0xFF0C0E10); // code blocks
  static const Color bgPrimary = Color(0xFF121416); // main background
  static const Color bgContainerLow = Color(0xFF1A1C1E);
  static const Color bgSecondary = Color(0xFF1E2022); // cards / elevated
  static const Color bgTertiary = Color(0xFF282A2C); // input fields
  static const Color bgQuaternary = Color(0xFF333537); // search bar / tags
  static const Color bgBright = Color(0xFF37393B); // active elements

  // ── Text ─────────────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFE2E2E5);
  static const Color textSecondary = Color(0xFFB9CACB);
  static const Color textMuted = Color(0xFF849495);

  // ── Status ───────────────────────────────────────────────────────────────
  static const Color statusOnline = Color(0xFF00E476);
  static const Color statusBusy = Color(0xFFD1BCFF);
  static const Color statusOffline = Color(0xFFFFB4AB);
  static const Color statusIdle = Color(0xFF849495);

  // ── Borders ───────────────────────────────────────────────────────────────
  static const Color borderDefault = Color(0x4D3A494B); // 30% opacity
  static const Color borderLight = Color(0x1A3A494B); // 10% opacity
  static const Color overlayWhite = Color(0x0DFFFFFF); // 5% white overlay

  // ── Danger ───────────────────────────────────────────────────────────────
  static const Color danger = Color(0xFF93000A);
  static const Color onDanger = Color(0xFFFFDAD6);

  // ── Gradients ─────────────────────────────────────────────────────────────
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [primaryCyan, primaryPurple],
  );

  static const LinearGradient sentMessageGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xCC00F2FF), Color(0xCC7000FF)],
  );

  static const LinearGradient transferGradient = LinearGradient(
    colors: [primaryCyan, tertiaryGreen],
  );

  static const LinearGradient splashGlowGradient = RadialGradient(
    center: Alignment.center,
    radius: 0.8,
    colors: [Color(0x4000DBE7), Color(0x00121416)],
  ) as LinearGradient;
}
