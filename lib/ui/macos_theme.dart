import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// True when the running app is a macOS build.
///
/// This asks Flutter for the target platform rather than `dart:io`, so widget
/// tests and any tooling that overrides the platform see the same answer the
/// widgets do.
bool get isMacOS => defaultTargetPlatform == TargetPlatform.macOS;

/// The fill behind the small chips the macOS printer pane is built from.
///
/// Android draws those as a tint on a large Material surface, and does here
/// too. On macOS they sit on the chrome: the dark chrome of #323232 takes the
/// same tint, but the light one is #ECECEC, and a tint two steps off that reads
/// as no chip at all. So in light mode the chip is a white plate — the surface
/// the cards around it already use.
Color macChipFill(ThemeData theme) {
  final tint = theme.colorScheme.surfaceContainerHighest.withValues(
    alpha: 0.55,
  );
  if (!isMacOS) return tint;
  return theme.brightness == Brightness.dark ? tint : theme.colorScheme.surface;
}

/// True on any platform with a pointer, a keyboard and a big window — the
/// places where a dense, desktop-shaped layout makes sense.
bool get isDesktop =>
    isMacOS ||
    defaultTargetPlatform == TargetPlatform.windows ||
    defaultTargetPlatform == TargetPlatform.linux;

/// The system colours macOS uses, taken from the Human Interface Guidelines'
/// "System colors" table and `NSColor`'s semantic values.
abstract final class MacColors {
  /// `NSColor.systemBlue`, which is also the default accent colour.
  static const Color accent = Color(0xFF007AFF);

  /// `NSColor.windowBackgroundColor` — the chrome behind toolbars and sidebars.
  static const Color windowLight = Color(0xFFECECEC);
  static const Color windowDark = Color(0xFF323232);

  /// `NSColor.controlBackgroundColor` — the well lists and forms sit in.
  static const Color contentLight = Color(0xFFFFFFFF);
  static const Color contentDark = Color(0xFF1E1E1E);

  static const Color separatorLight = Color(0xFFD7D7D7);
  static const Color separatorDark = Color(0xFF3F3F3F);

  static const Color labelLight = Color(0xFF1D1D1F);
  static const Color labelDark = Color(0xFFF5F5F7);
  static const Color secondaryLabelLight = Color(0xFF6E6E73);
  static const Color secondaryLabelDark = Color(0xFF9A9A9E);

  /// The status colours behind the due badges.
  ///
  /// AppKit's `systemRed`, `systemOrange` and `systemGreen` are the ones above
  /// in each appearance — the `…Light` values rather than these in light mode,
  /// because these were drawn for a dark window. On white they measure 3.6:1,
  /// 2.2:1 and 2.2:1, and these carry the small badge label, which wants 4.5:1.
  /// The light values are Apple's increased-contrast ones, with the green taken
  /// a shade darker than `#248A3D` so it also reads on the grey chrome.
  static const Color red = Color(0xFFFF3B30);
  static const Color orange = Color(0xFFFF9500);
  static const Color green = Color(0xFF34C759);
  static const Color gray = Color(0xFF8E8E93);

  static const Color redLight = Color(0xFFD70015);
  static const Color orangeLight = Color(0xFFC93400);
  static const Color greenLight = Color(0xFF1F7A33);

  static Color redFor(Brightness brightness) =>
      brightness == Brightness.dark ? red : redLight;

  static Color orangeFor(Brightness brightness) =>
      brightness == Brightness.dark ? orange : orangeLight;

  static Color greenFor(Brightness brightness) =>
      brightness == Brightness.dark ? green : greenLight;
}

/// A Material theme dressed to look like AppKit: the system font, the system
/// accent, hairline separators and flat, squared-off controls.
///
/// Only used on macOS. Android keeps the stock Material theming, where the
/// rounded, elevated look is what users expect.
ThemeData buildMacTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final window = dark ? MacColors.windowDark : MacColors.windowLight;
  final content = dark ? MacColors.contentDark : MacColors.contentLight;
  final separator = dark ? MacColors.separatorDark : MacColors.separatorLight;
  final label = dark ? MacColors.labelDark : MacColors.labelLight;
  final secondary =
      dark ? MacColors.secondaryLabelDark : MacColors.secondaryLabelLight;
  final fieldFill = dark ? const Color(0xFF2C2C2E) : content;

  final scheme = ColorScheme.fromSeed(
    seedColor: MacColors.accent,
    brightness: brightness,
  ).copyWith(
    primary: MacColors.accent,
    onPrimary: Colors.white,
    surface: content,
    onSurface: label,
    onSurfaceVariant: secondary,
    outline: separator,
    outlineVariant: separator,
    error: dark ? MacColors.red : MacColors.redLight,
    onError: Colors.white,
    surfaceContainerLowest: content,
    surfaceContainerLow: content,
    surfaceContainer: window,
    surfaceContainerHigh: window,
    surfaceContainerHighest:
        dark ? const Color(0xFF3A3A3C) : const Color(0xFFE8E8EA),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    // `.AppleSystemUIFont` resolves to San Francisco, the same face AppKit
    // draws every control in.
    fontFamily: '.AppleSystemUIFont',
    fontFamilyFallback: const <String>['SF Pro Text', 'Helvetica Neue'],
    // AppKit has no ink ripples; a plain hover tint is the whole state model.
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: label.withValues(alpha: 0.06),
    scaffoldBackgroundColor: window,
    visualDensity: VisualDensity.compact,
    appBarTheme: AppBarTheme(
      backgroundColor: window,
      foregroundColor: label,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      toolbarHeight: 52,
      iconTheme: const IconThemeData(size: 18),
      titleTextStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: label,
      ),
      // A toolbar on macOS is separated from the content by a single hairline.
      shape: Border(bottom: BorderSide(color: separator)),
    ),
    cardTheme: CardThemeData(
      color: content,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: separator),
      ),
    ),
    dividerTheme: DividerThemeData(color: separator, thickness: 1, space: 1),
    listTileTheme: ListTileThemeData(
      dense: true,
      visualDensity: VisualDensity.compact,
      minVerticalPadding: 6,
      iconColor: secondary,
      textColor: label,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: MacColors.accent,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 28),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: label,
        backgroundColor: dark ? const Color(0xFF3A3A3C) : content,
        minimumSize: const Size(0, 28),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        side: BorderSide(color: separator),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: MacColors.accent,
        minimumSize: const Size(44, 26),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: label,
        minimumSize: const Size(28, 28),
        padding: const EdgeInsets.all(5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: content,
      surfaceTintColor: Colors.transparent,
      elevation: 20,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      titleTextStyle: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: label,
      ),
      contentTextStyle: TextStyle(fontSize: 13, color: label),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? const Color(0xFF48484A) : content,
      contentTextStyle: TextStyle(fontSize: 13, color: label),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      elevation: 8,
      insetPadding: const EdgeInsets.all(16),
    ),
    progressIndicatorTheme:
        const ProgressIndicatorThemeData(color: MacColors.accent),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll<double>(9),
      radius: const Radius.circular(5),
      crossAxisMargin: 2,
      thumbColor: WidgetStatePropertyAll<Color>(label.withValues(alpha: 0.28)),
      trackColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 500),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF5A5A5E) : const Color(0xFFF4F4F6),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: separator),
      ),
      textStyle: TextStyle(fontSize: 11, color: label),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: fieldFill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: separator),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: separator),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: MacColors.accent, width: 2),
      ),
      labelStyle: TextStyle(fontSize: 12, color: secondary),
      helperStyle: TextStyle(fontSize: 11, color: secondary),
    ),
  );
}
