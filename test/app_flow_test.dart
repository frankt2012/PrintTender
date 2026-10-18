import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:printer_maintenance/data/database.dart';
import 'package:printer_maintenance/main.dart';
import 'package:printer_maintenance/ui/screens/add_log_entry_screen.dart';
import 'package:printer_maintenance/ui/screens/edit_printer_screen.dart';
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

/// Pumps until [finder] matches, so we never wait on the perpetual spinner
/// animation shown while the database is opening.
Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Timed out waiting for: $finder');
}

/// Pumps until [finder] matches nothing — used to wait out route transitions so
/// that widgets on the outgoing screen cannot be matched by mistake.
Future<void> pumpUntilGone(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isEmpty) return;
  }
  throw TestFailure(
    'Timed out waiting for disappearance of: $finder',
  );
}

/// Runs animations (bottom sheets, dialogs, route transitions) to completion.
Future<void> settle(WidgetTester tester, {int frames = 24}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Waits for [finder], lets animations finish, then taps.
Future<void> tapWhenReady(WidgetTester tester, Finder finder) async {
  await pumpUntil(tester, finder);
  await settle(tester);
  await tester.tap(finder);
}

Finder buttonIn(Type screen, Type button) => find.descendant(
      of: find.byType(screen),
      matching: find.byType(button),
    );

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('printer_maintenance_ui');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await AppDatabase.resetForTesting();
    // In-memory SQLite is the only flavour that resolves under the fake async
    // clock that widget tests run on.
    AppDatabase.factoryOverride = databaseFactoryFfiNoIsolate;
    AppDatabase.pathOverride = inMemoryDatabasePath;
  });

  tearDown(() async {
    await AppDatabase.resetForTesting();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  void configurePhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(411, 915);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  /// Fills in and submits the printer form. `seedEssentials` mirrors the
  /// \"Start with the eight essentials\" checkbox, which is on by default.
  Future<void> addPrinter(
    WidgetTester tester,
    String name, {
    bool seedEssentials = false,
  }) async {
    await tapWhenReady(
      tester,
      find.widgetWithText(FloatingActionButton, 'Add printer'),
    );
    await pumpUntil(tester, find.byType(EditPrinterScreen));
    await settle(tester);

    await tester.enterText(
      find.descendant(
        of: find.byType(EditPrinterScreen),
        matching: find.byType(TextFormField),
      ).first,
      name,
    );
    await settle(tester);

    // The form grew past the fold, and the button list is built lazily, so the
    // save button has to be scrolled into existence before it can be tapped.
    final scrollable = find
        .descendant(
          of: find.byType(EditPrinterScreen),
          matching: find.byType(Scrollable),
        )
        .first;

    if (!seedEssentials) {
      final toggle = find.text('Start with the eight essentials');
      await tester.scrollUntilVisible(toggle, 240, scrollable: scrollable);
      await settle(tester);
      await tester.tap(toggle);
      await settle(tester);
    }

    final save = buttonIn(EditPrinterScreen, FilledButton);
    await tester.scrollUntilVisible(save, 240, scrollable: scrollable);
    await settle(tester);
    await tester.tap(save);

    await pumpUntilGone(tester, find.byType(EditPrinterScreen));
    await pumpUntil(tester, find.text('MY PRINTERS'));
    await settle(tester);
  }

  Future<void> assignTask(WidgetTester tester, String taskName) async {
    await tapWhenReady(tester, find.text('Assign a maintenance task'));

    // The picker lists the whole library grouped by category, so a task that
    // sits late in the list has to be scrolled into existence first.
    await pumpUntil(tester, find.byType(BottomSheet));
    await settle(tester);
    if (find.text(taskName).evaluate().isEmpty) {
      final sheetList = find
          .descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text(taskName),
        200,
        scrollable: sheetList,
      );
    }

    await pumpUntil(tester, find.text(taskName));
    await settle(tester);
    await tester.tap(find.text(taskName).last);

    await pumpUntil(tester, find.byType(AlertDialog));
    await settle(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(FilledButton),
      ),
    );

    await pumpUntilGone(tester, find.byType(AlertDialog));
    await pumpUntil(tester, find.text('Never done'));
    await settle(tester);
  }

  /// Bumps the odometer via the dashboard's per-printer action.
  Future<void> setPrinterHours(WidgetTester tester, String value) async {
    await tapWhenReady(
      tester,
      find.widgetWithIcon(IconButton, Icons.speed_outlined),
    );
    await pumpUntil(tester, find.byType(AlertDialog));
    await settle(tester);

    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      value,
    );
    await settle(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(FilledButton),
      ),
    );

    await pumpUntilGone(tester, find.byType(AlertDialog));
    await settle(tester);
  }

  Finder hoursFieldIn(Type screen) => find.descendant(
        of: find.byType(screen),
        matching: find.widgetWithText(TextFormField, 'Print hours at service'),
      );

  Future<void> saveLogEntry(WidgetTester tester) async {
    final save = buttonIn(AddLogEntryScreen, FilledButton);
    await tester.ensureVisible(save);
    await settle(tester);
    await tester.tap(save);
    await pumpUntilGone(tester, find.byType(AddLogEntryScreen));
    await pumpUntil(tester, find.text('MY PRINTERS'));
    await settle(tester);
  }

  /// Puts the dashboard in front of a printer that needs attention, with the
  /// given task assigned.
  Future<void> setUpDueTask(
    WidgetTester tester, {
    required String printerName,
    required String taskName,
    String? printHours,
  }) async {
    await tester.pumpWidget(const PrinterMaintenanceApp());
    await pumpUntil(tester, find.text('No printers yet'));

    await addPrinter(tester, printerName);
    if (printHours != null) {
      await setPrinterHours(tester, printHours);
    }

    await tapWhenReady(tester, find.text(printerName));
    await pumpUntil(tester, find.text('Nothing scheduled'));
    await settle(tester);
    await assignTask(tester, taskName);

    await tester.pageBack();
    await pumpUntilGone(tester, find.byType(PrinterDetailScreen));
    await pumpUntil(tester, find.text('NEEDS ATTENTION'));
    await settle(tester);
  }

  testWidgets('a fresh install shows the empty state', (tester) async {
    configurePhone(tester);
    await tester.pumpWidget(const PrinterMaintenanceApp());

    await pumpUntil(tester, find.text('No printers yet'));
    expect(find.text('Add printer'), findsWidgets);
  });

  testWidgets('add a printer, assign a task, and see it flagged as due',
      (tester) async {
    configurePhone(tester);
    await tester.pumpWidget(const PrinterMaintenanceApp());
    await pumpUntil(tester, find.text('No printers yet'));

    await addPrinter(tester, 'Voron 2.4');
    expect(find.text('Voron 2.4'), findsOneWidget);

    // A brand-new printer with the seeding box unticked really has nothing on
    // its board.
    await tapWhenReady(tester, find.text('Voron 2.4'));
    await pumpUntil(tester, find.text('Nothing scheduled'));
    await settle(tester);

    await assignTask(tester, 'Build plate');

    // The task is scheduled and flagged as never performed.
    expect(find.text('Build plate'), findsOneWidget);
    expect(find.text('Never done'), findsOneWidget);
  });

  testWidgets('a new printer can start with the eight essentials',
      (tester) async {
    configurePhone(tester);
    await tester.pumpWidget(const PrinterMaintenanceApp());
    await pumpUntil(tester, find.text('No printers yet'));

    await addPrinter(tester, 'Bambu A1', seedEssentials: true);

    // Eight jobs exist and none of them are due, so the tile reads "All good"
    // rather than "No schedule", and nothing lands in Needs attention.
    await pumpUntil(tester, find.text('All good'));
    expect(find.text('No schedule'), findsNothing);
    expect(find.text('NEEDS ATTENTION'), findsNothing);
  });

  testWidgets('a printer remembers its nozzle and build-plate setup',
      (tester) async {
    configurePhone(tester);
    await tester.pumpWidget(const PrinterMaintenanceApp());
    await pumpUntil(tester, find.text('No printers yet'));

    await tapWhenReady(
      tester,
      find.widgetWithText(FloatingActionButton, 'Add printer'),
    );
    await pumpUntil(tester, find.byType(EditPrinterScreen));
    await settle(tester);

    await tester.enterText(
      find.descendant(
        of: find.byType(EditPrinterScreen),
        matching: find.byType(TextFormField),
      ).first,
      'Setup test',
    );
    await settle(tester);

    final scrollable = find
        .descendant(
          of: find.byType(EditPrinterScreen),
          matching: find.byType(Scrollable),
        )
        .first;

    // Nozzle type comes from the preset list...
    final nozzleType = find
        .widgetWithText(DropdownButtonFormField<String>, 'Not set')
        .first;
    await tester.scrollUntilVisible(nozzleType, 240, scrollable: scrollable);
    await settle(tester);
    await tester.tap(nozzleType);
    await settle(tester);
    await tester.tap(find.text('Brass').last);
    await settle(tester);

    // ...the size is typed...
    final nozzleSize = find.widgetWithText(TextFormField, 'Nozzle size');
    await tester.scrollUntilVisible(nozzleSize, 240, scrollable: scrollable);
    await settle(tester);
    await tester.enterText(nozzleSize, '0.4 mm');
    await settle(tester);

    // ...and the build plate is picked. With the nozzle chosen, the only
    // dropdown still reading "Not set" is the plate.
    final plate = find
        .widgetWithText(DropdownButtonFormField<String>, 'Not set')
        .first;
    await tester.scrollUntilVisible(plate, 240, scrollable: scrollable);
    await settle(tester);
    await tester.tap(plate);
    await settle(tester);
    await tester.tap(find.text('Textured PEI').last);
    await settle(tester);

    // Leave the essentials unchecked; this test is about the setup fields.
    final toggle = find.text('Start with the eight essentials');
    await tester.scrollUntilVisible(toggle, 240, scrollable: scrollable);
    await settle(tester);
    await tester.tap(toggle);
    await settle(tester);

    final save = buttonIn(EditPrinterScreen, FilledButton);
    await tester.scrollUntilVisible(save, 240, scrollable: scrollable);
    await settle(tester);
    await tester.tap(save);
    await pumpUntilGone(tester, find.byType(EditPrinterScreen));
    await pumpUntil(tester, find.text('MY PRINTERS'));
    await settle(tester);

    // The detail header shows the setup back.
    await tapWhenReady(tester, find.text('Setup test'));
    await pumpUntil(tester, find.text('Nothing scheduled'));
    await settle(tester);

    expect(find.text('0.4 mm Brass'), findsOneWidget);
    expect(find.text('Textured PEI'), findsOneWidget);
  });

  testWidgets('the export menu writes a real backup file', (tester) async {
    configurePhone(tester);
    await tester.pumpWidget(const PrinterMaintenanceApp());
    await pumpUntil(tester, find.text('No printers yet'));

    await tapWhenReady(tester, find.byTooltip('More'));
    await pumpUntil(tester, find.text('Export backup'));
    expect(find.text('Import backup'), findsOneWidget);
    await settle(tester);

    await tester.tap(find.byType(PopupMenuItem<String>).first);

    // The export serialises the database and writes it to a real file, so it
    // finishes on the platform event loop rather than the fake test clock.
    // Give it both kinds of time until the document has actually landed.
    final files = <File>[];
    for (var attempt = 0; attempt < 100 && files.isEmpty; attempt++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      final written = tempDir
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.json'))
          .where((file) => file.lengthSync() > 0)
          .toList();
      files
        ..clear()
        ..addAll(written);
    }

    // Export hands the share sheet exactly one document. The sheet itself needs
    // a real platform, but the document it would share is checkable right here.
    expect(files, hasLength(1));
    final payload =
        jsonDecode(files.single.readAsStringSync()) as Map<String, Object?>;
    expect(payload['app'], 'printer_maintenance');
    expect(
      payload.keys,
      containsAll(<String>[
        'tasks',
        'printers',
        'printer_tasks',
        'log_entries',
      ]),
    );
    expect(
      files.single.uri.pathSegments.last,
      matches(RegExp(r'^printer-maintenance-\d{4}-\d{2}-\d{2}\.json$')),
    );
  });

  testWidgets('a calendar-only task hides the print-hours field and still resets',
      (tester) async {
    configurePhone(tester);
    // "Belts" is scheduled every 6 months and has no hour interval.
    await setUpDueTask(
      tester,
      printerName: 'Prusa MK4',
      taskName: 'Belts',
    );

    await tapWhenReady(tester, find.widgetWithText(TextButton, 'Log'));
    await pumpUntil(tester, find.byType(AddLogEntryScreen));
    await settle(tester);

    // The reading is meaningless for a calendar-only task, so it is not asked
    // for...
    expect(hoursFieldIn(AddLogEntryScreen), findsNothing);
    expect(
      find.text(
        'This task is scheduled by calendar only, so print hours are not '
        'needed.',
      ),
      findsOneWidget,
    );

    await saveLogEntry(tester);

    // ...and logging without it still clears the reminder.
    await pumpUntil(tester, find.text('All good'));
    expect(find.text('NEEDS ATTENTION'), findsNothing);
    expect(find.text('Belts'), findsOneWidget); // recent activity
  });

  testWidgets('the printer odometer can be updated from the dashboard',
      (tester) async {
    configurePhone(tester);
    await tester.pumpWidget(const PrinterMaintenanceApp());
    await pumpUntil(tester, find.text('No printers yet'));

    await addPrinter(tester, 'Voron 2.4');
    expect(find.textContaining('0 h'), findsOneWidget);

    await setPrinterHours(tester, '412');

    expect(find.textContaining('412 h'), findsOneWidget);
    expect(find.textContaining('0 h'), findsNothing);
  });

  testWidgets('an hour-scheduled task prefills the odometer and then resets',
      (tester) async {
    configurePhone(tester);
    // "Nozzle" is scheduled every 200 print hours (and every 3 months).
    await setUpDueTask(
      tester,
      printerName: 'Voron 2.4',
      taskName: 'Nozzle',
      printHours: '120',
    );

    await tapWhenReady(tester, find.widgetWithText(TextButton, 'Log'));
    await pumpUntil(tester, find.byType(AddLogEntryScreen));
    await settle(tester);

    // The field is offered, and it is already filled with the odometer, so the
    // common case is simply accepting it.
    final hoursField = hoursFieldIn(AddLogEntryScreen);
    expect(hoursField, findsOneWidget);
    final editable = tester.widget<EditableText>(
      find.descendant(of: hoursField, matching: find.byType(EditableText)),
    );
    expect(editable.controller.text, '120');

    await saveLogEntry(tester);

    await pumpUntil(tester, find.text('All good'));
    expect(find.text('NEEDS ATTENTION'), findsNothing);
  });

  testWidgets('logging a higher reading moves the odometer forward',
      (tester) async {
    configurePhone(tester);
    await setUpDueTask(
      tester,
      printerName: 'Voron 2.4',
      taskName: 'Nozzle',
      printHours: '120',
    );

    await tapWhenReady(tester, find.widgetWithText(TextButton, 'Log'));
    await pumpUntil(tester, find.byType(AddLogEntryScreen));
    await settle(tester);

    // Type the newer reading the machine reports; it should become the printer
    // total without any extra switch to flip.
    await tester.enterText(hoursFieldIn(AddLogEntryScreen), '260');
    await settle(tester);

    await saveLogEntry(tester);

    await pumpUntil(tester, find.textContaining('260 h'));
    expect(find.textContaining('120 h'), findsNothing);
  });
}
