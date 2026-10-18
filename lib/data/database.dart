import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show sqfliteFfiInit, databaseFactoryFfi;

import 'task_library.dart';

/// Opens (and creates on first run) the local SQLite database.
///
/// `sqflite` only speaks to the mobile platform channels, so on desktop we swap
/// in the FFI factory which talks to the OS SQLite library directly.
class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  static const int _schemaVersion = 2;

  Database? _db;

  static bool get isDesktop =>
      !kIsWeb &&
      (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  /// Tests set this to `databaseFactoryFfiNoIsolate`, because the default FFI
  /// factory runs queries on a background isolate that never completes under the
  /// fake async clock used by widget tests.
  @visibleForTesting
  static DatabaseFactory? factoryOverride;

  /// Tests point this at [inMemoryDatabasePath]. File-backed SQLite never opens
  /// under the fake async clock that widget tests run on, but in-memory does.
  @visibleForTesting
  static String? pathOverride;

  /// Closes and forgets the cached connection and any test overrides so a test
  /// can start from a clean database.
  @visibleForTesting
  static Future<void> resetForTesting() async {
    final self = instance;
    await self._db?.close();
    self._db = null;
    factoryOverride = null;
    pathOverride = null;
  }

  Future<Database> get database async => _db ??= await _open();

  Future<String> _databaseDirectory() async {
    if (isDesktop) {
      // Inside the macOS sandbox this resolves to
      // ~/Library/Containers/<bundle-id>/Data/Library/Application Support/<app>
      final dir = await getApplicationSupportDirectory();
      return dir.path;
    }
    return getDatabasesPath();
  }

  Future<Database> _open() async {
    final DatabaseFactory factory;
    if (isDesktop) {
      sqfliteFfiInit();
      factory = factoryOverride ?? databaseFactoryFfi;
      databaseFactory = factory;
    } else {
      factory = databaseFactory;
    }

    final String path;
    if (pathOverride != null) {
      path = pathOverride!;
    } else {
      final directory = await _databaseDirectory();
      path = p.join(directory, 'printer_maintenance.db');
    }

    return factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _schemaVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE printers (
        id                INTEGER PRIMARY KEY AUTOINCREMENT,
        name              TEXT    NOT NULL,
        manufacturer      TEXT,
        model             TEXT,
        serial_number     TEXT,
        purchase_date     TEXT,
        total_print_hours REAL    NOT NULL DEFAULT 0,
        nozzle_type       TEXT,
        nozzle_size       TEXT,
        build_plate       TEXT,
        notes             TEXT,
        archived          INTEGER NOT NULL DEFAULT 0,
        created_at        TEXT    NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE tasks (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        name            TEXT    NOT NULL,
        description     TEXT,
        interval_hours  REAL,
        interval_days   INTEGER,
        interval_months INTEGER,
        category        TEXT,
        sort_order      INTEGER NOT NULL DEFAULT 100,
        is_default      INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE printer_tasks (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        printer_id      INTEGER NOT NULL REFERENCES printers(id) ON DELETE CASCADE,
        task_id         INTEGER NOT NULL REFERENCES tasks(id)    ON DELETE CASCADE,
        interval_hours  REAL,
        interval_days   INTEGER,
        interval_months INTEGER,
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

    await db.execute(
      'CREATE INDEX idx_printer_tasks_printer ON printer_tasks(printer_id)',
    );
    await db.execute(
      'CREATE INDEX idx_log_entries_printer ON log_entries(printer_id)',
    );

    await _seedTaskDefinitions(db);
  }

  /// A starting library of common 3D-printer maintenance jobs. Fully editable
  /// and deletable by the user afterwards.
  Future<void> _seedTaskDefinitions(Database db) async {
    await _insertLibraryEntries(db, defaultTaskLibrary, onlyMissing: false);
  }

  /// Inserts library entries that are not already present by name. The upgrade
  /// path uses `onlyMissing: true` so an existing install gains the full library
  /// without ever ending up with two entries sharing a name. Note that an entry
  /// the user had deleted does come back — the whole library is the point — but
  /// as a fresh, unscheduled entry they can delete again.
  Future<void> _insertLibraryEntries(
    Database db,
    List<LibraryEntry> entries, {
    required bool onlyMissing,
  }) async {
    final existing = <String>{};
    if (onlyMissing) {
      final rows = await db.query('tasks', columns: <String>['name']);
      existing.addAll(
        rows.map((row) => (row['name'] as String).toLowerCase()),
      );
    }

    final batch = db.batch();
    for (final entry in entries) {
      if (onlyMissing && existing.contains(entry.name.toLowerCase())) continue;
      batch.insert('tasks', entry.toMap());
    }
    await batch.commit(noResult: true);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) await _upgradeToV2(db);
  }

  /// v2 adds months-based intervals, grouped library entries, and the printer's
  /// nozzle / build-plate setup.
  Future<void> _upgradeToV2(Database db) async {
    await db.execute('ALTER TABLE printers ADD COLUMN nozzle_type TEXT');
    await db.execute('ALTER TABLE printers ADD COLUMN nozzle_size TEXT');
    await db.execute('ALTER TABLE printers ADD COLUMN build_plate TEXT');
    await db.execute('ALTER TABLE tasks ADD COLUMN interval_months INTEGER');
    await db.execute('ALTER TABLE tasks ADD COLUMN category TEXT');
    await db.execute(
      'ALTER TABLE tasks ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 100',
    );
    await db.execute(
      'ALTER TABLE tasks ADD COLUMN is_default INTEGER NOT NULL DEFAULT 0',
    );
    await db.execute(
      'ALTER TABLE printer_tasks ADD COLUMN interval_months INTEGER',
    );

    // Rename the original eight seeds to their library equivalents so any
    // schedule pointing at them survives the upgrade.
    final byName = <String, LibraryEntry>{
      for (final entry in defaultTaskLibrary) entry.name: entry,
    };
    for (final legacy in legacySeedNames.entries) {
      final replacement = byName[legacy.value];
      if (replacement == null) continue;
      await db.update(
        'tasks',
        replacement.toMap(),
        where: 'name = ?',
        whereArgs: <Object?>[legacy.key],
      );
    }

    await _insertLibraryEntries(db, defaultTaskLibrary, onlyMissing: true);
  }
}
