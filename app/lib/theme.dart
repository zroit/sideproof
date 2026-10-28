import 'package:flutter/material.dart';

/// SideProof's colours. Cobalt is always the treated half and mist the control half; green and
/// red only ever mean a result.
class Sp {
  static const porcelain = Color(0xFFF2F4F3);
  static const ink = Color(0xFF15232A);
  static const muted = Color(0xFF5D6B70);
  static const cobalt = Color(0xFF2F5BEA);
  static const mist = Color(0xFFC5CDCB);
  static const better = Color(0xFF1F8A5B);
  static const worse = Color(0xFFC2412D);

  static const night = Color(0xFF0F171B);
  static const nightPanel = Color(0xFF172228);
  static const paper = Color(0xFFE8EEEC);
  static const cobaltLight = Color(0xFF8AA4FF);
  static const mistDark = Color(0xFF3B4A4F);

  /// The treated half's colour in the current theme.
  static Color treated(BuildContext context) => Theme.of(context).colorScheme.primary;

  /// The control half's colour in the current theme.
  static Color control(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? mistDark : mist;

  static Color verdict(String? v, BuildContext context) => switch (v) {
        'better' => better,
        'worse' => worse,
        _ => Theme.of(context).colorScheme.outline,
      };
}

/// Headings are set in Bricolage Grotesque, a variable font: weight and optical size are axes.
TextStyle display(double size, {double weight = 700, Color? color, double height = 1.1}) => TextStyle(
      fontFamily: 'Bricolage',
      fontSize: size,
      height: height,
      letterSpacing: size >= 24 ? -0.6 : -0.2,
      color: color,
      fontVariations: [FontVariation('wght', weight), FontVariation('opsz', size.clamp(12, 96).toDouble())],
    );

ThemeData spTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final ink = dark ? Sp.paper : Sp.ink;
  final scheme = ColorScheme.fromSeed(seedColor: Sp.cobalt, brightness: b).copyWith(
    primary: dark ? Sp.cobaltLight : Sp.cobalt,
    onPrimary: dark ? Sp.night : Colors.white,
    surface: dark ? Sp.night : Sp.porcelain,
    onSurface: ink,
    onSurfaceVariant: dark ? const Color(0xFFA5B2B5) : Sp.muted,
    surfaceContainerLowest: dark ? Sp.nightPanel : Colors.white,
    surfaceContainerLow: dark ? Sp.nightPanel : Colors.white,
    surfaceContainer: dark ? const Color(0xFF1C2930) : const Color(0xFFE8ECEB),
    surfaceContainerHighest: dark ? const Color(0xFF243239) : const Color(0xFFE1E6E5),
    outline: dark ? const Color(0xFF7D8B8F) : const Color(0xFF8A9699),
    outlineVariant: dark ? Sp.mistDark : Sp.mist,
    error: Sp.worse,
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, scaffoldBackgroundColor: scheme.surface);
  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      headlineMedium: display(30, color: ink),
      headlineSmall: display(24, color: ink),
      titleLarge: display(20, weight: 650, color: ink),
      titleMedium: display(17, weight: 650, color: ink, height: 1.2),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: display(19, weight: 650, color: ink),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLowest,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(50),
        foregroundColor: ink,
        side: BorderSide(color: scheme.outlineVariant, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLowest,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: scheme.outlineVariant)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: scheme.outlineVariant)),
    ),
    expansionTileTheme: const ExpansionTileThemeData(shape: Border(), collapsedShape: Border()),
  );
}

/// Phones use the full width; on a desktop browser the app stays a readable column.
class Column560 extends StatelessWidget {
  const Column560({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: child));
}
