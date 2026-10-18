import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:printer_maintenance/data/database.dart';
import 'package:printer_maintenance/data/repositories.dart';
import 'package:printer_maintenance/main.dart';
import 'package:printer_maintenance/services/backup.dart';
import 'package:printer_maintenance/ui/screens/add_log_entry_screen.dart';
import 'package:printer_maintenance/ui/screens/edit_printer_screen.dart';
import 'package:printer_maintenance/ui/screens/printer_detail_screen.dart';
import 'package:sqflite/sqflite.dart';

/// Pumps until [finder] matches.
Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Timed out waiting for: $finder');
}

/// Pumps until [finder] matches nothing — waits out route transitions.
Future<void> pumpUntilGone(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isEmpty) return;
  }
  throw TestFailure('Timed out waiting for disappearance of: $finder');
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

/// Runs against the genuinely installed app: real sqflite, real filesystem,
/// real path_provider. Nothing is stubbed.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // Start each test from an empty database on the device.
    await AppDatabase.resetForTesting();
    final directory = await getDatabasesPath();
    final file = File(p.join(directory, 'printer_maintenance.db'));
    if (file.existsSync()) {
      file.deleteSync();
    }
  });

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

    // The form is a lazy ListView and is taller than a phone screen, so both
    // the seeding checkbox and the save button have to be scrolled into
    // existence before they can be touched.
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

    // The picker shows the whole library grouped by category, so a task late in
    // the list is not built until it is scrolled into view.
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

  Finder hoursField() => find.descendant(
        of: find.byType(AddLogEntryScreen),
        matching: find.widgetWithText(TextFormField, 'Print hours at service'),
      );

  Future<void> saveLogEntry(WidgetTester tester) async {
    // The form is a lazy ListView and the on-screen keyboard shrinks the
    // viewport, so the save button is not built until it is scrolled into view.
    // On a desktop-sized window it happens to be within the cache extent, which
    // is why the widget test never needed this.
    final saveLabel = find.text('Save entry');
    await tester.scrollUntilVisible(
      saveLabel,
      240,
      scrollable: find
          .descendant(
            of: find.byType(AddLogEntryScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await settle(tester);
    await tester.tap(saveLabel);
    await pumpUntilGone(tester, find.byType(AddLogEntryScreen));
  }

  testWidgets('fresh install shows an empty workshop', (tester) async {
    await tester.pumpWidget(const PrinterMaintenanceApp());
    await pumpUntil(tester, find.text('No printers yet'));
    expect(find.text('Add printer'), findsWidgets);
  });

  testWidgets(
    'real end-to-end flow: add printer, schedule, log, clear the reminder',
    (tester) async {
      await tester.pumpWidget(const PrinterMaintenanceApp());
      await pumpUntil(tester, find.text('No printers yet'));

      // 1. Add a printer.
      await addPrinter(tester, 'Voron 2.4');
      expect(find.text('Voron 2.4'), findsOneWidget);

      // 2. Open it and assign a maintenance task.
      await tapWhenReady(tester, find.text('Voron 2.4'));
      await pumpUntil(tester, find.text('Nothing scheduled'));
      await settle(tester);
      await assignTask(tester, 'Build plate');
      expect(find.text('Never done'), findsOneWidget);

      // 3. The dashboard should now be asking for attention.
      await tester.pageBack();
      await pumpUntilGone(tester, find.byType(PrinterDetailScreen));
      await pumpUntil(tester, find.text('NEEDS ATTENTION'));
      await settle(tester);

      // 4. Log the job straight from the attention list. "Build plate" is
      // scheduled by calendar only, so no print-hours reading is asked for.
      await tapWhenReady(tester, find.widgetWithText(TextButton, 'Log'));
      await pumpUntil(tester, find.byType(AddLogEntryScreen));
      await settle(tester);
      expect(hoursField(), findsNothing);

      await saveLogEntry(tester);
      await pumpUntil(tester, find.text('All good'));
      await settle(tester);

      // 5. The reminder is cleared and the job is in recent activity.
      expect(find.text('NEEDS ATTENTION'), findsNothing);
      expect(find.text('Build plate'), findsOneWidget);
    },
  );

  testWidgets(
    'an hour-scheduled task offers a prefilled odometer reading',
    (tester) async {
      await tester.pumpWidget(const PrinterMaintenanceApp());
      await pumpUntil(tester, find.text('No printers yet'));

      await addPrinter(tester, 'Voron 2.4');
      await tapWhenReady(tester, find.text('Voron 2.4'));
      await pumpUntil(tester, find.text('Nothing scheduled'));
      await settle(tester);

      // "Nozzle" is scheduled every 200 print hours.
      await assignTask(tester, 'Nozzle');

      await tester.pageBack();
      await pumpUntilGone(tester, find.byType(PrinterDetailScreen));
      await pumpUntil(tester, find.text('NEEDS ATTENTION'));
      await settle(tester);

      await tapWhenReady(tester, find.widgetWithText(TextButton, 'Log'));
      await pumpUntil(tester, find.byType(AddLogEntryScreen));
      await settle(tester);

      // The field is offered and already carries the odometer, so accepting the
      // default is enough to reset the task.
      final field = hoursField();
      expect(field, findsOneWidget);
      final editable = tester.widget<EditableText>(
        find.descendant(of: field, matching: find.byType(EditableText)),
      );
      expect(editable.controller.text, '0');

      await saveLogEntry(tester);
      await pumpUntil(tester, find.text('All good'));
      await settle(tester);

      expect(find.text('NEEDS ATTENTION'), findsNothing);
    },
  );

  testWidgets(
    'a backup round-trips through the real on-device database',
    (tester) async {
      await tester.pumpWidget(const PrinterMaintenanceApp());
      await pumpUntil(tester, find.text('No printers yet'));

      await addPrinter(tester, 'Backup printer', seedEssentials: true);
      await pumpUntil(tester, find.text('All good'));

      final backup = BackupService();
      final snapshot = backup.decode(backup.encode(await backup.snapshot()));

      final printerId = (await PrinterRepository().all()).single.id!;
      await PrinterRepository().delete(printerId);
      expect(await PrinterRepository().all(), isEmpty);

      await backup.restore(snapshot);

      final restored = (await PrinterRepository().all()).single;
      expect(restored.name, 'Backup printer');
      expect(await TaskRepository().schedulesFor(restored.id!), hasLength(8));
      expect(restored.id, printerId);

      // The restored data is what the UI then renders.
      await tester.pumpWidget(const PrinterMaintenanceApp());
      await pumpUntil(tester, find.text('Backup printer'));
      await pumpUntil(tester, find.text('All good'));
    },
  );
}
