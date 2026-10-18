import 'package:flutter/foundation.dart';

DateTime? _parseDate(Object? value) {
  if (value == null) return null;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

String? _trimOrNull(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

// ---------------------------------------------------------------------------
// Printer
// ---------------------------------------------------------------------------

@immutable
class Printer {
  final int? id;
  final String name;
  final String? manufacturer;
  final String? model;
  final String? serialNumber;
  final DateTime? purchaseDate;
  final double totalPrintHours;
  final String? nozzleType;
  final String? nozzleSize;
  final String? buildPlate;
  final String? notes;
  final bool archived;
  final DateTime createdAt;

  const Printer({
    this.id,
    required this.name,
    this.manufacturer,
    this.model,
    this.serialNumber,
    this.purchaseDate,
    this.totalPrintHours = 0,
    this.nozzleType,
    this.nozzleSize,
    this.buildPlate,
    this.notes,
    this.archived = false,
    required this.createdAt,
  });

  /// "Voron 2.4 (LDO)" — falls back to just the name.
  String get subtitle {
    final parts = <String>[
      if (_trimOrNull(manufacturer) != null) manufacturer!.trim(),
      if (_trimOrNull(model) != null) model!.trim(),
    ];
    return parts.join(' ');
  }

  /// "0.4 mm brass" — nozzle type and size, either of which may be missing.
  String get nozzleLabel =>
      [nozzleSize, nozzleType].where((v) => _trimOrNull(v) != null).map((v) => v!.trim()).join(' ');

  Printer copyWith({
    int? id,
    String? name,
    String? manufacturer,
    String? model,
    String? serialNumber,
    DateTime? purchaseDate,
    double? totalPrintHours,
    String? nozzleType,
    String? nozzleSize,
    String? buildPlate,
    String? notes,
    bool? archived,
    DateTime? createdAt,
  }) {
    return Printer(
      id: id ?? this.id,
      name: name ?? this.name,
      manufacturer: manufacturer ?? this.manufacturer,
      model: model ?? this.model,
      serialNumber: serialNumber ?? this.serialNumber,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      totalPrintHours: totalPrintHours ?? this.totalPrintHours,
      nozzleType: nozzleType ?? this.nozzleType,
      nozzleSize: nozzleSize ?? this.nozzleSize,
      buildPlate: buildPlate ?? this.buildPlate,
      notes: notes ?? this.notes,
      archived: archived ?? this.archived,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
        if (id != null) 'id': id,
        'name': name.trim(),
        'manufacturer': _trimOrNull(manufacturer),
        'model': _trimOrNull(model),
        'serial_number': _trimOrNull(serialNumber),
        'purchase_date': purchaseDate?.toIso8601String(),
        'total_print_hours': totalPrintHours,
        'nozzle_type': _trimOrNull(nozzleType),
        'nozzle_size': _trimOrNull(nozzleSize),
        'build_plate': _trimOrNull(buildPlate),
        'notes': _trimOrNull(notes),
        'archived': archived ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
      };

  factory Printer.fromMap(Map<String, Object?> map) => Printer(
        id: (map['id'] as num?)?.toInt(),
        name: (map['name'] as String?) ?? 'Unnamed printer',
        manufacturer: map['manufacturer'] as String?,
        model: map['model'] as String?,
        serialNumber: map['serial_number'] as String?,
        purchaseDate: _parseDate(map['purchase_date']),
        totalPrintHours: (map['total_print_hours'] as num?)?.toDouble() ?? 0,
        nozzleType: map['nozzle_type'] as String?,
        nozzleSize: map['nozzle_size'] as String?,
        buildPlate: map['build_plate'] as String?,
        notes: map['notes'] as String?,
        archived: ((map['archived'] as num?)?.toInt() ?? 0) == 1,
        createdAt: _parseDate(map['created_at']) ?? DateTime.now(),
      );
}

// ---------------------------------------------------------------------------
// MaintenanceTask — a reusable definition ("Replace nozzle")
// ---------------------------------------------------------------------------

@immutable
class MaintenanceTask {
  final int? id;
  final String name;
  final String? description;
  final double? intervalHours;
  final int? intervalDays;
  final int? intervalMonths;
  final String? category;
  final int sortOrder;
  final bool isDefault;

  const MaintenanceTask({
    this.id,
    required this.name,
    this.description,
    this.intervalHours,
    this.intervalDays,
    this.intervalMonths,
    this.category,
    this.sortOrder = 100,
    this.isDefault = false,
  });

  MaintenanceTask copyWith({
    int? id,
    String? name,
    String? description,
    double? intervalHours,
    int? intervalDays,
    int? intervalMonths,
    String? category,
    int? sortOrder,
    bool? isDefault,
  }) {
    return MaintenanceTask(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      intervalHours: intervalHours ?? this.intervalHours,
      intervalDays: intervalDays ?? this.intervalDays,
      intervalMonths: intervalMonths ?? this.intervalMonths,
      category: category ?? this.category,
      sortOrder: sortOrder ?? this.sortOrder,
      isDefault: isDefault ?? this.isDefault,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
        if (id != null) 'id': id,
        'name': name.trim(),
        'description': _trimOrNull(description),
        'interval_hours': intervalHours,
        'interval_days': intervalDays,
        'interval_months': intervalMonths,
        'category': _trimOrNull(category),
        'sort_order': sortOrder,
        'is_default': isDefault ? 1 : 0,
      };

  factory MaintenanceTask.fromMap(Map<String, Object?> map) => MaintenanceTask(
        id: (map['id'] as num?)?.toInt(),
        name: (map['name'] as String?) ?? 'Task',
        description: map['description'] as String?,
        intervalHours: (map['interval_hours'] as num?)?.toDouble(),
        intervalDays: (map['interval_days'] as num?)?.toInt(),
        intervalMonths: (map['interval_months'] as num?)?.toInt(),
        category: map['category'] as String?,
        sortOrder: (map['sort_order'] as num?)?.toInt() ?? 100,
        isDefault: ((map['is_default'] as num?)?.toInt() ?? 0) == 1,
      );
}

// ---------------------------------------------------------------------------
// PrinterTask — a definition assigned to one printer, with its own schedule.
// Carries the joined task name/description so the UI needs no second query.
// ---------------------------------------------------------------------------

@immutable
class PrinterTask {
  final int? id;
  final int printerId;
  final int taskId;
  final double? intervalHours;
  final int? intervalDays;
  final int? intervalMonths;
  final DateTime? lastDoneAt;
  final double? lastDoneHours;
  final bool enabled;
  final String taskName;
  final String? taskDescription;

  const PrinterTask({
    this.id,
    required this.printerId,
    required this.taskId,
    this.intervalHours,
    this.intervalDays,
    this.intervalMonths,
    this.lastDoneAt,
    this.lastDoneHours,
    this.enabled = true,
    required this.taskName,
    this.taskDescription,
  });

  PrinterTask copyWith({
    int? id,
    int? printerId,
    int? taskId,
    double? intervalHours,
    bool clearIntervalHours = false,
    int? intervalDays,
    bool clearIntervalDays = false,
    int? intervalMonths,
    bool clearIntervalMonths = false,
    DateTime? lastDoneAt,
    bool clearLastDoneAt = false,
    double? lastDoneHours,
    bool clearLastDoneHours = false,
    bool? enabled,
    String? taskName,
    String? taskDescription,
  }) {
    return PrinterTask(
      id: id ?? this.id,
      printerId: printerId ?? this.printerId,
      taskId: taskId ?? this.taskId,
      intervalHours:
          clearIntervalHours ? null : (intervalHours ?? this.intervalHours),
      intervalDays:
          clearIntervalDays ? null : (intervalDays ?? this.intervalDays),
      intervalMonths:
          clearIntervalMonths ? null : (intervalMonths ?? this.intervalMonths),
      lastDoneAt: clearLastDoneAt ? null : (lastDoneAt ?? this.lastDoneAt),
      lastDoneHours:
          clearLastDoneHours ? null : (lastDoneHours ?? this.lastDoneHours),
      enabled: enabled ?? this.enabled,
      taskName: taskName ?? this.taskName,
      taskDescription: taskDescription ?? this.taskDescription,
    );
  }

  factory PrinterTask.fromMap(Map<String, Object?> map) => PrinterTask(
        id: (map['id'] as num?)?.toInt(),
        printerId: (map['printer_id'] as num?)?.toInt() ?? 0,
        taskId: (map['task_id'] as num?)?.toInt() ?? 0,
        intervalHours: (map['interval_hours'] as num?)?.toDouble(),
        intervalDays: (map['interval_days'] as num?)?.toInt(),
        intervalMonths: (map['interval_months'] as num?)?.toInt(),
        lastDoneAt: _parseDate(map['last_done_at']),
        lastDoneHours: (map['last_done_hours'] as num?)?.toDouble(),
        enabled: ((map['enabled'] as num?)?.toInt() ?? 1) == 1,
        taskName: (map['task_name'] as String?) ?? 'Task',
        taskDescription: map['task_description'] as String?,
      );
}

// ---------------------------------------------------------------------------
// LogEntry — a record of maintenance actually performed
// ---------------------------------------------------------------------------

@immutable
class LogEntry {
  final int? id;
  final int printerId;
  final int? printerTaskId;
  final String title;
  final DateTime performedAt;
  final double? hoursAtService;
  final String? partsUsed;
  final double? cost;
  final String? notes;
  final DateTime createdAt;

  const LogEntry({
    this.id,
    required this.printerId,
    this.printerTaskId,
    required this.title,
    required this.performedAt,
    this.hoursAtService,
    this.partsUsed,
    this.cost,
    this.notes,
    required this.createdAt,
  });

  Map<String, Object?> toMap() => <String, Object?>{
        if (id != null) 'id': id,
        'printer_id': printerId,
        'printer_task_id': printerTaskId,
        'title': title.trim(),
        'performed_at': performedAt.toIso8601String(),
        'hours_at_service': hoursAtService,
        'parts_used': _trimOrNull(partsUsed),
        'cost': cost,
        'notes': _trimOrNull(notes),
        'created_at': createdAt.toIso8601String(),
      };

  factory LogEntry.fromMap(Map<String, Object?> map) => LogEntry(
        id: (map['id'] as num?)?.toInt(),
        printerId: (map['printer_id'] as num?)?.toInt() ?? 0,
        printerTaskId: (map['printer_task_id'] as num?)?.toInt(),
        title: (map['title'] as String?) ?? 'Maintenance',
        performedAt: _parseDate(map['performed_at']) ?? DateTime.now(),
        hoursAtService: (map['hours_at_service'] as num?)?.toDouble(),
        partsUsed: map['parts_used'] as String?,
        cost: (map['cost'] as num?)?.toDouble(),
        notes: map['notes'] as String?,
        createdAt: _parseDate(map['created_at']) ?? DateTime.now(),
      );
}
