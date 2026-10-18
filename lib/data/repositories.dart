import 'database.dart';
import 'models.dart';

// ---------------------------------------------------------------------------
// Printers
// ---------------------------------------------------------------------------

class PrinterRepository {
  final AppDatabase _store = AppDatabase.instance;

  Future<List<Printer>> all({bool includeArchived = false}) async {
    final db = await _store.database;
    final rows = await db.query(
      'printers',
      where: includeArchived ? null : 'archived = 0',
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return rows.map(Printer.fromMap).toList();
  }

  Future<Printer?> byId(int id) async {
    final db = await _store.database;
    final rows = await db.query(
      'printers',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Printer.fromMap(rows.first);
  }

  Future<int> insert(Printer printer) async {
    final db = await _store.database;
    return db.insert('printers', printer.toMap());
  }

  Future<void> update(Printer printer) async {
    assert(printer.id != null, 'Cannot update a printer without an id');
    final db = await _store.database;
    await db.update(
      'printers',
      printer.toMap(),
      where: 'id = ?',
      whereArgs: <Object?>[printer.id],
    );
  }

  Future<void> delete(int id) async {
    final db = await _store.database;
    await db.delete('printers', where: 'id = ?', whereArgs: <Object?>[id]);
  }

  Future<void> setPrintHours(int id, double hours) async {
    final db = await _store.database;
    await db.update(
      'printers',
      <String, Object?>{'total_print_hours': hours},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }
}

// ---------------------------------------------------------------------------
// Task definitions + per-printer schedules
// ---------------------------------------------------------------------------

class TaskRepository {
  final AppDatabase _store = AppDatabase.instance;

  Future<List<MaintenanceTask>> definitions() async {
    final db = await _store.database;
    final rows = await db.query(
      'tasks',
      orderBy: 'sort_order ASC, name COLLATE NOCASE ASC',
    );
    return rows.map(MaintenanceTask.fromMap).toList();
  }

  /// The eight starter jobs a new printer can be seeded with.
  Future<List<MaintenanceTask>> defaultDefinitions() async {
    final db = await _store.database;
    final rows = await db.query(
      'tasks',
      where: 'is_default = 1',
      orderBy: 'sort_order ASC',
    );
    return rows.map(MaintenanceTask.fromMap).toList();
  }

  Future<int> insertDefinition(MaintenanceTask task) async {
    final db = await _store.database;
    return db.insert('tasks', task.toMap());
  }

  Future<void> updateDefinition(MaintenanceTask task) async {
    assert(task.id != null, 'Cannot update a task definition without an id');
    final db = await _store.database;
    await db.update(
      'tasks',
      task.toMap(),
      where: 'id = ?',
      whereArgs: <Object?>[task.id],
    );
  }

  Future<void> deleteDefinition(int id) async {
    final db = await _store.database;
    await db.delete('tasks', where: 'id = ?', whereArgs: <Object?>[id]);
  }

  /// Tasks assigned to a printer, with the definition joined in.
  Future<List<PrinterTask>> schedulesFor(int printerId) async {
    final db = await _store.database;
    final rows = await db.rawQuery(
      '''
      SELECT pt.*, t.name AS task_name, t.description AS task_description
      FROM printer_tasks pt
      JOIN tasks t ON t.id = pt.task_id
      WHERE pt.printer_id = ?
      ORDER BY t.name COLLATE NOCASE ASC
      ''',
      <Object?>[printerId],
    );
    return rows.map(PrinterTask.fromMap).toList();
  }

  Future<bool> isAssigned(int printerId, int taskId) async {
    final db = await _store.database;
    final rows = await db.query(
      'printer_tasks',
      columns: <String>['id'],
      where: 'printer_id = ? AND task_id = ?',
      whereArgs: <Object?>[printerId, taskId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<int> assign({
    required int printerId,
    required int taskId,
    double? intervalHours,
    int? intervalDays,
    int? intervalMonths,
  }) async {
    final db = await _store.database;
    return db.insert('printer_tasks', <String, Object?>{
      'printer_id': printerId,
      'task_id': taskId,
      'interval_hours': intervalHours,
      'interval_days': intervalDays,
      'interval_months': intervalMonths,
      'enabled': 1,
    });
  }

  /// Assigns every default task to a printer with the clock starting now, so a
  /// freshly added machine does not open with a board full of overdue jobs.
  Future<void> seedDefaultSchedules({
    required int printerId,
    required DateTime at,
    required double hours,
  }) async {
    final tasks = await defaultDefinitions();
    if (tasks.isEmpty) return;
    final db = await _store.database;
    final batch = db.batch();
    for (final task in tasks) {
      batch.insert('printer_tasks', <String, Object?>{
        'printer_id': printerId,
        'task_id': task.id,
        'interval_hours': task.intervalHours,
        'interval_days': task.intervalDays,
        'interval_months': task.intervalMonths,
        'last_done_at': at.toIso8601String(),
        'last_done_hours': hours,
        'enabled': 1,
      });
    }
    await batch.commit(noResult: true);
  }

  Future<void> updateSchedule(PrinterTask schedule) async {
    assert(schedule.id != null, 'Cannot update a schedule without an id');
    final db = await _store.database;
    await db.update(
      'printer_tasks',
      <String, Object?>{
        'interval_hours': schedule.intervalHours,
        'interval_days': schedule.intervalDays,
        'interval_months': schedule.intervalMonths,
        'last_done_at': schedule.lastDoneAt?.toIso8601String(),
        'last_done_hours': schedule.lastDoneHours,
        'enabled': schedule.enabled ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: <Object?>[schedule.id],
    );
  }

  Future<void> removeSchedule(int id) async {
    final db = await _store.database;
    await db.delete(
      'printer_tasks',
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> markDone({
    required int printerTaskId,
    required DateTime performedAt,
    double? hoursAtService,
  }) async {
    final db = await _store.database;
    await db.update(
      'printer_tasks',
      <String, Object?>{
        'last_done_at': performedAt.toIso8601String(),
        'last_done_hours': hoursAtService,
      },
      where: 'id = ?',
      whereArgs: <Object?>[printerTaskId],
    );
  }
}

// ---------------------------------------------------------------------------
// Maintenance log
// ---------------------------------------------------------------------------

class LogRepository {
  final AppDatabase _store = AppDatabase.instance;

  Future<List<LogEntry>> forPrinter(int printerId) async {
    final db = await _store.database;
    final rows = await db.query(
      'log_entries',
      where: 'printer_id = ?',
      whereArgs: <Object?>[printerId],
      orderBy: 'performed_at DESC, id DESC',
    );
    return rows.map(LogEntry.fromMap).toList();
  }

  Future<List<LogEntry>> recent({int limit = 20}) async {
    final db = await _store.database;
    final rows = await db.query(
      'log_entries',
      orderBy: 'performed_at DESC, id DESC',
      limit: limit,
    );
    return rows.map(LogEntry.fromMap).toList();
  }

  Future<int> insert(LogEntry entry) async {
    final db = await _store.database;
    return db.insert('log_entries', entry.toMap());
  }

  Future<void> delete(int id) async {
    final db = await _store.database;
    await db.delete('log_entries', where: 'id = ?', whereArgs: <Object?>[id]);
  }

  Future<double> totalCost({int? printerId}) async {
    final db = await _store.database;
    final rows = await db.rawQuery(
      printerId == null
          ? 'SELECT COALESCE(SUM(cost), 0) AS total FROM log_entries'
          : 'SELECT COALESCE(SUM(cost), 0) AS total FROM log_entries WHERE printer_id = ?',
      printerId == null ? null : <Object?>[printerId],
    );
    return (rows.first['total'] as num?)?.toDouble() ?? 0;
  }
}
