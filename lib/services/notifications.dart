import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'due_status.dart';

/// The text of a reminder: a headline and one line per thing that needs work.
class ReminderDigest {
  const ReminderDigest({required this.title, required this.body});

  final String title;
  final String body;

  @override
  bool operator ==(Object other) =>
      other is ReminderDigest && other.title == title && other.body == body;

  @override
  int get hashCode => Object.hash(title, body);

  @override
  String toString() => 'ReminderDigest($title)';
}

/// Local, offline reminders for maintenance that is overdue or coming due.
///
/// The app cannot see a print-hour interval coming: the odometer only moves
/// when the user records a reading, so a "every 200 h" task has no date to
/// alarm on. Rather than only covering the calendar intervals, there is a
/// single **morning digest** — one notification, delivered daily at
/// [digestHour] local time, listing everything the schedules currently say is
/// overdue or due soon. That covers hour tasks, day tasks and month tasks
/// alike, and it needs no per-task ids to maintain when schedules change.
///
/// Two deliberate rules keep it from nagging:
///
///  * when nothing is overdue or due soon there is no digest to deliver, so
///    the scheduled notification is cancelled and a healthy workshop stays
///    silent;
///  * the digest is only rebuilt when its text actually changes, so the same
///    stale list is not re-announced over and over.
///
/// The text has to be baked in when the notification is scheduled — nothing
/// runs in the background at fire time — so it is refreshed on every dashboard
/// load, which also happens after each edit. That means the worst case is a
/// digest that is one app session behind. Everything here is best-effort: a
/// failure to schedule never throws back into the UI.
class ReminderService {
  ReminderService._();

  static final ReminderService instance = ReminderService._();

  /// Notification id of the morning digest (also the reminder's only one).
  static const int digestId = 4242;

  /// When the digest is delivered, in local time.
  static const int digestHour = 9;

  /// Longest digest body: anything beyond this is summarised as a count so
  /// the notification stays a readable height.
  static const int maxLines = 5;

  static const String _channelId = 'due_reminders';
  static const String _channelName = 'Maintenance reminders';
  static const String _channelDescription =
      'A morning summary of maintenance tasks that are overdue or coming due.';

  /// A single file whose existence means "the permission prompt has been
  /// shown". One boolean does not justify a preferences plugin — and the flag
  /// belongs with the rest of this device's state anyway.
  static const String _askedFile = 'reminders_asked';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Future<bool>? _initialising;
  bool _ready = false;

  /// The digest last written to the scheduler, so an unchanged list does not
  /// get rescheduled on every single dashboard load.
  String? _lastBody;

  /// `true` once the device reports a zone in the IANA database. When it does
  /// not (a manually pinned fixed-offset zone), `tz.local` stays on UTC and
  /// `_offset` holds the current offset instead.
  bool _zoneKnown = false;
  Duration _offset = Duration.zero;

  /// Turns an attention list into notification text, or `null` when there is
  /// nothing worth interrupting the user for.
  static ReminderDigest? digestFor(List<AttentionItem> attention) {
    if (attention.isEmpty) return null;

    final lines = <String>[];
    for (final item in attention.take(maxLines)) {
      lines.add(
        '${item.schedule.taskName} on ${item.printer.name} is '
        '${item.info.label.toLowerCase()}',
      );
    }
    if (attention.length > maxLines) {
      lines.add('…and ${attention.length - maxLines} more');
    }

    final count = attention.length;
    return ReminderDigest(
      title: count == 1
          ? '1 task needs attention'
          : '$count tasks need attention',
      body: lines.join('\n'),
    );
  }

  /// Recomputes and reschedules the digest.
  ///
  /// [attention] is the dashboard's list of overdue and due-soon schedules,
  /// [hasSchedule] whether the workshop has any schedule at all (the moment
  /// a permission prompt starts making sense).
  Future<void> sync({
    required List<AttentionItem> attention,
    required bool hasSchedule,
  }) async {
    try {
      if (!await _ensureReady()) return;
      await _askPermissionOnce(hasSchedule);
      await _apply(attention);
    } catch (error) {
      // A reminder that will not schedule is a missing feature, not an error
      // worth showing the user — the dashboard still has its own list.
      debugPrint('Reminders: update skipped ($error)');
    }
  }

  /// Initialises time zones, the plugin and the notification channel.
  ///
  /// Returns `false` when reminders cannot work on this device; the future is
  /// released in that case so a later attempt can try again.
  Future<bool> _ensureReady() {
    if (_ready) return Future<bool>.value(true);
    return _initialising ??= _initialise().then((ready) {
      if (!ready) _initialising = null;
      return ready;
    });
  }

  Future<bool> _initialise() async {
    tz_data.initializeTimeZones();

    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
      _zoneKnown = true;
    } catch (error) {
      // No IANA zone on this device: stay on UTC and schedule against the
      // fixed offset instead. Fixed-offset zones never change, so the timing
      // stays right; a real zone we simply cannot name falls back to UTC.
      _zoneKnown = false;
      tz.setLocalLocation(tz.UTC);
      debugPrint('Reminders: no IANA time zone ($error)');
    }
    _offset = DateTime.now().timeZoneOffset;

    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
          macOS: DarwinInitializationSettings(),
        ),
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              _channelId,
              _channelName,
              description: _channelDescription,
              importance: Importance.high,
            ),
          );
    } catch (error) {
      debugPrint('Reminders: notification setup failed ($error)');
      return false;
    }

    _ready = true;
    return true;
  }

  /// Asks for the Android 13+/macOS notification permission, at most once and
  /// only once there is something to be notified about. A refusal is never
  /// re-nagged — the system setting remains the way back in.
  Future<void> _askPermissionOnce(bool hasSchedule) async {
    if (!hasSchedule) return;
    if (await _asked()) return;

    // Marked before asking, not after: a prompt that throws must not turn
    // into a prompt that comes back on every launch.
    try {
      await _markAsked();
    } catch (error) {
      // Failing to record the fact is not a reason to skip the prompt.
      debugPrint('Reminders: could not record permission prompt ($error)');
    }

    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      await android.requestNotificationsPermission();
      return;
    }

    final mac = _plugin
        .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin
        >();
    if (mac != null) {
      await mac.requestPermissions(alert: true, badge: true, sound: true);
      return;
    }

    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    await ios?.requestPermissions(alert: true, badge: true, sound: true);
  }

  /// Whether the notification permission prompt has already been shown on
  /// this device. Uses the support directory rather than the cache, so
  /// clearing cached files does not bring the prompt back.
  Future<bool> _asked() async {
    final file = File(p.join((await _flagDirectory()).path, _askedFile));
    return file.exists();
  }

  Future<void> _markAsked() async {
    final directory = await _flagDirectory();
    await directory.create(recursive: true);
    await File(p.join(directory.path, _askedFile)).writeAsString('asked');
  }

  Future<Directory> _flagDirectory() async {
    final directory = await getApplicationSupportDirectory();
    return Directory(p.join(directory.path, 'reminders'));
  }

  Future<void> _apply(List<AttentionItem> attention) async {
    final digest = digestFor(attention);
    if (digest?.body == _lastBody) return;

    if (digest == null) {
      await _plugin.cancel(id: digestId);
    } else {
      await _plugin.zonedSchedule(
        id: digestId,
        scheduledDate: _nextDigestAt(digestHour),
        title: digest.title,
        body: digest.body,
        payload: 'digest',
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.high,
            priority: Priority.high,
            styleInformation: BigTextStyleInformation(digest.body),
          ),
          iOS: const DarwinNotificationDetails(),
          macOS: const DarwinNotificationDetails(),
        ),
        // Inexact on purpose: a daily reminder does not need the second it
        // fires at, and inexact alarms are the one kind Android still grants
        // without the restricted SCHEDULE_EXACT_ALARM permission.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    }

    _lastBody = digest?.body;
  }

  /// The next [hour]:00 in local time, or tomorrow's if it has passed today.
  ///
  /// The date is worked out in local civil time and the hour is always taken
  /// from [hour], so a daylight-saving jump in the small hours cannot move the
  /// delivery time with it.
  tz.TZDateTime _nextDigestAt(int hour) {
    final now = DateTime.now();
    var day = DateTime(now.year, now.month, now.day);
    if (!now.isBefore(DateTime(now.year, now.month, now.day, hour))) {
      day = day.add(const Duration(days: 1));
    }

    final wall = tz.TZDateTime(tz.local, day.year, day.month, day.day, hour);
    return _zoneKnown ? wall : wall.subtract(_offset);
  }
}
