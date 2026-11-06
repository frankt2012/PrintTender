import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// The shortest screen side, in logical pixels, at which the tablet shell is
/// used while the layout preference is [TabletLayoutMode.auto]. 600 dp is the
/// conventional Material breakpoint between phones and tablets.
const double tabletBreakpoint = 600;

/// What Settings asks for; the screen itself decides in [auto].
enum TabletLayoutMode {
  auto,
  always,
  never;

  /// Whether the tablet shell should be used on a screen whose shorter side is
  /// [shortestSide] logical pixels.
  bool resolve(double shortestSide) => switch (this) {
    TabletLayoutMode.auto => shortestSide >= tabletBreakpoint,
    TabletLayoutMode.always => true,
    TabletLayoutMode.never => false,
  };

  /// Parses a stored value, falling back to [auto] for anything unrecognised.
  static TabletLayoutMode parse(String? raw) {
    for (final mode in TabletLayoutMode.values) {
      if (mode.name == raw) return mode;
    }
    return TabletLayoutMode.auto;
  }
}

/// This device's own preferences: when the digest is delivered, which layout
/// to use, and whether the notification prompt has been shown.
///
/// They deliberately live beside the app's support files rather than in the
/// database. A backup replaces the workshop; it must not carry another
/// machine's reminder time or layout away with it.
abstract final class DeviceSettings {
  /// 09:00 local time, as minutes past midnight.
  static const int defaultDigestMinutes = 9 * Duration.minutesPerHour;

  static const String _digestTimeFile = 'digest_time';
  static const String _tabletLayoutFile = 'tablet_layout';
  static const String _askedFile = 'reminders_asked';
  static const String _batteryAskedFile = 'battery_asked';
  static const String _autoUpdateFile = 'updates_auto';
  static const String _updateCheckedFile = 'updates_checked';

  /// The folder is named after the reminders it started with; treat it as this
  /// device's state.
  static Future<Directory> stateDirectory() async {
    final directory = await getApplicationSupportDirectory();
    return Directory(p.join(directory.path, 'reminders'));
  }

  /// The chosen digest time, as minutes past midnight.
  ///
  /// Anything unusable — no file yet, an unparseable value, a time outside the
  /// day — falls back to [defaultDigestMinutes] rather than throwing: a
  /// preference must never be able to break the dashboard.
  static Future<int> readDigestMinutes() async {
    try {
      final file = File(p.join((await stateDirectory()).path, _digestTimeFile));
      if (!await file.exists()) return defaultDigestMinutes;
      return normaliseDigestMinutes(
        int.tryParse((await file.readAsString()).trim()),
      );
    } catch (error) {
      debugPrint('Settings: could not read the digest time ($error)');
      return defaultDigestMinutes;
    }
  }

  /// Stores [minutes] past midnight as this device's digest time.
  static Future<void> writeDigestMinutes(int minutes) async {
    final directory = await stateDirectory();
    await directory.create(recursive: true);
    await File(
      p.join(directory.path, _digestTimeFile),
    ).writeAsString('${normaliseDigestMinutes(minutes)}');
  }

  /// Clamps a stored or picked value into the day, or falls back to
  /// [defaultDigestMinutes] when there is no usable value at all.
  static int normaliseDigestMinutes(int? minutes) {
    if (minutes == null || minutes < 0 || minutes >= Duration.minutesPerDay) {
      return defaultDigestMinutes;
    }
    return minutes;
  }

  /// The layout preference, defaulting to [TabletLayoutMode.auto].
  static Future<TabletLayoutMode> readTabletLayout() async {
    try {
      final file = File(
        p.join((await stateDirectory()).path, _tabletLayoutFile),
      );
      if (!await file.exists()) return TabletLayoutMode.auto;
      return TabletLayoutMode.parse((await file.readAsString()).trim());
    } catch (error) {
      debugPrint('Settings: could not read the tablet layout ($error)');
      return TabletLayoutMode.auto;
    }
  }

  static Future<void> writeTabletLayout(TabletLayoutMode mode) async {
    final directory = await stateDirectory();
    await directory.create(recursive: true);
    await File(
      p.join(directory.path, _tabletLayoutFile),
    ).writeAsString(mode.name);
  }

  /// Whether the notification permission prompt has already been shown on this
  /// device. Uses the support directory rather than the cache, so clearing
  /// cached files does not bring the prompt back.
  static Future<bool> remindersAsked() async {
    final file = File(p.join((await stateDirectory()).path, _askedFile));
    return file.exists();
  }

  static Future<void> markRemindersAsked() async {
    final directory = await stateDirectory();
    await directory.create(recursive: true);
    await File(p.join(directory.path, _askedFile)).writeAsString('asked');
  }

  /// Whether the battery-optimisation explanation has already been shown. It is
  /// a one-time nudge; the Settings row stays as the way back to it.
  static Future<bool> batteryPromptAsked() async {
    final file = File(p.join((await stateDirectory()).path, _batteryAskedFile));
    return file.exists();
  }

  static Future<void> markBatteryPromptAsked() async {
    final directory = await stateDirectory();
    await directory.create(recursive: true);
    await File(
      p.join(directory.path, _batteryAskedFile),
    ).writeAsString('asked');
  }

  /// Whether the app may ask GitHub for a newer release on its own. On by
  /// default; the switch in Settings turns it off.
  static Future<bool> autoUpdateCheck() async {
    try {
      final file = File(p.join((await stateDirectory()).path, _autoUpdateFile));
      if (!await file.exists()) return true;
      return (await file.readAsString()).trim() != 'off';
    } catch (error) {
      debugPrint('Settings: could not read the update preference ($error)');
      return true;
    }
  }

  static Future<void> writeAutoUpdateCheck(bool enabled) async {
    final directory = await stateDirectory();
    await directory.create(recursive: true);
    await File(
      p.join(directory.path, _autoUpdateFile),
    ).writeAsString(enabled ? 'on' : 'off');
  }

  /// When the automatic check last reached GitHub successfully, or null if it
  /// never has. A failed check deliberately does not count.
  static Future<DateTime?> lastUpdateCheck() async {
    try {
      final file = File(
        p.join((await stateDirectory()).path, _updateCheckedFile),
      );
      if (!await file.exists()) return null;
      return DateTime.tryParse((await file.readAsString()).trim());
    } catch (error) {
      debugPrint('Settings: could not read the last update check ($error)');
      return null;
    }
  }

  static Future<void> writeLastUpdateCheck(DateTime when) async {
    final directory = await stateDirectory();
    await directory.create(recursive: true);
    await File(
      p.join(directory.path, _updateCheckedFile),
    ).writeAsString(when.toIso8601String());
  }
}
