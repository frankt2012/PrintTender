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

  group('ReminderService.nextDigestAfter', () {
    DateTime at(int year, int month, int day, int hour, int minute) =>
        DateTime(year, month, day, hour, minute);

    test('the default delivery time is 09:00', () {
      expect(ReminderService.defaultDigestMinutes, 9 * 60);
    });

    test('later today, when the time has not come round yet', () {
      expect(
        ReminderService.nextDigestAfter(at(2026, 10, 19, 8, 59), 9 * 60),
        at(2026, 10, 19, 9, 0),
      );
    });

    test('exactly at the time rolls to tomorrow, not to now', () {
      expect(
        ReminderService.nextDigestAfter(at(2026, 10, 19, 9, 0), 9 * 60),
        at(2026, 10, 20, 9, 0),
      );
    });

    test('after the time rolls to tomorrow', () {
      expect(
        ReminderService.nextDigestAfter(at(2026, 10, 19, 9, 1), 9 * 60),
        at(2026, 10, 20, 9, 0),
      );
    });

    test('minutes are kept, not rounded to the hour', () {
      expect(
        ReminderService.nextDigestAfter(at(2026, 10, 19, 7, 0), 7 * 60 + 45),
        at(2026, 10, 19, 7, 45),
      );
    });

    test('midnight is a valid delivery time', () {
      expect(
        ReminderService.nextDigestAfter(at(2026, 10, 19, 12, 0), 0),
        at(2026, 10, 20, 0, 0),
      );
    });

    test('the last minute of a month rolls into the next one', () {
      expect(
        ReminderService.nextDigestAfter(at(2026, 10, 31, 23, 59), 9 * 60),
        at(2026, 11, 1, 9, 0),
      );
    });

    test('the last day of February rolls into a leap day', () {
      expect(
        ReminderService.nextDigestAfter(at(2028, 2, 28, 23, 59), 9 * 60),
        at(2028, 2, 29, 9, 0),
      );
    });
  });

  group('ReminderService.normaliseDigestMinutes', () {
    test('keeps either end of the day', () {
      expect(ReminderService.normaliseDigestMinutes(0), 0);
      expect(ReminderService.normaliseDigestMinutes(23 * 60 + 59), 23 * 60 + 59);
    });

    test('falls back to the default for missing, unparseable or absurd '
        'values', () {
      const fallback = ReminderService.defaultDigestMinutes;
      expect(ReminderService.normaliseDigestMinutes(null), fallback);
      expect(ReminderService.normaliseDigestMinutes(-1), fallback);
      expect(ReminderService.normaliseDigestMinutes(24 * 60), fallback);
      expect(
        ReminderService.normaliseDigestMinutes(int.tryParse('not a time')),
        fallback,
      );
    });
  });
}
