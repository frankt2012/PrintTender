import '../data/models.dart';

enum DueLevel {
  /// Comfortably within the interval.
  ok,

  /// 15% or less of the interval remains.
  dueSoon,

  /// At or past the interval.
  overdue,

  /// Disabled, or no interval configured — nothing to report.
  unscheduled,
}

class DueInfo {
  final DueLevel level;

  /// Highest fraction of any interval consumed. 1.0 means due, >1 overdue.
  final double? progress;
  final double? hoursSince;
  final int? daysSince;

  /// Days left on the calendar interval (days or months), whichever is tighter.
  final int? daysRemaining;
  final String label;

  const DueInfo({
    required this.level,
    required this.label,
    this.progress,
    this.hoursSince,
    this.daysSince,
    this.daysRemaining,
  });
}

/// One scheduled task that is overdue or coming due, with everything needed to
/// say something useful about it — on the dashboard and in a reminder.
class AttentionItem {
  const AttentionItem({
    required this.printer,
    required this.schedule,
    required this.info,
  });

  final Printer printer;
  final PrinterTask schedule;
  final DueInfo info;
}

/// Decides when a scheduled task is due, using ANY combination of a print-hour
/// interval, a calendar-day interval, and a calendar-month interval — whichever
/// limit is reached first wins.
class DueStatus {
  /// Matches the reference app: anything with 15% or less of its interval left
  /// is "due soon".
  static const double dueSoonThreshold = 0.85;

  static DueInfo evaluate({
    required Printer printer,
    required PrinterTask schedule,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();

    if (!schedule.enabled) {
      return const DueInfo(level: DueLevel.unscheduled, label: 'Disabled');
    }

    final hasHoursBaseline = schedule.lastDoneHours != null;
    final hasDaysBaseline = schedule.lastDoneAt != null;

    // Never serviced: treat as due immediately.
    if (!hasHoursBaseline && !hasDaysBaseline) {
      return const DueInfo(level: DueLevel.overdue, label: 'Never done');
    }

    double? hoursSince;
    if (schedule.intervalHours != null && hasHoursBaseline) {
      final raw = printer.totalPrintHours - schedule.lastDoneHours!;
      hoursSince = raw < 0 ? 0 : raw;
    }

    // Days elapsed since the last service. Shared by the day and month
    // intervals, and reported so the UI can show a calendar reading.
    int? daysSince;
    if (hasDaysBaseline) {
      daysSince = daysBetween(schedule.lastDoneAt!, today);
    }

    final ratios = <double>[];

    final hourInterval = schedule.intervalHours;
    if (hoursSince != null && hourInterval != null && hourInterval > 0) {
      ratios.add(hoursSince / hourInterval);
    }

    final dayInterval = schedule.intervalDays;
    final monthInterval = schedule.intervalMonths;

    // A month interval is measured as the real number of days between the last
    // service and the same day N calendar months later, so "every 3 months"
    // respects February as well as it respects July. Both calendar intervals
    // share the same "days since" reading; the tighter one governs.
    int? calendarSpan;
    if (daysSince != null) {
      if (dayInterval != null && dayInterval > 0) {
        calendarSpan = dayInterval;
      }
      if (monthInterval != null && monthInterval > 0) {
        final monthSpan = monthSpanInDays(schedule.lastDoneAt!, monthInterval);
        if (monthSpan > 0 &&
            (calendarSpan == null || monthSpan < calendarSpan)) {
          calendarSpan = monthSpan;
        }
      }
    }
    if (calendarSpan != null && daysSince != null) {
      ratios.add(daysSince / calendarSpan);
    }

    if (ratios.isEmpty) {
      return const DueInfo(
        level: DueLevel.unscheduled,
        label: 'No interval set',
      );
    }

    final progress = ratios.reduce((a, b) => a > b ? a : b);

    final DueLevel level;
    if (progress >= 1.0) {
      level = DueLevel.overdue;
    } else if (progress >= dueSoonThreshold) {
      level = DueLevel.dueSoon;
    } else {
      level = DueLevel.ok;
    }

    return DueInfo(
      level: level,
      progress: progress,
      hoursSince: hoursSince,
      daysSince: daysSince,
      daysRemaining: calendarSpan == null || daysSince == null
          ? null
          : calendarSpan - daysSince,
      label: _label(level, hoursSince, daysSince, calendarSpan, schedule),
    );
  }

  /// Whole days between two timestamps, normalised to UTC midnight so a DST
  /// change in the middle cannot shorten a month span by an hour.
  static int daysBetween(DateTime from, DateTime to) {
    final a = _dateOnly(from);
    final b = _dateOnly(to);
    return b.difference(a).inDays;
  }

  /// `from` advanced by `months`, clamped to the last day of the target month
  /// (31 Jan + 1 month = 28/29 Feb).
  static DateTime addMonths(DateTime from, int months) {
    final base = _dateOnly(from);
    final total = base.month - 1 + months;
    final year = base.year + total ~/ 12;
    final month = total % 12 + 1;
    final lastDay = DateTime.utc(year, month + 1, 0).day;
    final day = base.day <= lastDay ? base.day : lastDay;
    return DateTime.utc(year, month, day);
  }

  /// The real length, in days, of a `months` interval starting at `from`.
  static int monthSpanInDays(DateTime from, int months) =>
      addMonths(from, months).difference(_dateOnly(from)).inDays;

  static DateTime _dateOnly(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);

  static String _label(
    DueLevel level,
    double? hoursSince,
    int? daysSince,
    int? calendarSpan,
    PrinterTask schedule,
  ) {
    switch (level) {
      case DueLevel.overdue:
        return 'Overdue';
      case DueLevel.dueSoon:
        return 'Due soon';
      case DueLevel.unscheduled:
        return 'Not scheduled';
      case DueLevel.ok:
        final parts = <String>[];
        final hourInterval = schedule.intervalHours;
        if (hoursSince != null && hourInterval != null) {
          parts.add('${_formatHours(hourInterval - hoursSince)} h left');
        }
        if (calendarSpan != null && daysSince != null) {
          parts.add('${calendarSpan - daysSince} d left');
        }
        return parts.isEmpty ? 'OK' : parts.join('  ·  ');
    }
  }

  static String _formatHours(double value) {
    if (value >= 100) return value.toStringAsFixed(0);
    return value.toStringAsFixed(1);
  }

  /// "every 200 h or 3 mo" — a compact description of any interval combination.
  static String describeInterval({double? hours, int? days, int? months}) {
    final parts = <String>[];
    if (hours != null) parts.add('${_formatHours(hours)} h');
    if (days != null) parts.add('$days d');
    if (months != null) parts.add('$months mo');
    if (parts.isEmpty) return 'No interval';
    return 'every ${parts.join(' or ')}';
  }
}
