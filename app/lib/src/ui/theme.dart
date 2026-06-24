import 'package:flutter/material.dart';

/// Redtick brand theme (FP-48). The brand accent is the Redtick red used across
/// the rebranded desktop app icons/login logo.
class RedtickTheme {
  static const Color brand = Color(0xFFE53935);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: brand,
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
  }
}
