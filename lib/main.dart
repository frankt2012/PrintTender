import 'package:flutter/material.dart';

import 'ui/macos_theme.dart';
import 'ui/screens/dashboard_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PrinterMaintenanceApp());
}

class PrinterMaintenanceApp extends StatelessWidget {
  const PrinterMaintenanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PrintTender',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: _themeFor(Brightness.light),
      darkTheme: _themeFor(Brightness.dark),
      builder: isMacOS ? _windowChrome : null,
      home: const DashboardScreen(),
    );
  }

  /// macOS gets its own AppKit-flavoured theme; Android keeps the Material one.
  ThemeData _themeFor(Brightness brightness) =>
      isMacOS ? buildMacTheme(brightness) : _buildTheme(brightness);

  /// The macOS runner gives the window a transparent title bar over a full-size
  /// content view, so the traffic-light buttons float above the app. This
  /// reserves the strip they sit in and paints it the toolbar colour, which
  /// makes the title bar and the toolbar below read as a single surface.
  Widget _windowChrome(BuildContext context, Widget? child) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.only(top: 28),
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2F6FED),
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      scaffoldBackgroundColor: scheme.surfaceContainerLow,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        elevation: 0.25,
        scrolledUnderElevation: 0.25,
        centerTitle: false,
        toolbarHeight: 38,
        titleTextStyle: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
            width: 0.5,
          ),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        dense: true,
        visualDensity: VisualDensity.compact,
        minVerticalPadding: 6,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.4),
        space: 1,
        thickness: 0.5,
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }
}
