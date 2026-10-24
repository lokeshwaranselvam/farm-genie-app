import 'package:flutter/material.dart';

import 'glass_home.dart';

/// Shared green surfaces for native pages, forms and dialogs.
ThemeData farmgenieTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: forestGreen,
    primary: forestGreen,
    surface: const Color(0xFFF0FFF8),
    onSurface: const Color(0xFF203831),
  );
  final shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(21),
    side: const BorderSide(color: Colors.white, width: 1.8),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.transparent,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: forestGreen,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: const Color(0xCFFFFFFF),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: shape,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: const Color(0xF0EEFFF6),
      surfaceTintColor: Colors.transparent,
      shape: shape,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: const Color(0xF0EEFFF6),
      surfaceTintColor: Colors.transparent,
      shape: shape,
    ),
    drawerTheme: const DrawerThemeData(
      backgroundColor: Color(0xF0E6FFF2),
      surfaceTintColor: Colors.transparent,
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: Color(0xBDFFFFFF),
      surfaceTintColor: Colors.transparent,
      indicatorColor: Color(0xFFC5F5DE),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0x99FFFFFF),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFBDDFCF)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: forestGreen,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(21)),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: forestGreen,
    ),
  );
}
