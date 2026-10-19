import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide isMacOS;
import 'package:printer_maintenance/ui/mac_controls.dart';
import 'package:printer_maintenance/ui/mac_sidebar.dart';
import 'package:printer_maintenance/ui/macos_theme.dart';
import 'package:printer_maintenance/ui/routes.dart';

/// The macOS look is chosen from [defaultTargetPlatform], so overriding it is
/// enough to exercise the desktop branch from a headless test.
///
/// The override has to be undone inside the test body: the test binding checks
/// for changed foundation debug variables before tear-down callbacks run.
Future<void> onMac(Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  test('the macOS theme is built around the system font and accent', () async {
    await onMac(() async {
      for (final brightness in Brightness.values) {
        final theme = buildMacTheme(brightness);
        expect(theme.colorScheme.brightness, brightness);
        expect(theme.textTheme.bodyMedium?.fontFamily, '.AppleSystemUIFont');
        expect(theme.colorScheme.primary, MacColors.accent);
        expect(theme.splashFactory, NoSplash.splashFactory);
      }
    });
  });

  test('the platform helpers answer for the overridden platform', () async {
    await onMac(() async {
      expect(isMacOS, isTrue);
      expect(isDesktop, isTrue);
    });
  });

  testWidgets('pushPage lays a desktop page out as a sheet', (tester) async {
    await onMac(() async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildMacTheme(Brightness.light),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    pushPage(
                      (_) => Scaffold(
                        appBar: AppBar(title: const Text('Library')),
                        body: const Center(child: Text('sheet body')),
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('sheet body'), findsOneWidget);
      // The automatic back button still gives the sheet a way out.
      expect(find.byType(BackButton), findsOneWidget);

      // The panel is inset from the window rather than filling it.
      final panel = tester.getRect(find.byKey(macSheetPanelKey));
      final screen = tester.getRect(find.byType(Scaffold).first);
      expect(panel.width, lessThanOrEqualTo(screen.width));
      expect(panel.left, greaterThan(screen.left));
      expect(panel.top, greaterThan(screen.top));
      expect(panel.bottom, lessThan(screen.bottom));
    });
  });

  testWidgets('the sheet button bar cancels, saves and sits on the right', (
    tester,
  ) async {
    var cancelled = false;
    var saved = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildMacTheme(Brightness.light),
        home: Scaffold(
          bottomNavigationBar: MacSheetButtonBar(
            onCancel: () => cancelled = true,
            onDone: () => saved = true,
            doneLabel: 'Save',
          ),
        ),
      ),
    );

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    expect(cancelled, isTrue);
    expect(saved, isTrue);

    // AppKit orders a sheet's buttons Cancel-then-default, along the bottom
    // right edge.
    final cancel = tester.getRect(find.widgetWithText(TextButton, 'Cancel'));
    final done = tester.getRect(find.widgetWithText(FilledButton, 'Save'));
    expect(cancel.right, lessThan(done.left));
    expect(done.right, closeTo(800 - 16, 1));
  });

  testWidgets('a busy sheet button bar refuses both actions', (tester) async {
    var cancelled = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildMacTheme(Brightness.light),
        home: Scaffold(
          bottomNavigationBar: MacSheetButtonBar(
            onCancel: () => cancelled = true,
            onDone: () {},
            busy: true,
          ),
        ),
      ),
    );

    expect(find.text('Done'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    expect(cancelled, isFalse);
  });

  testWidgets('the sidebar highlights exactly one row', (tester) async {
    await onMac(() async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildMacTheme(Brightness.light),
          home: Scaffold(
            body: MacSidebar(
              children: <Widget>[
                MacSidebarSection(
                  title: 'Printers',
                  children: <Widget>[
                    MacSidebarTile(
                      label: 'All Printers',
                      icon: Icons.print_outlined,
                      selected: false,
                      trailing: const MacSidebarBadge(count: 2),
                    ),
                    MacSidebarTile(
                      label: 'Voron',
                      icon: Icons.print_outlined,
                      selected: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('PRINTERS'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);

      final tiles = tester.widgetList<MacSidebarTile>(
        find.byType(MacSidebarTile),
      );
      expect(tiles.where((tile) => tile.selected), hasLength(1));
    });
  });
}
