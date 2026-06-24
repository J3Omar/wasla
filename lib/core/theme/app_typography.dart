import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Wasla — Typography System
/// Fonts: Hanken Grotesk (headings) · Inter (body) · Geist (labels/mono)
abstract final class AppTypography {
  // ── Headings — Hanken Grotesk ─────────────────────────────────────────────
  static TextStyle get heading1 => GoogleFonts.hankenGrotesk(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
    color: AppColors.textPrimary,
  );

  static TextStyle get heading2 => GoogleFonts.hankenGrotesk(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  static TextStyle get heading3 => GoogleFonts.hankenGrotesk(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static TextStyle get heading4 => GoogleFonts.hankenGrotesk(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  // ── Body — Inter ──────────────────────────────────────────────────────────
  static TextStyle get bodyLarge => GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: AppColors.textPrimary,
  );

  static TextStyle get bodyMedium => GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.43,
    color: AppColors.textPrimary,
  );

  static TextStyle get bodySmall => GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );

  // ── Labels — Geist ────────────────────────────────────────────────────────
  static TextStyle get labelLarge => GoogleFonts.getFont(
    'JetBrains Mono',
    fontSize: 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.6,
    color: AppColors.textSecondary,
  );

  static TextStyle get labelMedium => GoogleFonts.getFont(
    'JetBrains Mono',
    fontSize: 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.4,
    color: AppColors.textSecondary,
  );

  static TextStyle get labelSmall => GoogleFonts.getFont(
    'JetBrains Mono',
    fontSize: 10,
    fontWeight: FontWeight.w500,
    color: AppColors.textMuted,
  );

  static TextStyle get capsLabel => GoogleFonts.getFont(
    'JetBrains Mono',
    fontSize: 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 1.2,
    color: AppColors.textSecondary,
  );

  static TextStyle get timestamp => GoogleFonts.getFont(
    'JetBrains Mono',
    fontSize: 10,
    fontWeight: FontWeight.w400,
    color: AppColors.textMuted,
  );

  static TextStyle get ipAddress => GoogleFonts.getFont(
    'JetBrains Mono',
    fontSize: 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.8,
    color: AppColors.primaryCyan,
  );
}
