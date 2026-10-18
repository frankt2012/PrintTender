import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:printer_maintenance/data/database.dart';
import 'package:printer_maintenance/data/models.dart';
import 'package:printer_maintenance/data/repositories.dart';
import 'package:printer_maintenance/data/task_library.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

/// Recreates the schema exactly as release 1 wrote it, including its eight
/// seeded tasks, so the upgrade can be exercised against a realistic database.
///
/// Pass [legacySeedNames] to model a user who deleted some of them, and
/// [scheduleFirstSeed] to model one that is actually in use.
Future<void> _createVersion1Database(
  String path, {
  List<String> legacySeedNames = const <String>[
    'Clean build plate',
    'Clean or replace nozzle',
    'Lubricate Z lead screws',
    'Check belt tension',
    'Clean hotend cooling fan',
    'Check or replace PTFE tube',
    'Grease linear rails',
    'Inspect wiring and connectors',
  ],
  bool withPrinter = false,
}) async {
  final db = await databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE printers (
            id                INTEGER PRIMARY KEY AUTOINCREMENT,
            name              TEXT    NOT NULL,
            manufacturer      TEXT,
            model             TEXT,
            serial_number     TEXT,
            purchase_date     TEXT,
            total_print_hours REAL    NOT NULL DEFAULT 0,
            notes             TEXT,
            archived          INTEGER NOT NULL DEFAULT 0,
            created_at        TEXT    NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE tasks (
            id             INTEGER PRIMARY KEY AUTOINCREMENT,
            name           TEXT    NOT NULL,
            description    TEXT,
            interval_hours REAL,
            interval_days  INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE printer_tasks (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            printer_id      INTEGER NOT NULL REFERENCES printers(id) ON DELETE CASCADE,
            task_id         INTEGER NOT NULL REFERENCES tasks(id)    ON DELETE CASCADE,
            interval_hours  REAL,
            interval_days   INTEGER,
            last_done_at    TEXT,
            last_done_hours REAL,
            enabled         INTEGER NOT NULL DEFAULT 1
          )
        ''');
        await db.execute('''
          CREATE TABLE log_entries (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            printer_id      INTEGER NOT NULL REFERENCES printers(id)     ON DELETE CASCADE,
            printer_task_id INTEGER          REFERENCES printer_tasks(id) ON DELETE SET NULL,
            title           TEXT    NOT NULL,
            performed_at    TEXT    NOT NULL,
            hours_at_service REAL,
            parts_used      TEXT,
            cost            REAL,
            notes           TEXT,
            created_at      TEXT    NOT NULL
          )
        ''');

        for (final name in legacySeedNames) {
          await db.insert('tasks', <String, Object?>{
            'name': name,
            'description': null,
            'interval_hours': name == 'Clean or replace nozzle' ? 200.0 : null,
            'interval_days': name == 'Clean build plate' ? 14 : null,
          });
        }

        if (withPrinter) {
          final printerId = await db.insert('printers', <String, Object?>{
            'name': 'Upgraded printer',
            'total_print_hours': 310.0,
            'archived': 0,
            'created_at': DateTime(2026, 1, 1).toIso8601String(),
          });
          final nozzle = (await db.query(
            'tasks',
            columns: <String>['id'],
            where: 'name = ?',
            whereArgs: <Object?>['Clean or replace nozzle'],
          ));
          await db.insert('printer_tasks', <String, Object?>{
            'printer_id': printerId,
            'task_id': nozzle.first['id'],
            'interval_hours': 200.0,
            'enabled': 1,
          });
        }
      },
    ),
  );
  await db.close();
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('printer_maintenance_v1');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    sqfliteFfiInit();
    await AppDatabase.resetForTesting();
  });

  tearDown(() async {
    await AppDatabase.resetForTesting();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  Future<void> openUpgraded({
    List<String>? legacySeedNames,
    bool withPrinter = false,
  }) async {
    await _createVersion1Database(
      p.join(tempDir.path, 'printer_maintenance.db'),
      legacySeedNames: legacySeedNames ?? const <String>[
        'Clean build plate',
        'Clean or replace nozzle',
        'Lubricate Z lead screws',
        'Check belt tension',
        'Clean hotend cooling fan',
        'Check or replace PTFE tube',
        'Grease linear rails',
        'Inspect wiring and connectors',
      ],
      withPrinter: withPrinter,
    );
    // Opening through the app is what runs the migration.
    await AppDatabase.instance.database;
  }

  test('the whole library arrives without duplicating the old seeds', () async {
    await openUpgraded();

    final definitions = await TaskRepository().definitions();
    expect(definitions, hasLength(defaultTaskLibrary.length));
    final names = definitions.map((d) => d.name).toList();
    expect(names.toSet(), hasLength(defaultTaskLibrary.length));
    expect(names, isNot(contains('Clean build plate')));
    expect(names, isNot(contains('Check belt tension')));
  });

  test('the old seeds are renamed in place and gain their library metadata',
      () async {
    await openUpgraded();

    final byName = <String, MaintenanceTask>{
      for (final d in await TaskRepository().definitions()) d.name: d,
    };
    final nozzle = byName['Nozzle'];
    expect(nozzle, isNotNull);
    expect(nozzle!.intervalHours, 200);
    expect(nozzle.intervalMonths, 3);
    expect(nozzle.category, 'Essentials');
    expect(nozzle.isDefault, isTrue);
    expect(byName['Belts']!.intervalMonths, 6);
  });

  test('an existing schedule follows its renamed definition', () async {
    await openUpgraded(withPrinter: true);

    final printers = PrinterRepository();
    final printer = (await printers.all()).single;
    expect(printer.name, 'Upgraded printer');
    expect(printer.totalPrintHours, 310);

    final schedules = await TaskRepository().schedulesFor(printer.id!);
    expect(schedules, hasLength(1));
    expect(schedules.single.taskName, 'Nozzle');
    expect(schedules.single.intervalHours, 200);
    // The schedule keeps its own interval, not the library's new months figure.
    expect(schedules.single.intervalMonths, isNull);
  });

  test('the new printer columns are usable after the upgrade', () async {
    await openUpgraded(withPrinter: true);

    final printers = PrinterRepository();
    final printer = (await printers.all()).single;
    await printers.update(printer.copyWith(
      nozzleType: 'Brass',
      nozzleSize: '0.4 mm',
      buildPlate: 'Smooth PEI',
    ));

    final reloaded = (await printers.byId(printer.id!))!;
    expect(reloaded.nozzleType, 'Brass');
    expect(reloaded.nozzleSize, '0.4 mm');
    expect(reloaded.buildPlate, 'Smooth PEI');
  });

  test('an install where the seeds were deleted still gets the library',
      () async {
    await openUpgraded(legacySeedNames: const <String>[]);

    final definitions = await TaskRepository().definitions();
    expect(definitions, hasLength(defaultTaskLibrary.length));
    expect(definitions.map((d) => d.name), contains('Belts'));
  });

  test('re-running the migration does not pile up duplicate names', () async {
    await openUpgraded(withPrinter: true);
    final first = (await TaskRepository().definitions()).length;

    // Closing and reopening replays the open path (and the migration guard).
    await AppDatabase.resetForTesting();
    await AppDatabase.instance.database;

    expect((await TaskRepository().definitions()).length, first);
  });
}
