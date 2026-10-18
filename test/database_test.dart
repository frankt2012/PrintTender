import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:printer_maintenance/data/database.dart';
import 'package:printer_maintenance/data/models.dart';
import 'package:printer_maintenance/data/repositories.dart';
import 'package:printer_maintenance/services/due_status.dart';

/// Redirects path_provider at a temporary directory so the real database code
/// (including the desktop FFI branch) can run under `flutter test`.
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

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('printer_maintenance_test');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    printers = PrinterRepository();
    tasks = TaskRepository();
    logs = LogRepository();
    // Force the schema to be created.
    await AppDatabase.instance.database;
  });

  tearDownAll(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('creates the database file on disk', () async {
    final files = tempDir
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .toList();
    expect(files, contains('printer_maintenance.db'));
  });

  test('seeds the full starter maintenance library', () async {
    final definitions = await tasks.definitions();
    expect(definitions.length, greaterThanOrEqualTo(50));
    expect(
      definitions.map((d) => d.name),
      containsAll(<String>[
        'Nozzle',
        'Belts',
        'Fans',
        'Lead screws',
        'Build plate',
        'PTFE tube',
      ]),
    );
    // Grouped for the pickers, and the eight essentials are flagged so a new
    // printer can be seeded with them.
    expect(definitions.map((d) => d.category), contains('Essentials'));
    expect(definitions.map((d) => d.category), contains('Resin printers'));
    final essentials = await tasks.defaultDefinitions();
    expect(essentials, hasLength(8));
    expect(essentials.first.name, 'Carbon rods');
    expect(essentials.every((d) => d.isDefault), isTrue);
  });

  test('inserts a printer and reads it back', () async {
    final id = await printers.insert(Printer(
      name: 'Voron 2.4',
      manufacturer: 'LDO',
      model: '300mm',
      serialNumber: 'VR-0042',
      totalPrintHours: 120.5,
      notes: 'Built from a kit',
      createdAt: DateTime(2026, 1, 1),
    ));

    final loaded = await printers.byId(id);
    expect(loaded, isNotNull);
    expect(loaded!.name, 'Voron 2.4');
    expect(loaded.manufacturer, 'LDO');
    expect(loaded.model, '300mm');
    expect(loaded.serialNumber, 'VR-0042');
    expect(loaded.totalPrintHours, 120.5);
    expect(loaded.notes, 'Built from a kit');
    expect(loaded.archived, isFalse);
  });

  test('archived printers are hidden by default', () async {
    final id = await printers.insert(Printer(
      name: 'Retired printer',
      archived: true,
      createdAt: DateTime(2026, 1, 1),
    ));
    final visible = await printers.all();
    expect(visible.map((p) => p.id), isNot(contains(id)));
    final all = await printers.all(includeArchived: true);
    expect(all.map((p) => p.id), contains(id));
  });

  test('assigns a task to a printer and joins the definition', () async {
    final printerId = await printers.insert(Printer(
      name: 'Prusa MK4S',
      createdAt: DateTime(2026, 1, 1),
    ));
    final definitions = await tasks.definitions();
    final nozzle = definitions.firstWhere((d) => d.name == 'Nozzle');

    await tasks.assign(
      printerId: printerId,
      taskId: nozzle.id!,
      intervalHours: nozzle.intervalHours,
      intervalDays: nozzle.intervalDays,
    );

    final schedules = await tasks.schedulesFor(printerId);
    expect(schedules, hasLength(1));
    expect(schedules.single.taskName, nozzle.name);
    expect(schedules.single.taskDescription, nozzle.description);
    expect(schedules.single.intervalHours, nozzle.intervalHours);
    expect(schedules.single.enabled, isTrue);
    expect(schedules.single.lastDoneAt, isNull);
    expect(await tasks.isAssigned(printerId, nozzle.id!), isTrue);
  });

  test('markDone stores the baseline used by the due-date maths', () async {
    final printerId = await printers.insert(Printer(
      name: 'Bambu X1C',
      createdAt: DateTime(2026, 1, 1),
    ));
    final definitions = await tasks.definitions();
    final scheduleId = await tasks.assign(
      printerId: printerId,
      taskId: definitions.first.id!,
      intervalHours: 100,
    );

    await tasks.markDone(
      printerTaskId: scheduleId,
      performedAt: DateTime(2026, 5, 1),
      hoursAtService: 42,
    );

    final schedule = (await tasks.schedulesFor(printerId)).single;
    expect(schedule.lastDoneHours, 42);
    expect(schedule.lastDoneAt, DateTime(2026, 5, 1));
  });

  test('updating a schedule persists interval and enabled flag', () async {
    final printerId = await printers.insert(Printer(
      name: 'Schedule edit test',
      createdAt: DateTime(2026, 1, 1),
    ));
    final scheduleId = await tasks.assign(
      printerId: printerId,
      taskId: (await tasks.definitions()).first.id!,
      intervalDays: 30,
    );

    final original = (await tasks.schedulesFor(printerId)).single;
    await tasks.updateSchedule(PrinterTask(
      id: scheduleId,
      printerId: printerId,
      taskId: original.taskId,
      intervalHours: 250,
      enabled: false,
      taskName: original.taskName,
    ));

    final updated = (await tasks.schedulesFor(printerId)).single;
    expect(updated.intervalHours, 250);
    expect(updated.enabled, isFalse);
  });

  test('logs entries newest first and totals their cost', () async {
    final printerId = await printers.insert(Printer(
      name: 'Ender 3',
      createdAt: DateTime(2026, 1, 1),
    ));

    await logs.insert(LogEntry(
      printerId: printerId,
      title: 'Replaced nozzle',
      performedAt: DateTime(2026, 3, 1),
      partsUsed: '0.4mm brass nozzle',
      cost: 12.5,
      createdAt: DateTime(2026, 3, 1),
    ));
    await logs.insert(LogEntry(
      printerId: printerId,
      title: 'Cleaned bed',
      performedAt: DateTime(2026, 3, 5),
      createdAt: DateTime(2026, 3, 5),
    ));

    final entries = await logs.forPrinter(printerId);
    expect(entries, hasLength(2));
    expect(entries.first.title, 'Cleaned bed');
    expect(entries.last.partsUsed, '0.4mm brass nozzle');
    expect(await logs.totalCost(printerId: printerId), 12.5);
  });

  test('deleting a printer cascades to its schedules and log', () async {
    final printerId = await printers.insert(Printer(
      name: 'Doomed printer',
      createdAt: DateTime(2026, 1, 1),
    ));
    await tasks.assign(
      printerId: printerId,
      taskId: (await tasks.definitions()).first.id!,
      intervalDays: 10,
    );
    await logs.insert(LogEntry(
      printerId: printerId,
      title: 'Something',
      performedAt: DateTime(2026, 2, 1),
      createdAt: DateTime(2026, 2, 1),
    ));

    await printers.delete(printerId);

    expect(await printers.byId(printerId), isNull);
    expect(await tasks.schedulesFor(printerId), isEmpty);
    expect(await logs.forPrinter(printerId), isEmpty);
  });

  test('deleting a task definition removes it from printer schedules', () async {
    final printerId = await printers.insert(Printer(
      name: 'Definition delete test',
      createdAt: DateTime(2026, 1, 1),
    ));
    final definitionId = await tasks.insertDefinition(
      const MaintenanceTask(name: 'Throwaway task', intervalDays: 5),
    );
    await tasks.assign(printerId: printerId, taskId: definitionId, intervalDays: 5);
    expect(await tasks.schedulesFor(printerId), hasLength(1));

    await tasks.deleteDefinition(definitionId);

    expect(await tasks.schedulesFor(printerId), isEmpty);
  });

  test('setPrintHours updates the odometer', () async {
    final id = await printers.insert(Printer(
      name: 'Odometer test',
      createdAt: DateTime(2026, 1, 1),
    ));
    await printers.setPrintHours(id, 250);
    expect((await printers.byId(id))!.totalPrintHours, 250);
  });

  test('a printer round-trips an optional purchase date and clears it', () async {
    final id = await printers.insert(Printer(
      name: 'Date test',
      purchaseDate: DateTime(2025, 6, 15),
      createdAt: DateTime(2026, 1, 1),
    ));
    final loaded = (await printers.byId(id))!;
    expect(loaded.purchaseDate, DateTime(2025, 6, 15));

    await printers.update(Printer(
      id: id,
      name: loaded.name,
      createdAt: loaded.createdAt,
    ));
    expect((await printers.byId(id))!.purchaseDate, isNull);
  });

  test('a printer stores its nozzle and build plate setup', () async {
    final id = await printers.insert(Printer(
      name: 'Setup test',
      nozzleType: 'Hardened steel',
      nozzleSize: '0.6 mm',
      buildPlate: 'Textured PEI',
      createdAt: DateTime(2026, 1, 1),
    ));
    final loaded = (await printers.byId(id))!;
    expect(loaded.nozzleType, 'Hardened steel');
    expect(loaded.nozzleSize, '0.6 mm');
    expect(loaded.buildPlate, 'Textured PEI');
    expect(loaded.nozzleLabel, '0.6 mm Hardened steel');
  });

  test('a months interval round-trips alongside the hour interval', () async {
    final printerId = await printers.insert(Printer(
      name: 'Months round-trip',
      createdAt: DateTime(2026, 1, 1),
    ));
    final nozzle =
        (await tasks.definitions()).firstWhere((d) => d.name == 'Nozzle');

    await tasks.assign(
      printerId: printerId,
      taskId: nozzle.id!,
      intervalHours: nozzle.intervalHours,
      intervalMonths: nozzle.intervalMonths,
    );

    final schedule = (await tasks.schedulesFor(printerId)).single;
    expect(schedule.intervalHours, 200);
    expect(schedule.intervalMonths, 3);
    expect(schedule.intervalDays, isNull);
  });

  test('seeding a new printer starts the essentials from today', () async {
    final printerId = await printers.insert(Printer(
      name: 'Seeded printer',
      totalPrintHours: 42,
      createdAt: DateTime(2026, 1, 1),
    ));

    await tasks.seedDefaultSchedules(
      printerId: printerId,
      at: DateTime(2026, 6, 1),
      hours: 42,
    );

    final schedules = await tasks.schedulesFor(printerId);
    expect(schedules, hasLength(8));
    expect(
      schedules.every((s) => s.lastDoneAt == DateTime(2026, 6, 1)),
      isTrue,
    );
    expect(schedules.every((s) => s.lastDoneHours == 42), isTrue);

    // The whole point: a machine added today is not already overdue.
    final printer = (await printers.byId(printerId))!;
    for (final schedule in schedules) {
      final info = DueStatus.evaluate(
        printer: printer,
        schedule: schedule,
        now: DateTime(2026, 6, 1),
      );
      expect(info.level, isNot(DueLevel.overdue), reason: schedule.taskName);
    }
  });
}
