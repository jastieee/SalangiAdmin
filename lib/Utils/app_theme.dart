import 'package:flutter/material.dart';

// ── Brand colors (same for both modes) ──────────────
class AppColors {
  // Primary brand (kept under the name `blue` for backward compatibility)
  static const blue   = Color(0xFF6A3FA0); // brand purple
  // Brand accent (kept under the name `amber` for backward compatibility)
  static const amber  = Color(0xFFF5A623); // brand gold

  static const green  = Color(0xFF1F9D55);
  static const red    = Color(0xFFD93025);
  static const teal   = Color(0xFF0E7C86);
  static const purple = Color(0xFF6A3FA0);
  static const orange  = Color(0xFFE07A1F);
  static const cyan = Color(0xFF1AA9C9);
  static const orange1  = Color(0xFFE07A1F);

  // Light
  static const lightBg      = Color(0xFFF6F2FB); // soft purple-tinted white
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightBorder  = Color(0xFFE6DEF2);
  static const lightTextHi  = Color(0xFF1F1330); // deep purple-black
  static const lightTextLo  = Color(0xFF6B5B82);

  // Dark
  static const darkBg      = Color(0xFF130C1F); // near-black with purple cast
  static const darkSurface = Color(0xFF1E1530);
  static const darkBorder  = Color(0x22FFFFFF);
  static const darkTextHi  = Color(0xFFF3EAFF);
  static const darkTextLo  = Color(0xFFB0A1C7);
}

// ── Theme helper ─────────────────────────────────────
class AppTheme {
  final bool isDark;
  AppTheme(this.isDark);

  Color get bg      => isDark ? AppColors.darkBg      : AppColors.lightBg;
  Color get surface => isDark ? AppColors.darkSurface  : AppColors.lightSurface;
  Color get border  => isDark ? AppColors.darkBorder   : AppColors.lightBorder;
  Color get textHi  => isDark ? AppColors.darkTextHi   : AppColors.lightTextHi;
  Color get textLo  => isDark ? AppColors.darkTextLo   : AppColors.lightTextLo;

  // Primary purple is brighter in dark mode so it stays readable on dark surfaces.
  Color get blue    => isDark ? const Color(0xFFB28DDB) : AppColors.blue;
  // Gold is slightly brightened in dark mode for the same reason.
  Color get amber   => isDark ? const Color(0xFFFFB845) : AppColors.amber;

  Color get green   => isDark ? const Color(0xFF4ADE80) : AppColors.green;
  Color get red     => isDark ? const Color(0xFFFF6B6B) : AppColors.red;
  Color get teal    => isDark ? const Color(0xFF4FD1C5) : AppColors.teal;
  Color get purple  => isDark ? const Color(0xFFB28DDB) : AppColors.purple;
  Color get orange  => isDark ? const Color(0xFFFFA463) : AppColors.orange;
  Color get cyan    => isDark ? const Color(0xFF5FD4E8) : AppColors.cyan;

  Color get rowAlt => isDark
      ? const Color(0x14FFFFFF)
      : const Color(0xFFFBF8FF);

  Color get softBg => isDark
      ? const Color(0xFF18112A)
      : const Color(0xFFFBF8FF);

  Color get cardTint => isDark
      ? const Color(0xFF241A3A)
      : const Color(0xFFFFFFFF);

  double get selectedOpacity => isDark ? 0.18 : 0.10;
  double get tintOpacity     => isDark ? 0.16 : 0.10;
}

// ── Global notifier — import this everywhere ─────────
class ThemeNotifier extends ValueNotifier<bool> {
  ThemeNotifier() : super(false); // false = light mode

  bool get isDark => value;
  void toggle()   => value = !value;
  AppTheme get theme => AppTheme(isDark);
}

// Single global instance
final themeNotifier = ThemeNotifier();