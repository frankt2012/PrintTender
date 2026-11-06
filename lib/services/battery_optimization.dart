import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android's battery optimisation can defer or kill this app's background work,
/// which is how the daily digest is delivered. This is the bridge to the
/// platform: it reports whether the exemption is in place and opens the system
/// dialog that grants it.
///
/// Everything is best-effort. When the platform cannot answer — an OS without
/// the concept, or a build where the channel is missing — the methods return
/// `null`/`false` so callers stay quiet instead of nagging about a setting that
/// does not exist.
abstract final class BatteryOptimization {
  static const MethodChannel _channel = MethodChannel(
    'printer_maintenance/battery',
  );

  /// The setting only exists on Android.
  static bool get applies => defaultTargetPlatform == TargetPlatform.android;

  /// Whether Android may delay or drop background work for this app.
  ///
  /// `null` means "cannot tell", which is different from "not exempt".
  static Future<bool?> isIgnoring() async {
    if (!applies) return null;
    try {
      return await _channel.invokeMethod<bool>(
        'isIgnoringBatteryOptimizations',
      );
    } on MissingPluginException {
      return null;
    } catch (error) {
      debugPrint('Battery: could not read the optimisation state ($error)');
      return null;
    }
  }

  /// Opens the system dialog that exempts the app.
  ///
  /// Returns whether a dialog was opened; the user still has to agree to it,
  /// and the caller should re-read [isIgnoring] when the app resumes.
  static Future<bool> requestExemption() async {
    if (!applies) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'requestIgnoreBatteryOptimizations',
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } catch (error) {
      debugPrint('Battery: could not open the exemption dialog ($error)');
      return false;
    }
  }
}
