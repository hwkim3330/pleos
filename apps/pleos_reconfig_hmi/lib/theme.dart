import 'package:flutter/material.dart';

/// One dark instrument palette, four semantic colours, nothing else. The two
/// older consoles drifted into light grey cards where every element carried the
/// same visual weight, so nothing read as important; here colour is reserved for
/// state and everything structural is neutral.
class Tone {
  const Tone._();

  static const background = Color(0xFF07090A);
  static const surface = Color(0xFF11161B);
  static const surfaceRaised = Color(0xFF171F26);
  static const hairline = Color(0xFF222C34);

  static const textPrimary = Color(0xFFE8EEF3);
  static const textSecondary = Color(0xFF8C9BA8);
  static const textFaint = Color(0xFF5A6874);

  static const healthy = Color(0xFF3ED598);
  static const warning = Color(0xFFFFB84D);
  static const fault = Color(0xFFFF5E5B);
  static const idle = Color(0xFF44535F);
}

/// Labels are small, uppercase and wide; values are large and tight. That single
/// contrast does most of the hierarchy work, so panels do not need borders and
/// shadows to separate themselves.
class TypeScale {
  const TypeScale._();

  static const label = TextStyle(
    fontSize: 11,
    height: 1.1,
    letterSpacing: 1.4,
    fontWeight: FontWeight.w600,
    color: Tone.textFaint,
  );

  static const value = TextStyle(
    fontSize: 15,
    height: 1.2,
    letterSpacing: -0.1,
    fontWeight: FontWeight.w600,
    color: Tone.textPrimary,
  );

  static const headline = TextStyle(
    fontSize: 34,
    height: 1.0,
    letterSpacing: -1.0,
    fontWeight: FontWeight.w700,
    color: Tone.textPrimary,
  );

  static const body = TextStyle(
    fontSize: 13,
    height: 1.35,
    color: Tone.textSecondary,
  );

  static const mono = TextStyle(
    fontSize: 12,
    height: 1.3,
    letterSpacing: 0.2,
    fontFeatures: [FontFeature.tabularFigures()],
    color: Tone.textSecondary,
  );
}

ThemeData buildHmiTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: Tone.background,
    colorScheme: base.colorScheme.copyWith(
      surface: Tone.surface,
      primary: Tone.healthy,
      error: Tone.fault,
    ),
    splashFactory: NoSplash.splashFactory,
  );
}
