import 'package:flutter/material.dart';

import 'app_constants.dart';

ThemeData buildShizukuTheme() {
  return ThemeData(
    colorScheme: ColorScheme(
      brightness: Brightness.light,
      primary: shizukuPrimary,
      onPrimary: Colors.white,
      primaryContainer: shizukuSecondary,
      onPrimaryContainer: Colors.white,
      secondary: shizukuSecondary,
      onSecondary: Colors.black87,
      secondaryContainer: shizukuSurface,
      onSecondaryContainer: Colors.black87,
      tertiary: shizukuAccent,
      onTertiary: Colors.black87,
      tertiaryContainer: shizukuAccent.withOpacity(0.7),
      onTertiaryContainer: Colors.black87,
      error: Colors.red.shade700,
      onError: Colors.white,
      errorContainer: Colors.red.shade100,
      onErrorContainer: Colors.red.shade900,
      surface: shizukuSurface,
      onSurface: shizukuBackground,
      surfaceTint: shizukuPrimary,
      outline: shizukuSecondary,
      outlineVariant: shizukuSecondary.withOpacity(0.6),
      shadow: Colors.black26,
      scrim: Colors.black54,
      inverseSurface: shizukuBackground,
      onInverseSurface: shizukuAccent,
      inversePrimary: shizukuAccent,
    ),
    scaffoldBackgroundColor: Colors.white,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: shizukuPrimary,
      elevation: 1,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: shizukuPrimary,
      foregroundColor: Colors.white,
    ),
    useMaterial3: true,
  );
}
