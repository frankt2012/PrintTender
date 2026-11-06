import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:printer_maintenance/services/battery_optimization.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('printer_maintenance/battery');

  void mock(Future<Object?>? Function(MethodCall)? handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
  }

  tearDown(() => mock(null));

  group('BatteryOptimization', () {
    test('stays quiet when the platform has no channel', () async {
      expect(await BatteryOptimization.isIgnoring(), isNull);
    });

    test('reports the platform answer', () async {
      mock(
        (call) async =>
            call.method == 'isIgnoringBatteryOptimizations' ? true : null,
      );
      expect(await BatteryOptimization.isIgnoring(), isTrue);
    });

    test('reports a missing exemption as false, not unknown', () async {
      mock((call) async => false);
      expect(await BatteryOptimization.isIgnoring(), isFalse);
    });

    test('reports whether the exemption dialog opened', () async {
      mock(
        (call) async =>
            call.method == 'requestIgnoreBatteryOptimizations' ? true : false,
      );
      expect(await BatteryOptimization.requestExemption(), isTrue);
    });

    test('reports a refused dialog', () async {
      mock((call) async => false);
      expect(await BatteryOptimization.requestExemption(), isFalse);
    });

    test('is a no-op away from Android', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      expect(await BatteryOptimization.isIgnoring(), isNull);
      expect(await BatteryOptimization.requestExemption(), isFalse);
    });
  });
}
