import 'package:flutter/material.dart';

import 'farmgenie_theme_controller.dart';
import 'glass_home.dart';

ThemeData farmgenieTheme([
  FarmgenieThemeChoice choice = FarmgenieThemeChoice.farmgenie,
]) {
  final primary = switch (choice) {
    FarmgenieThemeChoice.farmgenie => forestGreen,
    FarmgenieThemeChoice.ocean => const Color(0xFF1565C0),
    FarmgenieThemeChoice.earth => const Color(0xFF8A5A2B),
  };
  final scheme = ColorScheme.fromSeed(
    seedColor: primary,
    primary: primary,
    surface: pageBackground,
    onSurface: homeInk,
  );
  final shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(14),
    side: const BorderSide(color: cardBorder),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.white,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: primary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: shape,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: shape,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: shape,
    ),
    drawerTheme: const DrawerThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      indicatorColor: iconTint,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: cardBorder),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: primary,
    ),
  );
}
