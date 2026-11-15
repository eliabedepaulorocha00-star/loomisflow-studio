import 'package:flutter/material.dart';

class Palette {
  static const bg = Color(0xFF0B0C10);
  static const surface = Color(0xFF14161C);
  static const surfaceHi = Color(0xFF1D2028);
  static const line = Color(0xFF2A2E39);
  static const text = Color(0xFFE9EBF2);
  static const textDim = Color(0xFF8D93A5);
  static const accent = Color(0xFF7CF0C9); // menta
  static const accent2 = Color(0xFF8AA4FF); // azul-lavanda
  static const guide = Color(0xFF7CF0C9);
}

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: Palette.bg,
    colorScheme: const ColorScheme.dark(
      primary: Palette.accent,
      secondary: Palette.accent2,
      surface: Palette.surface,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: Palette.text,
      displayColor: Palette.text,
    ),
    sliderTheme: const SliderThemeData(
      trackHeight: 3,
      activeTrackColor: Palette.accent,
      inactiveTrackColor: Palette.line,
      thumbColor: Palette.accent,
      overlayShape: RoundSliderOverlayShape(overlayRadius: 18),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Palette.surfaceHi,
    ),
  );
}
