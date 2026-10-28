import 'package:flutter/material.dart';

/// SideProof's colours: a cream ground, rose for the treated half, pearl chrome for what
/// matters. Green, amber and red only ever mean a result.
class Sp {
  static const cream = Color(0xFFFBF6F1);
  static const panel = Color(0xFFFFFFFF);
  static const sunk = Color(0xFFF6EFEB);
  static const ink = Color(0xFF2B1E25);
  static const muted = Color(0xFF74636B);
  static const line = Color(0xFFEFE1DA);
  static const rose = Color(0xFFE3507E);
  static const lilac = Color(0xFFA866E8);
  static const mint = Color(0xFF3BB8A3);
  static const mist = Color(0xFFD9CFC7);
  static const outline = Color(0xFF9A8A90);
  static const better = Color(0xFF12734F), betterBg = Color(0xFFDDF3E9);
  static const unclear = Color(0xFF93550C), unclearBg = Color(0xFFFDEBD6);
  static const worse = Color(0xFFB23A2E), worseBg = Color(0xFFFBE1DC);

  /// The call to action: pink to rose to lilac.
  static const cta = LinearGradient(colors: [Color(0xFFF48FB1), Color(0xFFE3507E), Color(0xFFB467E0)], stops: [0, 0.45, 1]);

  /// Pearl chrome, for borders around what matters.
  static const chrome = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF9C9DA), Color(0xFFE9DDFB), Color(0xFFCFF2EA), Color(0xFFFBE3C8)],
    stops: [0, 0.45, 0.75, 1],
  );

  /// Rose to lilac to mint, for a word that should shine.
  static const shimmer = LinearGradient(colors: [Color(0xFFE3507E), Color(0xFFA866E8), Color(0xFF3BB8A3)]);

  static Color treated(BuildContext context) => rose;
  static Color control(BuildContext context) => mist;

  static Color verdict(String? v, BuildContext context) => switch (v) {
        'better' => better,
        'worse' => worse,
        'unclear' => unclear,
        _ => outline,
      };

  static Color verdictBg(String? v) => switch (v) {
        'better' => betterBg,
        'worse' => worseBg,
        'unclear' => unclearBg,
        _ => sunk,
      };
}

/// Headings: Instrument Serif, regular or italic.
TextStyle display(double size, {Color? color, double height = 1.05, bool italic = false}) => TextStyle(
      fontFamily: 'InstrumentSerif',
      fontSize: size,
      height: height,
      letterSpacing: size >= 28 ? -0.4 : 0,
      color: color,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
    );

/// Body text: Manrope, a variable font, so the weight is an axis.
TextStyle body(double size, {double weight = 500, Color? color, double? height}) => TextStyle(
      fontFamily: 'Manrope',
      fontSize: size,
      height: height,
      color: color,
      fontWeight: FontWeight.values[((weight / 100).round() - 1).clamp(0, 8)],
      fontVariations: [FontVariation('wght', weight)],
    );

ThemeData spTheme(Brightness _) {
  final scheme = ColorScheme.fromSeed(seedColor: Sp.rose, brightness: Brightness.light).copyWith(
    primary: Sp.rose,
    onPrimary: Colors.white,
    secondary: Sp.lilac,
    surface: Sp.cream,
    onSurface: Sp.ink,
    onSurfaceVariant: Sp.muted,
    surfaceContainerLowest: Sp.panel,
    surfaceContainerLow: Sp.panel,
    surfaceContainer: Sp.sunk,
    surfaceContainerHighest: const Color(0xFFF1E6E1),
    outline: Sp.outline,
    outlineVariant: Sp.line,
    error: Sp.worse,
  );
  final text = TextTheme(
    displaySmall: display(40, color: Sp.ink),
    headlineLarge: display(40, color: Sp.ink),
    headlineMedium: display(36, color: Sp.ink),
    headlineSmall: display(30, color: Sp.ink),
    titleLarge: display(26, color: Sp.ink, height: 1.1),
    titleMedium: body(16, weight: 700, color: Sp.ink, height: 1.3),
    titleSmall: body(14, weight: 700, color: Sp.ink),
    bodyLarge: body(16, color: Sp.ink, height: 1.5),
    bodyMedium: body(14.5, color: Sp.ink, height: 1.45),
    bodySmall: body(12.5, color: Sp.muted, height: 1.4),
    labelLarge: body(14, weight: 700, color: Sp.ink),
    labelMedium: body(12.5, weight: 600, color: Sp.ink),
    labelSmall: body(11.5, weight: 600, color: Sp.muted),
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, scaffoldBackgroundColor: Sp.cream, fontFamily: 'Manrope', textTheme: text);
  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: Sp.cream,
      foregroundColor: Sp.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: display(26, color: Sp.ink),
    ),
    cardTheme: CardThemeData(color: Sp.panel, elevation: 0, margin: const EdgeInsets.symmetric(vertical: 6), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        backgroundColor: Sp.rose,
        shape: const StadiumBorder(),
        textStyle: body(16, weight: 800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        foregroundColor: Sp.ink,
        backgroundColor: Sp.panel,
        side: const BorderSide(color: Sp.line, width: 1.5),
        shape: const StadiumBorder(),
        textStyle: body(15, weight: 700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: Sp.rose, textStyle: body(15, weight: 700))),
    chipTheme: ChipThemeData(
      backgroundColor: Sp.panel,
      selectedColor: const Color(0xFFFBE3EC),
      labelStyle: body(13.5, weight: 700, color: Sp.ink),
      side: const BorderSide(color: Sp.line),
      shape: const StadiumBorder(),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: Sp.sunk,
        selectedBackgroundColor: Sp.panel,
        foregroundColor: Sp.muted,
        selectedForegroundColor: Sp.ink,
        side: BorderSide.none,
        textStyle: body(13.5, weight: 700),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Sp.panel,
      labelStyle: body(15, weight: 600, color: Sp.muted),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: Sp.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: Sp.line, width: 1.5)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: Sp.rose, width: 2)),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: Sp.rose, linearTrackColor: Sp.sunk),
    expansionTileTheme: const ExpansionTileThemeData(shape: Border(), collapsedShape: Border()),
  );
}

/// The main call to action: a pill in the pink-to-lilac gradient.
class GradientButton extends StatelessWidget {
  const GradientButton({super.key, required this.label, this.onPressed, this.icon});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: Sp.cta,
          borderRadius: BorderRadius.circular(99),
          boxShadow: const [BoxShadow(color: Color(0x66E3507E), blurRadius: 24, offset: Offset(0, 10), spreadRadius: -10)],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(99),
            onTap: onPressed,
            child: SizedBox(
              height: 56,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                if (icon != null) ...[Icon(icon, color: Colors.white, size: 20), const SizedBox(width: 8)],
                Text(label, style: body(16, weight: 800, color: Colors.white)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// A panel with a pearl-chrome border.
class ChromeBox extends StatelessWidget {
  const ChromeBox({super.key, required this.child, this.padding = const EdgeInsets.all(20), this.radius = 28});
  final Widget child;
  final EdgeInsets padding;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(gradient: Sp.chrome, borderRadius: BorderRadius.circular(radius + 2)),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(color: const Color(0xFFFFFDFB), borderRadius: BorderRadius.circular(radius)),
          child: child,
        ),
      );
}

/// Text painted in the shimmer gradient.
class ShimmerText extends StatelessWidget {
  const ShimmerText(this.text, {super.key, required this.style});
  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (r) => Sp.shimmer.createShader(r),
        child: Text(text, style: style),
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
