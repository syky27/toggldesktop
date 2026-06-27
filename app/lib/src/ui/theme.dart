import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Redtick design tokens & theme (design comp: Light = "Slate", Dark = "Carbon").
///
/// Build everything theme-agnostic: read colors from `Theme.of(context)` or
/// `Theme.of(context).extension<RedtickTokens>()!`, never hard-code a hex except
/// the fixed brand red. (Per-project accent colours are derived deterministically
/// from the project id — see `src/util/project_color.dart`.)

// Brand
const kBrandRed = Color(0xFFA11C1C); // logo tile / light accent
const kBrandRedBright = Color(0xFFFF4A3D); // dark-mode accent (glow)

// Beveled app-icon tile gradient (white hourglass sits on this).
const kBrandTileTop = Color(0xFFC0302A);
const kBrandTileBottom = Color(0xFF8C1513);

/// Bespoke tokens the design uses that M3's [ColorScheme] doesn't cover.
@immutable
class RedtickTokens extends ThemeExtension<RedtickTokens> {
  const RedtickTokens({
    required this.sidebar,
    required this.hairline,
    required this.faint,
    required this.accent,
    required this.accentSoft,
  });

  final Color sidebar;
  final Color hairline;
  final Color faint;
  final Color accent;
  final Color accentSoft;

  /// The beveled brand tile gradient (login logo / rail header / app icon).
  Gradient get brandTile => const RadialGradient(
        center: Alignment(-0.4, -0.5),
        radius: 1.1,
        colors: [kBrandTileTop, kBrandTileBottom],
        stops: [0.0, 0.72],
      );

  static const light = RedtickTokens(
    sidebar: Color(0xFFFBFBFC),
    hairline: Color(0xFFEFF0F3),
    faint: Color(0xFFA0A6B0),
    accent: kBrandRed,
    accentSoft: Color(0xFFFBEBEA),
  );

  static const dark = RedtickTokens(
    sidebar: Color(0xFF161619),
    hairline: Color(0xFF232328),
    faint: Color(0xFF5E5F68),
    accent: kBrandRedBright,
    accentSoft: Color(0xFF2A1A1B),
  );

  @override
  RedtickTokens copyWith({
    Color? sidebar,
    Color? hairline,
    Color? faint,
    Color? accent,
    Color? accentSoft,
  }) =>
      RedtickTokens(
        sidebar: sidebar ?? this.sidebar,
        hairline: hairline ?? this.hairline,
        faint: faint ?? this.faint,
        accent: accent ?? this.accent,
        accentSoft: accentSoft ?? this.accentSoft,
      );

  @override
  RedtickTokens lerp(ThemeExtension<RedtickTokens>? other, double t) {
    if (other is! RedtickTokens) return this;
    return RedtickTokens(
      sidebar: Color.lerp(sidebar, other.sidebar, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      faint: Color.lerp(faint, other.faint, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
    );
  }
}

class RedtickTheme {
  /// Kept for back-compat with widgets referencing the old accent.
  static const Color brand = kBrandRed;

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  /// Monospace, tabular-figure style for every duration/time label.
  static TextStyle mono({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
  }) =>
      GoogleFonts.jetBrainsMono(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        letterSpacing: letterSpacing,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final tokens = dark ? RedtickTokens.dark : RedtickTokens.light;

    final bg = dark ? const Color(0xFF121214) : const Color(0xFFF6F7F9);
    final surface = dark ? const Color(0xFF1A1A1E) : Colors.white;
    final border = dark ? const Color(0xFF2A2A30) : const Color(0xFFE7E9ED);
    final text = dark ? const Color(0xFFECEDEF) : const Color(0xFF171A1F);
    final muted = dark ? const Color(0xFF8A8B94) : const Color(0xFF717784);
    final accent = tokens.accent;

    final scheme = ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: Colors.white,
      primaryContainer: tokens.accentSoft,
      onPrimaryContainer: accent,
      secondary: accent,
      onSecondary: Colors.white,
      surface: surface,
      onSurface: text,
      surfaceContainerHighest: dark
          ? const Color(0xFF202024)
          : const Color(0xFFF1F2F5),
      onSurfaceVariant: muted,
      outline: border,
      outlineVariant: tokens.hairline,
      error: const Color(0xFFD64545),
      onError: Colors.white,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      visualDensity: VisualDensity.standard,
    );

    final textTheme = GoogleFonts.manropeTextTheme(base.textTheme)
        .apply(bodyColor: text, displayColor: text);

    return base.copyWith(
      textTheme: textTheme,
      dividerTheme: DividerThemeData(
          color: tokens.hairline, thickness: 1, space: 1),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(13),
          side: BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xFF202024) : const Color(0xFFF4F5F7),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
        labelStyle: TextStyle(color: muted),
        hintStyle: TextStyle(color: tokens.faint),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: tokens.sidebar,
        indicatorColor: tokens.accentSoft,
        selectedIconTheme: IconThemeData(color: accent),
        unselectedIconTheme: IconThemeData(color: muted),
        selectedLabelTextStyle:
            textTheme.labelMedium?.copyWith(color: accent, fontWeight: FontWeight.w700),
        unselectedLabelTextStyle: textTheme.labelMedium?.copyWith(color: muted),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: tokens.sidebar,
        indicatorColor: tokens.accentSoft,
        labelTextStyle: WidgetStatePropertyAll(
            textTheme.labelMedium?.copyWith(color: muted)),
        iconTheme: WidgetStateProperty.resolveWith((s) =>
            IconThemeData(color: s.contains(WidgetState.selected) ? accent : muted)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? accent : border),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      extensions: [tokens],
    );
  }
}
