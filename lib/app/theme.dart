import 'package:flutter/material.dart';

/// Единственное место с цветами (правило W09).
abstract final class AppTheme {
  static const _seed = Color(0xFFE2574C); // томатный

  /// Акцент перерыва — спокойный зелёный (работа = primary).
  static const restGreen = Color(0xFF3FA45B);
  static const restGreenDark = Color(0xFF7CC98F);

  /// Палитра для категорий: цвет берётся по хэшу имени.
  static const categoryPalette = [
    Color(0xFFE2574C),
    Color(0xFF4C7DE2),
    Color(0xFF3FA45B),
    Color(0xFFC77D2E),
    Color(0xFF8C5BC7),
    Color(0xFF2E9DA6),
    Color(0xFFC74C86),
    Color(0xFF7D8C2E),
  ];

  static Color categoryColor(String category) =>
      categoryPalette[category.hashCode.abs() % categoryPalette.length];

  /// Зелёный, читаемый на текущем фоне.
  static Color rest(ColorScheme scheme) =>
      scheme.brightness == Brightness.dark ? restGreenDark : restGreen;

  static const _matrixGreen = Color(0xFF00FF66);

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  /// Чёрный терминал, неоновый зелёный, моноширинный шрифт.
  static ThemeData matrix() {
    final scheme = ColorScheme.fromSeed(
      seedColor: _matrixGreen,
      brightness: Brightness.dark,
    ).copyWith(
      primary: _matrixGreen,
      onPrimary: Colors.black,
      secondary: _matrixGreen,
      tertiary: _matrixGreen,
      surface: Colors.black,
      surfaceContainerLowest: const Color(0xFF040A04),
      onSurface: _matrixGreen,
      onSurfaceVariant: const Color(0xFF3FA45B),
      outline: const Color(0xFF1E5C33),
      outlineVariant: const Color(0xFF123D20),
      error: const Color(0xFFFF3B30),
    );
    final base = _build(
      Brightness.dark,
      overrideScheme: scheme,
      background: Colors.black,
      card: const Color(0xFF040A04),
      border: const Color(0xFF1E5C33),
    );
    final mono = base.textTheme.apply(
      fontFamily: 'Consolas',
      fontFamilyFallback: const ['Courier New', 'monospace'],
    );
    return base.copyWith(
      textTheme: mono,
      primaryTextTheme: mono,
      scaffoldBackgroundColor: Colors.black,
    );
  }

  static ThemeData _build(
    Brightness brightness, {
    ColorScheme? overrideScheme,
    Color? background,
    Color? card,
    Color? border,
  }) {
    final dark = brightness == Brightness.dark;
    final scheme =
        overrideScheme ??
        ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
    // Тёплая бумага вместо дефолтного серого: фон чуть тонирован сидом,
    // карточки — чистые, с тонкой обводкой вместо тени. Тема matrix
    // передаёт свою чёрно-зелёную палитру через параметры выше.
    background ??= dark ? const Color(0xFF161416) : const Color(0xFFF8F4F2);
    card ??= dark ? const Color(0xFF201D1F) : Colors.white;
    border ??= dark ? const Color(0xFF383336) : const Color(0xFFEAE1DD);

    final radius12 = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );

    return ThemeData(
      colorScheme: scheme.copyWith(
        surface: background,
        surfaceContainerLowest: card,
        outlineVariant: border,
      ),
      useMaterial3: true,
      scaffoldBackgroundColor: background,
      cardTheme: CardThemeData(
        elevation: 0,
        color: card,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: border),
        ),
      ),
      dividerTheme: DividerThemeData(color: border),
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: card,
        elevation: 3,
        shadowColor: Colors.black26,
        shape: radius12,
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: dark ? const Color(0xFF262224) : const Color(0xFFFBF9F8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          side: BorderSide(color: border),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: card,
        indicatorColor: scheme.primary.withValues(alpha: 0.14),
        selectedIconTheme: IconThemeData(color: scheme.primary),
        selectedLabelTextStyle: TextStyle(
          color: scheme.primary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontSize: 12,
        ),
        labelType: NavigationRailLabelType.all,
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 400),
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF3A3538) : const Color(0xFF3C3234),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      listTileTheme: ListTileThemeData(shape: radius12),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: radius12,
      ),
    );
  }
}
