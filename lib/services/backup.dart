import 'dart:convert';

import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../data/database.dart';

/// Whole-database snapshot and restore, as a single portable JSON document.
///
/// Deliberately free of file and share plumbing so the round-trip can be tested
/// against the in-memory database; the platform bits live in `backup_io.dart`.
class BackupService {
  static const String appTag = 'printer_maintenance';
  static const int formatVersion = 1;

  /// Tables in dependency order: parents first, so a restore never trips a
  /// foreign key.
  static const List<String> _tables = <String>[
    'tasks',
    'printers',
    'printer_tasks',
    'log_entries',
  ];

  final AppDatabase _store = AppDatabase.instance;

  Future<Map<String, Object?>> snapshot() async {
    final db = await _store.database;
    final data = <String, Object?>{
      'app': appTag,
      'format': formatVersion,
      'exported_at': DateTime.now().toIso8601String(),
    };
    for (final table in _tables) {
      data[table] = await db.query(table);
    }
    return data;
  }

  String encode(Map<String, Object?> snapshot) =>
      const JsonEncoder.withIndent('  ').convert(snapshot);

  /// Parses and validates a backup document. Throws [FormatException] with a
  /// readable message when the file is not one of ours.
  Map<String, Object?> decode(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw const FormatException('That file is not valid JSON.');
    }
    if (decoded is! Map) {
      throw const FormatException('That file is not a backup.');
    }
    final map = Map<String, Object?>.from(decoded);
    if (map['app'] != appTag) {
      throw const FormatException('That backup came from a different app.');
    }
    final format = map['format'];
    if (format is! int) {
      throw const FormatException('That backup is missing its format version.');
    }
    if (format > formatVersion) {
      throw FormatException(
        'That backup was written by a newer version (format $format).',
      );
    }
    for (final table in _tables) {
      if (map[table] is! List) {
        throw FormatException('That backup is missing its "$table" section.');
      }
    }
    return map;
  }

  /// Replaces everything in the database with the contents of [snapshot].
  Future<void> restore(Map<String, Object?> snapshot) async {
    final rows = <String, List<Map<String, Object?>>>{
      for (final table in _tables) table: _rows(snapshot, table),
    };

    final db = await _store.database;
    await db.transaction((txn) async {
      for (final table in _tables.reversed) {
        await txn.delete(table);
      }
      for (final table in _tables) {
        for (final row in rows[table]!) {
          await txn.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    });
  }

  List<Map<String, Object?>> _rows(Map<String, Object?> snapshot, String table) {
    final raw = snapshot[table];
    if (raw is! List) {
      throw FormatException('That backup is missing its "$table" section.');
    }
    return raw
        .whereType<Map<Object?, Object?>>()
        .map(Map<String, Object?>.from)
        .toList();
  }

  /// `printer-maintenance-2026-10-17.json`
  String suggestedFileName([DateTime? now]) {
    final date = now ?? DateTime.now();
    final stamp = '${date.year.toString().padLeft(4, '0')}'
        '-${date.month.toString().padLeft(2, '0')}'
        '-${date.day.toString().padLeft(2, '0')}';
    return 'printer-maintenance-$stamp.json';
  }
}
