import 'package:flutter/material.dart';

import '../core/ecu/dtc_database.dart';
import '../licensing/tier.dart';

/// High-contrast theme: readable in sunlight, large glove-friendly targets.
class AppTheme {
  static const accent = Color(0xFF2F8CFF);
  static const ok = Color(0xFF2EB872);
  static const warn = Color(0xFFF2A93B);
  static const bad = Color(0xFFE5484D);

  static ThemeData dark() => _build(Brightness.dark);
  static ThemeData light() => _build(Brightness.light);

  static ThemeData _build(Brightness b) {
    final dark = b == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: b,
      primary: accent,
      surface: dark ? const Color(0xFF0E1116) : const Color(0xFFF6F7F9),
    ).copyWith(
      onPrimary: Colors.white,
      surfaceContainerLow: dark ? const Color(0xFF151A21) : Colors.white,
      surfaceContainer: dark ? const Color(0xFF1A2029) : const Color(0xFFEFF1F4),
      surfaceContainerHigh: dark ? const Color(0xFF222A35) : const Color(0xFFE6E9EE),
      error: bad,
    );
    final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: b);
    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: dark ? 0.35 : 0.6)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 56),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 52),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      listTileTheme: const ListTileThemeData(minVerticalPadding: 12),
      chipTheme: base.chipTheme.copyWith(shape: const StadiumBorder()),
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }

  static Color severity(Severity s) => switch (s) {
        Severity.high => bad,
        Severity.medium => warn,
        Severity.low => accent,
        Severity.info => Colors.blueGrey,
      };

  static Color tier(Tier t) => switch (t) {
        Tier.free => Colors.blueGrey,
        Tier.plus => accent,
        Tier.pro => const Color(0xFFB57BFF),
      };
}
