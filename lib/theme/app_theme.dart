import 'package:flutter/material.dart';

class AppPalette {
  final Color background;
  final Color surface;
  final Color surfaceRaised;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color border;
  final Color borderSoft;
  final Color buttonPrimary;
  final Color buttonPrimaryText;
  final Color buttonSecondary;
  final Color buttonSecondaryBorder;
  final Color buttonSecondaryText;
  final Color chipSelectedBackground;
  final Color chipSelectedBorder;
  final Color chipSelectedText;
  final Color chipUnselectedBackground;
  final Color chipUnselectedBorder;
  final Color chipUnselectedText;
  final Color warningSurface;
  final Color warningBorder;
  final Color warningIcon;
  final Color warningText;
  final Color danger;
  final Color link;
  final Color shimmerBase;
  final Color shimmerHighlight;
  final Color shadow;

  const AppPalette({
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.border,
    required this.borderSoft,
    required this.buttonPrimary,
    required this.buttonPrimaryText,
    required this.buttonSecondary,
    required this.buttonSecondaryBorder,
    required this.buttonSecondaryText,
    required this.chipSelectedBackground,
    required this.chipSelectedBorder,
    required this.chipSelectedText,
    required this.chipUnselectedBackground,
    required this.chipUnselectedBorder,
    required this.chipUnselectedText,
    required this.warningSurface,
    required this.warningBorder,
    required this.warningIcon,
    required this.warningText,
    required this.danger,
    required this.link,
    required this.shimmerBase,
    required this.shimmerHighlight,
    required this.shadow,
  });

  static const light = AppPalette(
    background: Color(0xfffbf9f6),
    surface: Color(0xfffbf9f6),
    surfaceRaised: Color(0xfff2efe9),
    textPrimary: Color(0xff1c1c1e),
    textSecondary: Color(0xff48484a),
    textTertiary: Color(0xff8e8e93),
    border: Color(0xffd8d4cd),
    borderSoft: Color(0x141c1c1e),
    buttonPrimary: Color(0xff1c1c1e),
    buttonPrimaryText: Color(0xffffffff),
    buttonSecondary: Color(0xfff2efe9),
    buttonSecondaryBorder: Color(0xffded8cf),
    buttonSecondaryText: Color(0xff1c1c1e),
    chipSelectedBackground: Color(0xff1c1c1e),
    chipSelectedBorder: Color(0xff1c1c1e),
    chipSelectedText: Color(0xffffffff),
    chipUnselectedBackground: Color(0xffffffff),
    chipUnselectedBorder: Color(0xffd8d4cd),
    chipUnselectedText: Color(0xff1c1c1e),
    warningSurface: Color(0xfff5f0e8),
    warningBorder: Color(0x66b8a97e),
    warningIcon: Color(0xff8a7550),
    warningText: Color(0xff6b5c3e),
    danger: Color(0xffc93b2b),
    link: Color(0xff2b6cb0),
    shimmerBase: Color(0xfff0ede9),
    shimmerHighlight: Color(0xfff7f5f2),
    shadow: Color(0x1f000000),
  );

  static const dark = AppPalette(
    background: Color(0xff0f1115),
    surface: Color(0xff13161c),
    surfaceRaised: Color(0xff1b2028),
    textPrimary: Color(0xfff4f5f7),
    textSecondary: Color(0xffc0c5cf),
    textTertiary: Color(0xff8d93a0),
    border: Color(0xff333945),
    borderSoft: Color(0x22333a46),
    buttonPrimary: Color(0xfff4f5f7),
    buttonPrimaryText: Color(0xff0f1115),
    buttonSecondary: Color(0xff1a1f27),
    buttonSecondaryBorder: Color(0xff333945),
    buttonSecondaryText: Color(0xfff4f5f7),
    chipSelectedBackground: Color(0xfff4f5f7),
    chipSelectedBorder: Color(0xfff4f5f7),
    chipSelectedText: Color(0xff0f1115),
    chipUnselectedBackground: Color(0xff161a21),
    chipUnselectedBorder: Color(0xff333945),
    chipUnselectedText: Color(0xfff4f5f7),
    warningSurface: Color(0xff2a2116),
    warningBorder: Color(0x669b7a4a),
    warningIcon: Color(0xffe0c090),
    warningText: Color(0xffe6c99e),
    danger: Color(0xffff746a),
    link: Color(0xff6ea8fe),
    shimmerBase: Color(0xff1a1f27),
    shimmerHighlight: Color(0xff262c36),
    shadow: Color(0x66000000),
  );

  static AppPalette of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AppPaletteTheme>()?.palette ??
        (theme.brightness == Brightness.dark ? dark : light);
  }
}

/// Carries the app's custom colors through Flutter's animated theme lerp.
class AppPaletteTheme extends ThemeExtension<AppPaletteTheme> {
  final AppPalette palette;

  const AppPaletteTheme(this.palette);

  @override
  AppPaletteTheme copyWith({AppPalette? palette}) =>
      AppPaletteTheme(palette ?? this.palette);

  @override
  AppPaletteTheme lerp(ThemeExtension<AppPaletteTheme>? other, double t) {
    if (other is! AppPaletteTheme) return this;
    final from = palette;
    final to = other.palette;
    Color blend(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPaletteTheme(
      AppPalette(
        background: blend(from.background, to.background),
        surface: blend(from.surface, to.surface),
        surfaceRaised: blend(from.surfaceRaised, to.surfaceRaised),
        textPrimary: blend(from.textPrimary, to.textPrimary),
        textSecondary: blend(from.textSecondary, to.textSecondary),
        textTertiary: blend(from.textTertiary, to.textTertiary),
        border: blend(from.border, to.border),
        borderSoft: blend(from.borderSoft, to.borderSoft),
        buttonPrimary: blend(from.buttonPrimary, to.buttonPrimary),
        buttonPrimaryText: blend(from.buttonPrimaryText, to.buttonPrimaryText),
        buttonSecondary: blend(from.buttonSecondary, to.buttonSecondary),
        buttonSecondaryBorder: blend(
          from.buttonSecondaryBorder,
          to.buttonSecondaryBorder,
        ),
        buttonSecondaryText: blend(
          from.buttonSecondaryText,
          to.buttonSecondaryText,
        ),
        chipSelectedBackground: blend(
          from.chipSelectedBackground,
          to.chipSelectedBackground,
        ),
        chipSelectedBorder: blend(
          from.chipSelectedBorder,
          to.chipSelectedBorder,
        ),
        chipSelectedText: blend(from.chipSelectedText, to.chipSelectedText),
        chipUnselectedBackground: blend(
          from.chipUnselectedBackground,
          to.chipUnselectedBackground,
        ),
        chipUnselectedBorder: blend(
          from.chipUnselectedBorder,
          to.chipUnselectedBorder,
        ),
        chipUnselectedText: blend(
          from.chipUnselectedText,
          to.chipUnselectedText,
        ),
        warningSurface: blend(from.warningSurface, to.warningSurface),
        warningBorder: blend(from.warningBorder, to.warningBorder),
        warningIcon: blend(from.warningIcon, to.warningIcon),
        warningText: blend(from.warningText, to.warningText),
        danger: blend(from.danger, to.danger),
        link: blend(from.link, to.link),
        shimmerBase: blend(from.shimmerBase, to.shimmerBase),
        shimmerHighlight: blend(from.shimmerHighlight, to.shimmerHighlight),
        shadow: blend(from.shadow, to.shadow),
      ),
    );
  }
}

ThemeData buildAppTheme(AppPalette palette, Brightness brightness) {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xff111625),
        brightness: brightness,
      ).copyWith(
        primary: palette.textPrimary,
        onPrimary: palette.buttonPrimaryText,
        secondary: palette.textPrimary,
        onSecondary: palette.buttonPrimaryText,
        surface: palette.surface,
        onSurface: palette.textPrimary,
        surfaceContainerHighest: palette.surfaceRaised,
        surfaceContainerHigh: palette.surfaceRaised,
        surfaceContainer: palette.surfaceRaised,
        surfaceContainerLow: palette.surface,
        surfaceContainerLowest: palette.background,
        onSurfaceVariant: palette.textSecondary,
        outline: palette.border,
        outlineVariant: palette.borderSoft,
        error: palette.danger,
        onError: Colors.white,
        shadow: palette.shadow,
      );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    extensions: [AppPaletteTheme(palette)],
    scaffoldBackgroundColor: palette.background,
    dividerColor: palette.borderSoft,
    textTheme: TextTheme(
      displaySmall: TextStyle(
        fontFamily: 'Georgia',
        fontWeight: FontWeight.w700,
        color: palette.textPrimary,
        letterSpacing: -0.5,
      ),
      bodyLarge: TextStyle(
        fontFamily: 'Georgia',
        fontSize: 17,
        height: 1.65,
        color: palette.textSecondary,
      ),
    ),
  );
}
