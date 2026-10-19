import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide isMacOS;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:printer_maintenance/data/database.dart';
import 'package:printer_maintenance/main.dart';
import 'package:printer_maintenance/services/due_status.dart';
import 'package:printer_maintenance/ui/macos_theme.dart';
import 'package:printer_maintenance/ui/widgets.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactoryFfiNoIsolate, inMemoryDatabasePath;

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}

/// The WCAG contrast ratio between two opaque colours, which is what "can I
/// read this" reduces to.
///
/// 4.5:1 is AA for the small text these are drawn as; 7:1 is AAA and what body
/// text should reach.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('printer_appearance_test');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await AppDatabase.resetForTesting();
    AppDatabase.factoryOverride = databaseFactoryFfiNoIsolate;
    AppDatabase.pathOverride = inMemoryDatabasePath;
  });

  tearDown(() async {
    await AppDatabase.resetForTesting();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  for (final brightness in Brightness.values) {
    final name = brightness == Brightness.dark ? 'dark' : 'light';

    test('the $name macOS theme keeps its text legible', () {
      final theme = buildMacTheme(brightness);
      final scheme = theme.colorScheme;
      final card = scheme.surface;
      final chrome = scheme.surfaceContainer;

      // macOS text: labels on the white cards and on the grey chrome.
      expect(contrast(scheme.onSurface, card), greaterThanOrEqualTo(7));
      expect(contrast(scheme.onSurface, chrome), greaterThanOrEqualTo(7));
      expect(contrast(scheme.onSurfaceVariant, card), greaterThanOrEqualTo(4.5));
      expect(contrast(scheme.onSurfaceVariant, chrome), greaterThanOrEqualTo(4));

      // Every colour a due badge or progress bar carries text or meaning in,
      // including the "No schedule" case.
      final status = <String, Color>{
        'overdue': scheme.error,
        'due soon': MacColors.orangeFor(brightness),
        'on track': MacColors.greenFor(brightness),
        'no schedule': scheme.onSurfaceVariant,
      };
      status.forEach((label, color) {
        expect(
          contrast(color, card),
          greaterThanOrEqualTo(4.5),
          reason: '$label on a card in $name mode',
        );
        expect(
          contrast(color, chrome),
          greaterThanOrEqualTo(3.5),
          reason: '$label on the chrome in $name mode',
        );
      });
    });
  }

  test('the two appearances really do differ', () {
    expect(MacColors.windowLight, isNot(MacColors.windowDark));
    expect(MacColors.contentLight, isNot(MacColors.contentDark));
    expect(MacColors.orangeFor(Brightness.light), isNot(MacColors.orange));
    expect(MacColors.greenFor(Brightness.light), isNot(MacColors.green));
    expect(MacColors.redFor(Brightness.light), isNot(MacColors.red));

    final light = buildMacTheme(Brightness.light);
    final dark = buildMacTheme(Brightness.dark);
    expect(light.colorScheme.surface, isNot(dark.colorScheme.surface));
    expect(light.colorScheme.onSurface, isNot(dark.colorScheme.onSurface));
    expect(light.inputDecorationTheme.fillColor, isNot(MacColors.contentDark));
  });

  test('the chips read as plates on the light chrome', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final light = buildMacTheme(Brightness.light);
    final chrome = light.colorScheme.surfaceContainer;

    // What the chips used to be tinted with in every appearance: #EAEAEB on
    // #ECECEC, which is a chip you cannot see.
    final tint = light.colorScheme.surfaceContainerHighest.withValues(
      alpha: 0.55,
    );
    expect(contrast(Color.alphaBlend(tint, chrome), chrome), lessThan(1.05));
    expect(contrast(Color.alphaBlend(macChipFill(light), chrome), chrome), greaterThan(1.15));

    // The dark chrome has the headroom for that tint, and keeps it.
    final dark = buildMacTheme(Brightness.dark);
    expect(
      macChipFill(dark),
      dark.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
    );
  });

  testWidgets('the due colours follow the appearance', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final seen = <Brightness, List<Color>>{};
      for (final brightness in Brightness.values) {
        late Color overdue;
        late Color dueSoon;
        late Color ok;
        late Color unscheduled;
        await tester.pumpWidget(
          MaterialApp(
            // A fresh key per appearance: without it the Builder would keep
            // whatever it computed the first time round.
            key: ValueKey<Brightness>(brightness),
            theme: buildMacTheme(brightness),
            home: Builder(
              builder: (context) {
                overdue = dueColor(context, DueLevel.overdue);
                dueSoon = dueColor(context, DueLevel.dueSoon);
                ok = dueColor(context, DueLevel.ok);
                unscheduled = dueColor(context, DueLevel.unscheduled);
                return const SizedBox();
              },
            ),
          ),
        );
        expect(
          overdue,
          brightness == Brightness.dark ? MacColors.red : MacColors.redLight,
        );
        // A "No schedule" badge is a label, not a hairline.
        expect(unscheduled, buildMacTheme(brightness).colorScheme.onSurfaceVariant);
        seen[brightness] = <Color>[overdue, dueSoon, ok, unscheduled];
      }

      expect(seen[Brightness.light], isNot(seen[Brightness.dark]));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('the app hands Material a light and a dark theme', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await pumpTest(tester);
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));

      expect(app.themeMode, ThemeMode.system);
      expect(app.theme!.brightness, Brightness.light);
      expect(app.darkTheme!.brightness, Brightness.dark);

      // Both appearances are the AppKit-flavoured theme on macOS, not the
      // Material one Android gets.
      expect(app.theme!.scaffoldBackgroundColor, MacColors.windowLight);
      expect(app.darkTheme!.scaffoldBackgroundColor, MacColors.windowDark);
      expect(app.theme!.textTheme.bodyMedium?.fontFamily, '.AppleSystemUIFont');
      expect(
        app.darkTheme!.textTheme.bodyMedium?.fontFamily,
        '.AppleSystemUIFont',
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Android is left the stock Material theme in both', (
    tester,
  ) async {
    await pumpTest(tester);
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));

    expect(app.theme!.brightness, Brightness.light);
    expect(app.darkTheme!.brightness, Brightness.dark);
    expect(app.theme!.scaffoldBackgroundColor, isNot(MacColors.windowLight));
    expect(app.darkTheme!.scaffoldBackgroundColor, isNot(MacColors.windowDark));
    expect(
      app.theme!.textTheme.bodyMedium?.fontFamily,
      isNot('.AppleSystemUIFont'),
    );
  });
}

/// Pumps the app itself and waits for the first frame after its data loads.
Future<void> pumpTest(WidgetTester tester) async {
  await tester.pumpWidget(const PrinterMaintenanceApp());
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) return;
  }
}
