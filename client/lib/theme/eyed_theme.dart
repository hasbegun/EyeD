import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Semantic colors extension (success/warning have no ColorScheme equivalent)
// ---------------------------------------------------------------------------

@immutable
class EyedSemanticColors extends ThemeExtension<EyedSemanticColors> {
  final Color success;
  final Color warning;
  final Color successContainer;
  final Color warningContainer;

  const EyedSemanticColors({
    required this.success,
    required this.warning,
    required this.successContainer,
    required this.warningContainer,
  });

  @override
  EyedSemanticColors copyWith({
    Color? success,
    Color? warning,
    Color? successContainer,
    Color? warningContainer,
  }) {
    return EyedSemanticColors(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      successContainer: successContainer ?? this.successContainer,
      warningContainer: warningContainer ?? this.warningContainer,
    );
  }

  @override
  EyedSemanticColors lerp(EyedSemanticColors? other, double t) {
    if (other is! EyedSemanticColors) return this;
    return EyedSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      successContainer: Color.lerp(successContainer, other.successContainer, t)!,
      warningContainer: Color.lerp(warningContainer, other.warningContainer, t)!,
    );
  }
}

const _lightSemantic = EyedSemanticColors(
  success: Color(0xFF1A7F37),
  warning: Color(0xFF9A6700),
  successContainer: Color(0xFFDCFFE4),
  warningContainer: Color(0xFFFFF8C5),
);

const _darkSemantic = EyedSemanticColors(
  success: Color(0xFF3FB950),
  warning: Color(0xFFD29922),
  successContainer: Color(0xFF0D2818),
  warningContainer: Color(0xFF2D2200),
);

// ---------------------------------------------------------------------------
// Shared component overrides
// ---------------------------------------------------------------------------

const _radius6 = BorderRadius.all(Radius.circular(6));

CardThemeData _cardTheme(ColorScheme cs) => CardThemeData(
      color: cs.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: _radius6,
        side: BorderSide(color: cs.outlineVariant),
      ),
      elevation: 0,
      margin: EdgeInsets.zero,
    );

InputDecorationTheme _inputTheme(ColorScheme cs) => InputDecorationTheme(
      filled: true,
      fillColor: cs.surfaceContainerLowest,
      border: OutlineInputBorder(
        borderRadius: _radius6,
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: _radius6,
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: _radius6,
        borderSide: BorderSide(color: cs.primary),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      hintStyle: TextStyle(color: cs.onSurfaceVariant),
      isDense: true,
    );

ElevatedButtonThemeData _elevatedButtonTheme(ColorScheme cs) =>
    ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: cs.primaryContainer,
        foregroundColor: cs.onPrimaryContainer,
        shape: RoundedRectangleBorder(borderRadius: _radius6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    );

OutlinedButtonThemeData _outlinedButtonTheme(ColorScheme cs) =>
    OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: cs.error,
        side: BorderSide(color: cs.error),
        shape: RoundedRectangleBorder(borderRadius: _radius6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
    );

ChipThemeData _chipTheme(ColorScheme cs) => ChipThemeData(
      backgroundColor: cs.surfaceContainer,
      selectedColor: cs.primaryContainer,
      side: BorderSide(color: cs.outlineVariant),
      shape: RoundedRectangleBorder(borderRadius: _radius6),
      labelStyle: TextStyle(color: cs.onSurface, fontSize: 13),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    );

// ---------------------------------------------------------------------------
// Theme builders
// ---------------------------------------------------------------------------

ThemeData buildEyedLightTheme() {
  final cs = ColorScheme.fromSeed(
    seedColor: const Color(0xFF58A6FF),
    brightness: Brightness.light,
  );
  return ThemeData(
    colorScheme: cs,
    dividerColor: cs.outlineVariant,
    cardTheme: _cardTheme(cs),
    inputDecorationTheme: _inputTheme(cs),
    elevatedButtonTheme: _elevatedButtonTheme(cs),
    outlinedButtonTheme: _outlinedButtonTheme(cs),
    chipTheme: _chipTheme(cs),
    extensions: const [_lightSemantic],
  );
}

ThemeData buildEyedDarkTheme() {
  final cs = ColorScheme.fromSeed(
    seedColor: const Color(0xFF58A6FF),
    brightness: Brightness.dark,
  );
  return ThemeData(
    colorScheme: cs,
    dividerColor: cs.outlineVariant,
    cardTheme: _cardTheme(cs),
    inputDecorationTheme: _inputTheme(cs),
    elevatedButtonTheme: _elevatedButtonTheme(cs),
    outlinedButtonTheme: _outlinedButtonTheme(cs),
    chipTheme: _chipTheme(cs),
    extensions: const [_darkSemantic],
  );
}