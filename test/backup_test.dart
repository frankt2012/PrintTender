import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:printer_maintenance/data/database.dart';
import 'package:printer_maintenance/data/models.dart';
import 'package:printer_maintenance/data/repositories.dart';
import 'package:printer_maintenance/services/backup.dart';

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

void main() {
  late Directory tempDir;
  late PrinterRepository printers;
  late TaskRepository tasks;
  late LogRepository logs;
  final backup = BackupService();

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('printer_maintenance_bak');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    printers = PrinterRepository();
    tasks = TaskRepository();
    logs = LogRepository();
    await AppDatabase.instance.database;
  });

  tearDownAll(() async {
    await AppDatabase.resetForTesting();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  /// Wipes the workshop between tests so each one starts from the same place.
  /// The task library is left alone — it is the same in every backup.
  Future<void> clearWorkshop() async {
    for (final entry in await logs.recent(limit: 1000)) {
      await logs.delete(entry.id!);
    }
    for (final printer in await printers.all(includeArchived: true)) {
      await printers.delete(printer.id!);
    }
  }

  setUp(clearWorkshop);

  Future<void> seedWorkshop() async {
    final printerId = await printers.insert(Printer(
      name: 'Backup printer',
      nozzleType: 'Brass',
      nozzleSize: '0.4 mm',
      buildPlate: 'Textured PEI',
      totalPrintHours: 128,
      createdAt: DateTime(2026, 1, 1),
    ));
    final nozzle =
        (await tasks.definitions()).firstWhere((d) => d.name == 'Nozzle');
    final scheduleId = await tasks.assign(
      printerId: printerId,
      taskId: nozzle.id!,
      intervalHours: nozzle.intervalHours,
      intervalMonths: nozzle.intervalMonths,
    );
    await tasks.markDone(
      printerTaskId: scheduleId,
      performedAt: DateTime(2026, 5, 1),
      hoursAtService: 100,
    );
    await logs.insert(LogEntry(
      printerId: printerId,
      printerTaskId: scheduleId,
      title: 'Nozzle',
      performedAt: DateTime(2026, 5, 1),
      hoursAtService: 100,
      partsUsed: '0.4 mm brass',
      cost: 12.5,
      createdAt: DateTime(2026, 5, 1),
    ));
  }

  test('a snapshot survives an encode / decode round-trip', () async {
    await seedWorkshop();

    final snapshot = await backup.snapshot();
    expect(snapshot['app'], BackupService.appTag);
    expect(snapshot['format'], BackupService.formatVersion);

    final decoded = backup.decode(backup.encode(snapshot));
    expect(decoded['printers'], hasLength(1));
    expect(decoded['tasks'], hasLength(58));
    expect(decoded['log_entries'], hasLength(1));
  });

  test('restoring a backup replaces everything and rebuilds the data',
      () async {
    await seedWorkshop();
    final snapshot = backup.decode(backup.encode(await backup.snapshot()));

    // Wreck everything.
    final printer = (await printers.all()).single;
    await printers.delete(printer.id!);
    expect(await printers.all(), isEmpty);
    expect(await logs.recent(), isEmpty);

    await backup.restore(snapshot);
    final restored = (await printers.all()).single;
    expect(restored.name, 'Backup printer');
    expect(restored.totalPrintHours, 128);
    expect(restored.nozzleType, 'Brass');
    expect(restored.buildPlate, 'Textured PEI');

    final schedules = await tasks.schedulesFor(restored.id!);
    expect(schedules, hasLength(1));
    expect(schedules.single.taskName, 'Nozzle');
    expect(schedules.single.intervalMonths, 3);
    expect(schedules.single.lastDoneHours, 100);

    final entries = await logs.forPrinter(restored.id!);
    expect(entries, hasLength(1));
    expect(entries.single.partsUsed, '0.4 mm brass');
    expect(await logs.totalCost(printerId: restored.id!), 12.5);
    expect((await tasks.definitions()), hasLength(58));
  });

  test('restoring into a non-empty database does not merge', () async {
    await seedWorkshop();
    final snapshot = backup.decode(backup.encode(await backup.snapshot()));

    await printers.insert(Printer(
      name: 'Should be erased',
      createdAt: DateTime(2026, 2, 1),
    ));
    expect(await printers.all(), hasLength(2));

    await backup.restore(snapshot);
    expect((await printers.all()).single.name, 'Backup printer');
  });

  test('a file from another app is rejected', () {
    expect(
      () => backup.decode('{"app":"something_else","format":1}'),
      throwsA(isA<FormatException>()),
    );
  });

  test('invalid JSON and missing sections are rejected', () {
    expect(() => backup.decode('not json'), throwsA(isA<FormatException>()));
    expect(
      () => backup.decode('{"app":"${BackupService.appTag}","format":1}'),
      throwsA(isA<FormatException>()),
    );
  });

  test('a backup from a newer format version is refused', () {
    expect(
      () => backup.decode(
        '{"app":"${BackupService.appTag}","format":99,'
        '"tasks":[],"printers":[],"printer_tasks":[],"log_entries":[]}',
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('the suggested filename carries the date', () {
    expect(
      backup.suggestedFileName(DateTime(2026, 10, 7)),
      'printer-maintenance-2026-10-07.json',
    );
  });
}
