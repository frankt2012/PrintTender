import 'package:flutter_test/flutter_test.dart';
import 'package:printer_maintenance/data/models.dart';
import 'package:printer_maintenance/services/due_status.dart';

void main() {
  Printer printer({double hours = 0}) => Printer(
        name: 'Test printer',
        totalPrintHours: hours,
        createdAt: DateTime(2026, 1, 1),
      );

  PrinterTask schedule({
    double? intervalHours,
    int? intervalDays,
    int? intervalMonths,
    double? lastDoneHours,
    DateTime? lastDoneAt,
    bool enabled = true,
  }) =>
      PrinterTask(
        printerId: 1,
        taskId: 1,
        taskName: 'Clean nozzle',
        intervalHours: intervalHours,
        intervalDays: intervalDays,
        intervalMonths: intervalMonths,
        lastDoneHours: lastDoneHours,
        lastDoneAt: lastDoneAt,
        enabled: enabled,
      );

  group('DueStatus', () {
    test('a task that has never been performed is overdue', () {
      final info = DueStatus.evaluate(
        printer: printer(hours: 10),
        schedule: schedule(intervalHours: 100),
      );
      expect(info.level, DueLevel.overdue);
      expect(info.label, 'Never done');
    });

    test('midway through the hour interval is ok', () {
      final info = DueStatus.evaluate(
        printer: printer(hours: 150),
        schedule: schedule(intervalHours: 100, lastDoneHours: 100),
      );
      expect(info.level, DueLevel.ok);
      expect(info.hoursSince, 50);
    });

    test('past the hour interval is overdue', () {
      final info = DueStatus.evaluate(
        printer: printer(hours: 250),
        schedule: schedule(intervalHours: 100, lastDoneHours: 100),
      );
      expect(info.level, DueLevel.overdue);
    });

    test('85 percent of the interval is due soon', () {
      final info = DueStatus.evaluate(
        printer: printer(hours: 185),
        schedule: schedule(intervalHours: 100, lastDoneHours: 100),
      );
      expect(info.level, DueLevel.dueSoon);
    });

    test('84 percent of the interval is still ok', () {
      final info = DueStatus.evaluate(
        printer: printer(hours: 184),
        schedule: schedule(intervalHours: 100, lastDoneHours: 100),
      );
      expect(info.level, DueLevel.ok);
    });

    test('the calendar interval can trigger before the hour interval', () {
      final info = DueStatus.evaluate(
        printer: printer(hours: 5),
        schedule: schedule(
          intervalHours: 1000,
          intervalDays: 30,
          lastDoneHours: 0,
          lastDoneAt: DateTime.now().subtract(const Duration(days: 40)),
        ),
      );
      expect(info.level, DueLevel.overdue);
    });

    test('a disabled schedule is ignored', () {
      final info = DueStatus.evaluate(
        printer: printer(hours: 900),
        schedule: schedule(
          intervalHours: 10,
          lastDoneHours: 0,
          enabled: false,
        ),
      );
      expect(info.level, DueLevel.unscheduled);
    });

    test('a schedule with no interval is unscheduled', () {
      final info = DueStatus.evaluate(
        printer: printer(hours: 900),
        schedule: schedule(lastDoneHours: 0),
      );
      expect(info.level, DueLevel.unscheduled);
    });
  });

  group('months intervals', () {
    test('comes due exactly on the same day N months later', () {
      // 15 Mar → 15 Jun 2026 is 92 days; being at 92 days is at the limit.
      final info = DueStatus.evaluate(
        printer: printer(),
        schedule: schedule(
          intervalMonths: 3,
          lastDoneAt: DateTime(2026, 3, 15),
        ),
        now: DateTime(2026, 6, 15),
      );
      expect(info.level, DueLevel.overdue);
      expect(info.daysRemaining, 0);
    });

    test('is ok two thirds of the way through', () {
      final info = DueStatus.evaluate(
        printer: printer(),
        schedule: schedule(
          intervalMonths: 3,
          lastDoneAt: DateTime(2026, 4, 15),
        ),
        now: DateTime(2026, 6, 15),
      );
      expect(info.level, DueLevel.ok);
      expect(info.daysRemaining, 30);
    });

    test('is due soon once 15% of the span remains', () {
      // The 3-month span starting 15 Mar 2026 is 92 days; 80 days in leaves 12.
      final info = DueStatus.evaluate(
        printer: printer(),
        schedule: schedule(
          intervalMonths: 3,
          lastDoneAt: DateTime(2026, 3, 15),
        ),
        now: DateTime(2026, 6, 3),
      );
      expect(info.level, DueLevel.dueSoon);
    });

    test('the tighter of a days and a months interval wins', () {
      final info = DueStatus.evaluate(
        printer: printer(),
        schedule: schedule(
          intervalDays: 365,
          intervalMonths: 1,
          lastDoneAt: DateTime(2026, 1, 1),
        ),
        now: DateTime(2026, 2, 15),
      );
      // One month has elapsed (and then some), so the monthly limit governs.
      expect(info.level, DueLevel.overdue);
    });

    test('adding months clamps to the end of a short month', () {
      expect(
        DueStatus.addMonths(DateTime(2026, 1, 31), 1),
        DateTime.utc(2026, 2, 28),
      );
      expect(
        DueStatus.addMonths(DateTime(2024, 1, 31), 1),
        DateTime.utc(2024, 2, 29),
      );
      expect(
        DueStatus.addMonths(DateTime(2026, 10, 31), 4),
        DateTime.utc(2027, 2, 28),
      );
    });
  });

  group('describeInterval', () {
    test('lists every configured limit', () {
      expect(
        DueStatus.describeInterval(hours: 200, months: 3),
        'every 200 h or 3 mo',
      );
      expect(DueStatus.describeInterval(months: 6), 'every 6 mo');
      expect(DueStatus.describeInterval(), 'No interval');
    });
  });
}
