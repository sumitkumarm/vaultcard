import 'package:flutter/material.dart';

class AppTheme {
  static const _seed = Color(0xFF006D5B);

  static ThemeData light() {
    final scheme =
        ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.light);
    return _buildTheme(scheme);
  }

  static ThemeData dark() {
    final scheme =
        ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.dark);
    return _buildTheme(scheme);
  }

  static ThemeData _buildTheme(ColorScheme scheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerHighest,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}
