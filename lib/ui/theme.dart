import 'package:flutter/material.dart';

/// The Plate's look: warm, plain, unclinical. Nutrition apps default to
/// charts and red warnings; this one should feel like a friend passing you
/// something across the table.
class PlateColors {
  static const cream = Color(0xFFFBF7F0);
  static const card = Color(0xFFFFFFFF);
  static const ink = Color(0xFF1F2420);
  static const inkSoft = Color(0xFF5C665E);
  static const green = Color(0xFF2E6B4F);
  static const greenSoft = Color(0xFFDCEBE2);
  static const amber = Color(0xFFE8A33D);
  static const amberSoft = Color(0xFFFBEBD2);
  static const clay = Color(0xFFC96F4A);
  static const claySoft = Color(0xFFF8E2DA);
  static const line = Color(0xFFE7E0D5);
}

/// Spacing scale. Everything in the app lands on one of these.
class Space {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;
}

const kRadius = 20.0;
const kRadiusSmall = 14.0;

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: PlateColors.green,
    surface: PlateColors.cream,
  ).copyWith(
    primary: PlateColors.green,
    onPrimary: Colors.white,
    secondary: PlateColors.amber,
    surface: PlateColors.cream,
    onSurface: PlateColors.ink,
  );

  final base = ThemeData(colorScheme: scheme, useMaterial3: true);

  return base.copyWith(
    scaffoldBackgroundColor: PlateColors.cream,
    textTheme: base.textTheme
        .apply(bodyColor: PlateColors.ink, displayColor: PlateColors.ink)
        .copyWith(
          displaySmall: const TextStyle(
            fontSize: 32,
            height: 1.15,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.6,
            color: PlateColors.ink,
          ),
          headlineMedium: const TextStyle(
            fontSize: 26,
            height: 1.2,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: PlateColors.ink,
          ),
          titleLarge: const TextStyle(
            fontSize: 19,
            height: 1.3,
            fontWeight: FontWeight.w600,
            color: PlateColors.ink,
          ),
          titleMedium: const TextStyle(
            fontSize: 16,
            height: 1.35,
            fontWeight: FontWeight.w600,
            color: PlateColors.ink,
          ),
          bodyLarge: const TextStyle(fontSize: 16, height: 1.45, color: PlateColors.ink),
          bodyMedium: const TextStyle(fontSize: 14.5, height: 1.45, color: PlateColors.inkSoft),
          labelLarge: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
        ),
    appBarTheme: const AppBarTheme(
      backgroundColor: PlateColors.cream,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: PlateColors.ink,
      ),
      iconTheme: IconThemeData(color: PlateColors.ink),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: PlateColors.green,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusSmall)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: PlateColors.ink,
        minimumSize: const Size.fromHeight(54),
        side: const BorderSide(color: PlateColors.line, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusSmall)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: PlateColors.green,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: PlateColors.ink,
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 15),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusSmall)),
    ),
    dividerTheme: const DividerThemeData(color: PlateColors.line, thickness: 1, space: 1),
  );
}
