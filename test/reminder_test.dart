import 'package:flutter_test/flutter_test.dart';
import 'package:printer_maintenance/data/models.dart';
import 'package:printer_maintenance/services/due_status.dart';
import 'package:printer_maintenance/services/notifications.dart';

void main() {
  Printer printer(String name, {double hours = 0}) => Printer(
    name: name,
    totalPrintHours: hours,
    createdAt: DateTime(2026, 1, 1),
  );

  /// A schedule plus whatever `DueStatus` makes of it, so the digest is
  /// tested against the real labels rather than hand-made ones.
  AttentionItem attention(
    String taskName,
    String printerName, {
    double hours = 0,
    double? intervalHours,
    int? intervalDays,
    int? intervalMonths,
    double? lastDoneHours,
    DateTime? lastDoneAt,
  }) {
    final schedule = PrinterTask(
      printerId: 1,
      taskId: 1,
      taskName: taskName,
      intervalHours: intervalHours,
      intervalDays: intervalDays,
      intervalMonths: intervalMonths,
      lastDoneHours: lastDoneHours,
      lastDoneAt: lastDoneAt,
    );
    return AttentionItem(
      printer: printer(printerName, hours: hours),
      schedule: schedule,
      info: DueStatus.evaluate(
        printer: printer(printerName, hours: hours),
        schedule: schedule,
      ),
    );
  }

  group('ReminderService.digestFor', () {
    test('nothing due means no digest at all', () {
      expect(ReminderService.digestFor(const <AttentionItem>[]), isNull);
    });

    test('an overdue task names itself, its printer and its state', () {
      final digest = ReminderService.digestFor(<AttentionItem>[
        attention(
          'Lubricate Z lead screws',
          'Voron 2.4',
          hours: 300,
          intervalHours: 200,
          lastDoneHours: 0,
        ),
      ]);

      expect(digest, isNotNull);
      expect(digest!.title, '1 task needs attention');
      expect(digest.body, 'Lubricate Z lead screws on Voron 2.4 is overdue');
    });

    test('a task that has never been done reads as such', () {
      final digest = ReminderService.digestFor(<AttentionItem>[
        attention('Check belt tension', 'Prusa MK4', intervalMonths: 3),
      ]);

      expect(digest!.body, 'Check belt tension on Prusa MK4 is never done');
    });

    test('due soon is worded differently from overdue', () {
      final digest = ReminderService.digestFor(<AttentionItem>[
        attention(
          'Check belt tension',
          'Prusa MK4',
          intervalDays: 100,
          lastDoneAt: DateTime.now().subtract(const Duration(days: 90)),
        ),
      ]);

      expect(digest!.title, '1 task needs attention');
      expect(digest.body, 'Check belt tension on Prusa MK4 is due soon');
    });

    test('a long list is capped and the remainder counted', () {
      final items = List<AttentionItem>.generate(
        ReminderService.maxLines + 2,
        (i) => attention(
          'Task $i',
          'Printer $i',
          hours: 300,
          intervalHours: 100,
          lastDoneHours: 0,
        ),
      );

      final digest = ReminderService.digestFor(items)!;
      final lines = digest.body.split('\n');

      expect(
        digest.title,
        '${ReminderService.maxLines + 2} tasks need attention',
      );
      expect(lines, hasLength(ReminderService.maxLines + 1));
      expect(lines.first, 'Task 0 on Printer 0 is overdue');
      expect(lines.last, '…and 2 more');
    });

    test('exactly at the cap is not counted as extra', () {
      final items = List<AttentionItem>.generate(
        ReminderService.maxLines,
        (i) => attention(
          'Task $i',
          'Printer $i',
          hours: 300,
          intervalHours: 100,
          lastDoneHours: 0,
        ),
      );

      final body = ReminderService.digestFor(items)!.body.split('\n');
      expect(body, hasLength(ReminderService.maxLines));
      expect(body.last, isNot(startsWith('…')));
    });

    test('equal inputs give an equal digest, so an unchanged list is '
        'skipped instead of rescheduled', () {
      final one = ReminderService.digestFor(<AttentionItem>[
        attention(
          'Nozzle',
          'Voron 2.4',
          hours: 300,
          intervalHours: 100,
          lastDoneHours: 0,
        ),
      ]);
      final two = ReminderService.digestFor(<AttentionItem>[
        attention(
          'Nozzle',
          'Voron 2.4',
          hours: 300,
          intervalHours: 100,
          lastDoneHours: 0,
        ),
      ]);
      final three = ReminderService.digestFor(<AttentionItem>[
        attention(
          'Belts',
          'Voron 2.4',
          hours: 300,
          intervalHours: 100,
          lastDoneHours: 0,
        ),
      ]);

      expect(one, equals(two));
      expect(one, isNot(equals(three)));
      expect(one.hashCode, two.hashCode);
    });
  });
}
