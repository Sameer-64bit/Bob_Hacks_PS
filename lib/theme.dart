import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Warm, editorial palette — paper background, ink text, marigold accent.
class Palette {
  static const paper = Color(0xFFF7F4EE);
  static const card = Color(0xFFFFFFFF);
  static const line = Color(0xFFE6E1D6);
  static const dark = Color(0xFF191817);
  static const body = Color(0xFF4A4640);
  static const faint = Color(0xFF8A857C);

  static const navy = Color(0xFF16324F);
  static const marigold = Color(0xFFE8A33D);
  static const sage = Color(0xFF5E7D5A);
  static const terracotta = Color(0xFFC26D4C);
  static const slate = Color(0xFF3E4A5A);
  static const red = Color(0xFFB4483C);
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Palette.navy,
      primary: Palette.navy,
      secondary: Palette.marigold,
      surface: Palette.card,
      error: Palette.red,
    ),
    scaffoldBackgroundColor: Palette.paper,
  );

  final text = GoogleFonts.interTextTheme(base.textTheme).copyWith(
    displayLarge: GoogleFonts.fraunces(
        fontSize: 44, fontWeight: FontWeight.w600, color: Palette.dark, height: 1.05),
    displayMedium: GoogleFonts.fraunces(
        fontSize: 32, fontWeight: FontWeight.w600, color: Palette.dark, height: 1.1),
    headlineMedium: GoogleFonts.fraunces(
        fontSize: 24, fontWeight: FontWeight.w600, color: Palette.dark),
    titleLarge: GoogleFonts.inter(
        fontSize: 18, fontWeight: FontWeight.w600, color: Palette.dark),
    titleMedium: GoogleFonts.inter(
        fontSize: 15, fontWeight: FontWeight.w600, color: Palette.dark),
    bodyLarge: GoogleFonts.inter(fontSize: 15, color: Palette.body, height: 1.5),
    bodyMedium: GoogleFonts.inter(fontSize: 14, color: Palette.body, height: 1.5),
    bodySmall: GoogleFonts.inter(fontSize: 12.5, color: Palette.faint),
    labelLarge: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
  );

  return base.copyWith(
    textTheme: text,
    appBarTheme: AppBarTheme(
      backgroundColor: Palette.paper,
      foregroundColor: Palette.dark,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.fraunces(
          fontSize: 22, fontWeight: FontWeight.w600, color: Palette.dark),
    ),
    cardTheme: CardThemeData(
      color: Palette.card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Palette.line),
      ),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Palette.card,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Palette.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Palette.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Palette.navy, width: 1.6),
      ),
      labelStyle: GoogleFonts.inter(color: Palette.faint, fontSize: 14),
      hintStyle: GoogleFonts.inter(color: Palette.faint, fontSize: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Palette.dark,
        foregroundColor: Colors.white,
        minimumSize: const Size(56, 52),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle:
            GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Palette.dark,
        side: const BorderSide(color: Palette.line),
        minimumSize: const Size(56, 52),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle:
            GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    dividerTheme: const DividerThemeData(color: Palette.line, thickness: 1),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Palette.dark,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      contentTextStyle: GoogleFonts.inter(color: Colors.white, fontSize: 14),
    ),
  );
}
