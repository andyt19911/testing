import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/ecu/dtc_database.dart';
import '../licensing/tier.dart';

/// Colours that Material's [ColorScheme] has no slot for: layered surfaces,
/// semantic status colours and the signature gradient.
@immutable
class RsColors extends ThemeExtension<RsColors> {
  const RsColors({
    required this.bg,
    required this.surface1,
    required this.surface2,
    required this.surface3,
    required this.outline,
    required this.text,
    required this.muted,
    required this.accent,
    required this.accent2,
    required this.ok,
    required this.warn,
    required this.bad,
  });

  final Color bg;
  final Color surface1;
  final Color surface2;
  final Color surface3;
  final Color outline;
  final Color text;
  final Color muted;
  final Color accent;

  /// Second stop of the signature gradient (an electric cyan, like a TFT dash).
  final Color accent2;
  final Color ok;
  final Color warn;
  final Color bad;

  LinearGradient get signature => LinearGradient(
        colors: [accent, accent2],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  /// Soft wash used behind hero panels.
  LinearGradient heroWash(Color tint) => LinearGradient(
        colors: [tint.withValues(alpha: 0.22), tint.withValues(alpha: 0.04)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  static const dark = RsColors(
    bg: Color(0xFF080B10),
    surface1: Color(0xFF10151C),
    surface2: Color(0xFF161D26),
    surface3: Color(0xFF1E2731),
    outline: Color(0xFF26313D),
    text: Color(0xFFE9EEF4),
    muted: Color(0xFF8E9BAC),
    accent: Color(0xFF3D8BFF),
    accent2: Color(0xFF19C8F5),
    ok: Color(0xFF34C77B),
    warn: Color(0xFFF5A524),
    bad: Color(0xFFF04A4A),
  );

  static const light = RsColors(
    bg: Color(0xFFF3F5F8),
    surface1: Color(0xFFFFFFFF),
    surface2: Color(0xFFEDF0F4),
    surface3: Color(0xFFE2E7ED),
    outline: Color(0xFFD5DCE4),
    text: Color(0xFF0D131A),
    muted: Color(0xFF586577),
    accent: Color(0xFF1F6FEB),
    accent2: Color(0xFF0AA7D6),
    ok: Color(0xFF1E9E5D),
    warn: Color(0xFFC77A06),
    bad: Color(0xFFD7373A),
  );

  @override
  RsColors copyWith() => this;

  @override
  RsColors lerp(ThemeExtension<RsColors>? other, double t) {
    if (other is! RsColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return RsColors(
      bg: l(bg, other.bg),
      surface1: l(surface1, other.surface1),
      surface2: l(surface2, other.surface2),
      surface3: l(surface3, other.surface3),
      outline: l(outline, other.outline),
      text: l(text, other.text),
      muted: l(muted, other.muted),
      accent: l(accent, other.accent),
      accent2: l(accent2, other.accent2),
      ok: l(ok, other.ok),
      warn: l(warn, other.warn),
      bad: l(bad, other.bad),
    );
  }
}

extension RsThemeX on BuildContext {
  RsColors get rs => Theme.of(this).extension<RsColors>()!;
  TextTheme get text => Theme.of(this).textTheme;
}

/// Layout breakpoints (logical pixels).
class Breakpoints {
  static const compact = 600.0;
  static const expanded = 1024.0;

  /// Grid columns for task tiles and gauges at a given width.
  static int columns(double width, {int compact = 2, int medium = 3, int expanded = 4}) =>
      width >= Breakpoints.expanded ? expanded : (width >= Breakpoints.compact ? medium : compact);
}

/// High-contrast theme: readable in sunlight, large glove-friendly targets.
class AppTheme {
  // Semantic colours that read well on both light and dark surfaces.
  static const accent = Color(0xFF2F86FF);
  static const ok = Color(0xFF2EB872);
  static const warn = Color(0xFFF2A93B);
  static const bad = Color(0xFFE5484D);
  static const pro = Color(0xFFA77BFF);

  static const display = 'BarlowCondensed';
  static const body = 'Barlow';

  static ThemeData dark() => _build(Brightness.dark, RsColors.dark);
  static ThemeData light() => _build(Brightness.light, RsColors.light);

  static TextTheme _type(Color text, Color muted) {
    TextStyle d(double size, FontWeight w, {double ls = 0, double h = 1.1}) =>
        TextStyle(fontFamily: display, fontSize: size, fontWeight: w, letterSpacing: ls, height: h, color: text);
    TextStyle b(double size, FontWeight w, {Color? c, double h = 1.4, double ls = 0}) =>
        TextStyle(fontFamily: body, fontSize: size, fontWeight: w, height: h, letterSpacing: ls, color: c ?? text);
    return TextTheme(
      displayLarge: d(64, FontWeight.w800, ls: -0.5, h: 1.0),
      displayMedium: d(48, FontWeight.w800, h: 1.0),
      displaySmall: d(40, FontWeight.w700),
      headlineLarge: d(34, FontWeight.w700),
      headlineMedium: d(30, FontWeight.w700),
      headlineSmall: d(26, FontWeight.w700),
      titleLarge: b(20, FontWeight.w600, h: 1.25),
      titleMedium: b(17, FontWeight.w600, h: 1.3),
      titleSmall: b(15, FontWeight.w600, h: 1.3),
      bodyLarge: b(17, FontWeight.w400),
      bodyMedium: b(15, FontWeight.w400),
      bodySmall: b(13, FontWeight.w400, c: muted),
      labelLarge: b(16, FontWeight.w600, h: 1.2),
      labelMedium: b(13, FontWeight.w600, h: 1.2, ls: 0.2),
      labelSmall: b(11.5, FontWeight.w600, h: 1.2, ls: 0.4),
    );
  }

  static ThemeData _build(Brightness b, RsColors c) {
    final dark = b == Brightness.dark;
    final scheme = ColorScheme.fromSeed(seedColor: c.accent, brightness: b).copyWith(
      primary: c.accent,
      onPrimary: Colors.white,
      secondary: c.accent2,
      surface: c.bg,
      onSurface: c.text,
      onSurfaceVariant: c.muted,
      surfaceContainerLowest: c.bg,
      surfaceContainerLow: c.surface1,
      surfaceContainer: c.surface2,
      surfaceContainerHigh: c.surface3,
      surfaceContainerHighest: c.surface3,
      outline: c.outline,
      outlineVariant: c.outline,
      error: c.bad,
    );
    final type = _type(c.text, c.muted);
    final radius16 = BorderRadius.circular(16);
    final base = ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: scheme,
      fontFamily: body,
      textTheme: type,
      extensions: [c],
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
    );
    return base.copyWith(
      scaffoldBackgroundColor: c.bg,
      canvasColor: c.bg,
      dividerTheme: DividerThemeData(color: c.outline, thickness: 1, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: c.bg,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        foregroundColor: c.text,
        titleTextStyle: type.headlineSmall?.copyWith(fontSize: 26),
      ),
      cardTheme: CardThemeData(
        color: c.surface1,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: c.outline.withValues(alpha: dark ? 0.9 : 1)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 56),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          textStyle: type.labelLarge?.copyWith(fontSize: 17),
          shape: RoundedRectangleBorder(borderRadius: radius16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 54),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          foregroundColor: c.text,
          side: BorderSide(color: c.outline, width: 1.2),
          textStyle: type.labelLarge,
          shape: RoundedRectangleBorder(borderRadius: radius16),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.accent,
          textStyle: type.labelLarge,
          minimumSize: const Size(48, 44),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48), foregroundColor: c.text),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          textStyle: WidgetStatePropertyAll(type.labelLarge?.copyWith(fontSize: 14)),
          side: WidgetStatePropertyAll(BorderSide(color: c.outline)),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          backgroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected) ? c.accent.withValues(alpha: dark ? 0.22 : 0.14) : c.surface1),
          foregroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected) ? (dark ? Colors.white : c.accent) : c.text),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: const StadiumBorder(),
        side: BorderSide(color: c.outline),
        backgroundColor: c.surface1,
        selectedColor: c.accent.withValues(alpha: dark ? 0.25 : 0.15),
        labelStyle: type.labelLarge?.copyWith(fontSize: 15),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      listTileTheme: ListTileThemeData(
        minVerticalPadding: 14,
        iconColor: c.muted,
        titleTextStyle: type.titleMedium,
        subtitleTextStyle: type.bodyMedium?.copyWith(color: c.muted),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : c.muted),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.accent : c.surface3),
        trackOutlineColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? c.accent : c.outline),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        side: BorderSide(color: c.muted, width: 1.6),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 6,
        activeTrackColor: c.accent,
        inactiveTrackColor: c.surface3,
        thumbColor: c.accent,
        overlayColor: c.accent.withValues(alpha: 0.15),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.accent,
        linearTrackColor: c.surface3,
        circularTrackColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface2,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c.outline)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c.accent, width: 1.6)),
        labelStyle: type.bodyMedium?.copyWith(color: c.muted),
        hintStyle: type.bodyMedium?.copyWith(color: c.muted),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface2,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        titleTextStyle: type.headlineSmall,
        contentTextStyle: type.bodyLarge?.copyWith(color: c.muted),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface1,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: c.outline,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.surface3,
        contentTextStyle: type.bodyMedium,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: c.accent,
        unselectedLabelColor: c.muted,
        indicatorColor: c.accent,
        dividerColor: c.outline,
        labelStyle: type.labelLarge,
        unselectedLabelStyle: type.labelLarge,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.surface3,
        foregroundColor: c.text,
        extendedTextStyle: type.labelLarge,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: c.surface3, borderRadius: BorderRadius.circular(8)),
        textStyle: type.bodySmall?.copyWith(color: c.text),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(builders: <TargetPlatform, PageTransitionsBuilder>{
        // Android: animates with the system predictive-back gesture.
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.fuchsia: FadeForwardsPageTransitionsBuilder(),
      }),
    );
  }

  static Color severity(Severity s) => switch (s) {
        Severity.high => bad,
        Severity.medium => warn,
        Severity.low => accent,
        Severity.info => const Color(0xFF7D8A9A),
      };

  static Color tier(Tier t) => switch (t) {
        Tier.free => const Color(0xFF7D8A9A),
        Tier.plus => accent,
        Tier.pro => pro,
      };
}

/// Theme mode the rider picked in Settings.
enum Appearance { system, dark, light }

extension AppearanceX on Appearance {
  ThemeMode get mode => switch (this) {
        Appearance.system => ThemeMode.system,
        Appearance.dark => ThemeMode.dark,
        Appearance.light => ThemeMode.light,
      };

  String get label => switch (this) {
        Appearance.system => 'Match phone',
        Appearance.dark => 'Dark',
        Appearance.light => 'Light',
      };
}

/// Tabular figures for numbers that update in place (gauges, voltages).
const tabular = [FontFeature.tabularFigures()];

bool get isMobilePlatform =>
    !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
