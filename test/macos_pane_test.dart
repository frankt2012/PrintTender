import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide isMacOS;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:printer_maintenance/data/database.dart';
import 'package:printer_maintenance/data/models.dart';
import 'package:printer_maintenance/data/repositories.dart';
import 'package:printer_maintenance/ui/mac_controls.dart';
import 'package:printer_maintenance/ui/macos_theme.dart';
import 'package:printer_maintenance/ui/screens/printer_detail_screen.dart';
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

/// The sidebar pane is chosen from [defaultTargetPlatform], so overriding it is
/// the whole of the setup.
Future<void> onMac(Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

/// The size the app's window works out to on the display it was developed on,
/// minus the 216px sidebar.
const Size paneSize = Size(967, 712);

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('printer_pane_test');
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

  /// A printer with enough going on that the pane header shows every chip.
  Future<int> seedPrinter() async {
    final printers = PrinterRepository();
    final tasks = TaskRepository();
    final id = await printers.insert(
      Printer(
        name: 'Voron 2.4',
        manufacturer: 'LDO',
        model: '2.4 350',
        serialNumber: 'V2-0123',
        purchaseDate: DateTime(2024, 3, 14),
        totalPrintHours: 812.5,
        nozzleSize: '0.4 mm',
        nozzleType: 'CHT brass',
        buildPlate: 'Textured G10',
        notes: 'Enclosed, ABS only.',
        createdAt: DateTime(2024, 3, 14),
      ),
    );
    final library = await tasks.definitions();
    for (final task in library.take(4)) {
      await tasks.assign(
        printerId: id,
        taskId: task.id!,
        intervalHours: task.intervalHours,
        intervalDays: task.intervalDays,
        intervalMonths: task.intervalMonths,
      );
    }
    return id;
  }

  /// Pumps a screen and waits until [ready] is on screen, which for the pane is
  /// the moment it has finished loading out of SQLite.
  Future<void> pumpScreen(
    WidgetTester tester,
    Widget screen,
    Finder ready,
  ) async {
    tester.view.physicalSize = paneSize;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(theme: buildMacTheme(Brightness.light), home: screen),
    );

    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (ready.evaluate().isNotEmpty) return;
    }
    fail('the screen never showed $ready');
  }

  Future<void> pumpPane(WidgetTester tester, int printerId) => pumpScreen(
        tester,
        Scaffold(
          body: PrinterDetailScreen(printerId: printerId, embedded: true),
        ),
        find.byKey(macPaneHeaderKey),
      );

  testWidgets('the pane header costs a fraction of the screen it replaces', (
    tester,
  ) async {
    await onMac(() async {
      final printerId = await seedPrinter();

      // What the pushed screen spends above its list: the header card plus a
      // TabBar of its own.
      await pumpScreen(
        tester,
        PrinterDetailScreen(printerId: printerId),
        find.byType(TabBar),
      );
      final stacked =
          tester.getRect(find.byType(TabBar)).bottom -
          tester.getRect(find.byType(AppBar)).bottom;

      // What the sidebar pane spends instead: one bar.
      await pumpPane(tester, printerId);
      final compact = tester.getRect(find.byKey(macPaneHeaderKey)).height;

      expect(compact, lessThan(stacked * 0.6));

      // The list is what the reclaimed height was for.
      final list = tester.getRect(find.byType(CustomScrollView));
      expect(list.height, greaterThan(paneSize.height * 0.75));
    });
  });

  testWidgets('the pane switches between schedule and history', (tester) async {
    await onMac(() async {
      final printerId = await seedPrinter();
      await pumpPane(tester, printerId);

      // A real TabBar would be a second switch, and a second 48px bar.
      expect(find.byType(TabBar), findsNothing);
      expect(find.byType(MacSegmentedControl<int>), findsOneWidget);
      expect(find.text('Assign a maintenance task'), findsOneWidget);

      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();

      expect(find.text('Assign a maintenance task'), findsNothing);
      expect(find.text('No history yet'), findsOneWidget);

      await tester.tap(find.text('Schedule'));
      await tester.pumpAndSettle();
      expect(find.text('Assign a maintenance task'), findsOneWidget);
    });
  });

  testWidgets('the header bar does not overflow a narrow window', (
    tester,
  ) async {
    await onMac(() async {
      final printerId = await seedPrinter();
      // The smallest window the app allows, less the 216px sidebar.
      tester.view.physicalSize = const Size(684, 560);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildMacTheme(Brightness.light),
          home: Scaffold(
            body: PrinterDetailScreen(printerId: printerId, embedded: true),
          ),
        ),
      );
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (find.byKey(macPaneHeaderKey).evaluate().isNotEmpty) break;
      }

      // The name column is the part that gives way; the chips wrap.
      expect(tester.takeException(), isNull);
      expect(find.byKey(macPaneHeaderKey), findsOneWidget);
    });
  });

  testWidgets('the pane header shows every reading on one bar', (tester) async {
    await onMac(() async {
      final printerId = await seedPrinter();
      await pumpPane(tester, printerId);

      expect(find.text('812.5 h'), findsOneWidget);
      expect(find.text('print hours'), findsOneWidget);
      expect(find.text('overdue'), findsOneWidget);
      expect(find.text('due soon'), findsOneWidget);
      expect(find.text('Nozzle: '), findsOneWidget);
      expect(find.text('0.4 mm CHT brass'), findsOneWidget);
      expect(find.text('Textured G10'), findsOneWidget);
      expect(find.text('V2-0123'), findsOneWidget);
      expect(find.text('Enclosed, ABS only.'), findsOneWidget);

      expect(find.text('Nozzle: '), findsOneWidget);
      expect(find.text('0.4 mm CHT brass'), findsOneWidget);
      expect(find.text('Textured G10'), findsOneWidget);
      expect(find.text('Enclosed, ABS only.'), findsOneWidget);

      // Serial and purchase date share one chip, on one line, with the
      // separator the chip draws between its parts.
      expect(find.text('S/N: '), findsOneWidget);
      expect(find.text('V2-0123'), findsOneWidget);
      expect(find.text('Bought: '), findsOneWidget);
      expect(find.text('  ·  '), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Bought: ')).dy,
        tester.getTopLeft(find.text('S/N: ')).dy,
      );

      // The pushed screen's stacked header card is gone from the pane.
      expect(find.text('Print hours  ·  tap to edit'), findsNothing);
    });
  });
}
