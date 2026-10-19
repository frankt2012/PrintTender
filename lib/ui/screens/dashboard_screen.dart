import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../services/backup.dart';
import '../../services/backup_io.dart';
import '../../services/due_status.dart';
import '../../services/notifications.dart';
import '../widgets.dart';
import 'add_log_entry_screen.dart';
import 'edit_printer_screen.dart';
import 'printer_detail_screen.dart';
import 'task_definitions_screen.dart';

class PrinterStatus {
  const PrinterStatus({
    required this.overdue,
    required this.dueSoon,
    required this.total,
  });

  final int overdue;
  final int dueSoon;
  final int total;
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _printers = PrinterRepository();
  final _tasks = TaskRepository();
  final _logs = LogRepository();

  List<Printer> _printersList = const <Printer>[];
  Map<int, PrinterStatus> _statuses = const <int, PrinterStatus>{};
  Map<int, List<PrinterTask>> _schedules = <int, List<PrinterTask>>{};
  List<AttentionItem> _attention = const <AttentionItem>[];
  List<LogEntry> _recent = const <LogEntry>[];
  Map<int, String> _printerNames = const <int, String>{};
  int _overdueCount = 0;
  double _totalCost = 0;
  bool _loading = true;
  Object? _error;
  bool _showBoard = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final printers = await _printers.all();
      final statuses = <int, PrinterStatus>{};
      final attention = <AttentionItem>[];
      final names = <int, String>{};
      var overdueCount = 0;
      var hasSchedule = false;

      for (final printer in printers) {
        names[printer.id!] = printer.name;
        final schedules = await _tasks.schedulesFor(printer.id!);
        if (schedules.isNotEmpty) hasSchedule = true;
        var overdue = 0;
        var dueSoon = 0;
        for (final schedule in schedules) {
          final info = DueStatus.evaluate(printer: printer, schedule: schedule);
          if (info.level == DueLevel.overdue) overdue++;
          if (info.level == DueLevel.dueSoon) dueSoon++;
          if (info.level == DueLevel.overdue ||
              info.level == DueLevel.dueSoon) {
            attention.add(
              AttentionItem(printer: printer, schedule: schedule, info: info),
            );
          }
        }
        overdueCount += overdue;
        _schedules[printer.id!] = schedules;
        statuses[printer.id!] = PrinterStatus(
          overdue: overdue,
          dueSoon: dueSoon,
          total: schedules.length,
        );
      }

      attention.sort((a, b) {
        final pa = a.info.progress ?? 2.0;
        final pb = b.info.progress ?? 2.0;
        return pb.compareTo(pa);
      });

      final recent = await _logs.recent(limit: 8);
      final totalCost = await _logs.totalCost();

      if (!mounted) return;
      setState(() {
        _printersList = printers;
        _statuses = statuses;
        _attention = attention;
        _recent = recent;
        _printerNames = names;
        _overdueCount = overdueCount;
        _totalCost = totalCost;
        _error = null;
        _loading = false;
      });

      // The dashboard recomputes this list on launch, after every edit and on
      // pull-to-refresh, so it is also where the morning digest is kept
      // current. It is deliberately awaited after the frame is painted, and
      // the service swallows its own failures: a reminder that will not
      // schedule must never turn a working dashboard into an error screen.
      await ReminderService.instance.sync(
        attention: attention,
        hasSchedule: hasSchedule,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _addPrinter() async {
    final saved = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const EditPrinterScreen()));
    if (saved == true) await _load();
  }

  Future<void> _openLibrary() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const TaskDefinitionsScreen()));
    await _load();
  }

  /// Writes the whole database to a JSON file and hands it to the share sheet,
  /// which is the one "save it wherever you like" affordance available on both
  /// Android and the desktop.
  Future<void> _exportBackup() async {
    final backup = BackupService();
    try {
      final json = backup.encode(await backup.snapshot());
      await shareBackupFile(json: json, fileName: backup.suggestedFileName());
    } catch (error) {
      if (!mounted) return;
      showSnack(context, 'Could not export: $error');
    }
  }

  Future<void> _importBackup() async {
    final backup = BackupService();
    final String? source;
    try {
      source = await pickBackupFile();
    } catch (error) {
      if (!mounted) return;
      showSnack(context, 'Could not open that file: $error');
      return;
    }
    if (source == null) return;

    final Map<String, Object?> snapshot;
    try {
      snapshot = backup.decode(source);
    } on FormatException catch (error) {
      if (!mounted) return;
      showSnack(context, error.message);
      return;
    }

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Replace all data?'),
        content: const Text(
          'Importing a backup deletes every printer, task and log entry on this '
          'device and replaces them with the contents of the file. This cannot '
          'be undone.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Replace'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await backup.restore(snapshot);
    } catch (error) {
      if (!mounted) return;
      showSnack(context, 'Could not import: $error');
      return;
    }
    await _load();
    if (!mounted) return;
    showSnack(context, 'Backup imported.');
  }

  Future<void> _openPrinter(int printerId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PrinterDetailScreen(printerId: printerId),
      ),
    );
    await _load();
  }

  /// Bumps a printer's odometer without leaving the dashboard, so hour-based
  /// intervals can be kept current as a two-tap habit.
  Future<void> _editHours(Printer printer) async {
    final hours = await showPrintHoursDialog(
      context,
      currentHours: printer.totalPrintHours,
    );
    if (hours == null || hours < 0) return;
    await _printers.setPrintHours(printer.id!, hours);
    await _load();
  }

  Future<void> _logFor(Printer printer, [PrinterTask? schedule]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddLogEntryScreen(
          initialPrinter: printer,
          initialSchedule: schedule,
        ),
      ),
    );
    if (saved == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Printer Maintenance'),
        actions: <Widget>[
          if (Platform.isMacOS || Platform.isWindows || Platform.isLinux)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: SegmentedButton<bool>(
                segments: const <ButtonSegment<bool>>[
                  ButtonSegment<bool>(
                    value: false,
                    label: Text('Tasks'),
                    icon: Icon(Icons.list_alt_outlined),
                  ),
                  ButtonSegment<bool>(
                    value: true,
                    label: Text('Year board'),
                    icon: Icon(Icons.calendar_view_month_outlined),
                  ),
                ],
                selected: <bool>{_showBoard},
                onSelectionChanged: (selection) {
                  setState(() => _showBoard = selection.first);
                },
              ),
            ),
          IconButton(
            tooltip: 'Maintenance library',
            icon: const Icon(Icons.library_books_outlined),
            onPressed: _openLibrary,
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (value) {
              if (value == 'export') _exportBackup();
              if (value == 'import') _importBackup();
            },
            itemBuilder: (context) => const <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'export',
                child: ListTile(
                  leading: Icon(Icons.ios_share_outlined),
                  title: Text('Export backup'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem<String>(
                value: 'import',
                child: ListTile(
                  leading: Icon(Icons.restore_outlined),
                  title: Text('Import backup'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addPrinter,
        icon: const Icon(Icons.add),
        label: const Text('Add printer'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorView(error: _error!, onRetry: _load);

    if (_printersList.isEmpty) {
      return EmptyState(
        icon: Icons.print_outlined,
        title: 'No printers yet',
        message: 'Add your first 3D printer, then assign the maintenance tasks you care about.',
        action: FilledButton.icon(
          onPressed: _addPrinter,
          icon: const Icon(Icons.add),
          label: const Text('Add printer'),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: StatCard(
                  icon: Icons.print_outlined,
                  value: '${_printersList.length}',
                  label: 'Printers',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatCard(
                  icon: _overdueCount > 0
                      ? Icons.error_outline
                      : Icons.check_circle_outline,
                  value: '$_overdueCount',
                  label: _overdueCount == 1 ? 'Task overdue' : 'Tasks overdue',
                  color: _overdueCount > 0
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatCard(
                  icon: Icons.payments_outlined,
                  value: formatMoney(_totalCost),
                  label: 'Parts spend',
                ),
              ),
            ],
          ),
          if (_attention.isNotEmpty) ...<Widget>[
            const SizedBox(height: 24),
            SectionHeader(
              title: 'Needs attention',
              trailing: '${_attention.length}',
            ),
            ..._attention.map(
              (item) => _AttentionTile(
                item: item,
                onLog: () => _logFor(item.printer, item.schedule),
                onOpenPrinter: () => _openPrinter(item.printer.id!),
              ),
            ),
          ],
          const SizedBox(height: 24),
          SectionHeader(
            title: 'My printers',
            trailing: '${_printersList.length}',
          ),
          if (_showBoard)
            _BoardView(
              printers: _printersList,
              schedules: _schedules,
              onLog: (p, t) => _logFor(p, t),
              onOpenPrinter: (p) => _openPrinter(p.id!),
            )
          else
            ..._printersList.map(
              (printer) => _PrinterTile(
                printer: printer,
                status: _statuses[printer.id!],
                onTap: () => _openPrinter(printer.id!),
                onEditHours: () => _editHours(printer),
              ),
            ),
          if (_recent.isNotEmpty) ...<Widget>[
            const SizedBox(height: 24),
            const SectionHeader(title: 'Recent activity'),
            ..._recent.map(
              (entry) => _RecentTile(
                entry: entry,
                printerName: _printerNames[entry.printerId],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AttentionTile extends StatelessWidget {
  const _AttentionTile({
    required this.item,
    required this.onLog,
    required this.onOpenPrinter,
  });

  final AttentionItem item;
  final VoidCallback onLog;
  final VoidCallback onOpenPrinter;

  @override
  Widget build(BuildContext context) {
    final color = dueColor(context, item.info.level);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        leading: Icon(dueIcon(item.info.level), color: color),
        title: Text(item.schedule.taskName),
        subtitle: Text(
          '${item.printer.name}  ·  ${item.info.label}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: onLog,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextButton(onPressed: onLog, child: const Text('Log')),
            IconButton(
              tooltip: 'Open printer',
              icon: const Icon(Icons.chevron_right),
              onPressed: onOpenPrinter,
            ),
          ],
        ),
      ),
    );
  }
}

class _PrinterTile extends StatelessWidget {
  const _PrinterTile({
    required this.printer,
    required this.status,
    required this.onTap,
    required this.onEditHours,
  });

  final Printer printer;
  final PrinterStatus? status;
  final VoidCallback onTap;
  final VoidCallback onEditHours;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final overdue = status?.overdue ?? 0;
    final dueSoon = status?.dueSoon ?? 0;
    final total = status?.total ?? 0;

    final Widget trailing;
    if (overdue > 0) {
      trailing = DueBadge(
        info: DueInfo(level: DueLevel.overdue, label: '$overdue overdue'),
      );
    } else if (dueSoon > 0) {
      trailing = DueBadge(
        info: DueInfo(level: DueLevel.dueSoon, label: '$dueSoon due soon'),
      );
    } else if (total > 0) {
      trailing = DueBadge(
        info: const DueInfo(level: DueLevel.ok, label: 'All good'),
      );
    } else {
      trailing = DueBadge(
        info: const DueInfo(level: DueLevel.unscheduled, label: 'No schedule'),
      );
    }

    final subtitle = <String>[
      if (printer.subtitle.isNotEmpty) printer.subtitle,
      '${formatHours(printer.totalPrintHours)} h',
      '$total tracked',
    ].join('  ·  ');

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Icon(
            Icons.print_outlined,
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
        title: Text(printer.name),
        subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            trailing,
            IconButton(
              tooltip: 'Update print hours',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.speed_outlined, size: 20),
              onPressed: onEditHours,
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

class _RecentTile extends StatelessWidget {
  const _RecentTile({required this.entry, this.printerName});

  final LogEntry entry;
  final String? printerName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final details = <String>[
      ?printerName,
      formatDate(entry.performedAt),
      if (entry.cost != null) formatMoney(entry.cost!),
    ].join('  ·  ');

    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: const Icon(Icons.build_outlined),
      title: Text(entry.title),
      subtitle: Text(
        details,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}


class _BoardView extends StatelessWidget {
  const _BoardView({
    required this.printers,
    required this.schedules,
    required this.onLog,
    required this.onOpenPrinter,
  });

  final List<Printer> printers;
  final Map<int, List<PrinterTask>> schedules;
  final void Function(Printer, PrinterTask) onLog;
  final void Function(Printer) onOpenPrinter;

  static const List<String> _months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final cm = now.month - 1;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: <Widget>[
                  const SizedBox(width: 110),
                  Expanded(
                    child: Row(
                      children: List<Widget>.generate(_months.length, (i) {
                        final isNow = i == cm;
                        return Expanded(
                          child: Center(
                            child: Text(
                              _months[i],
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: isNow
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurfaceVariant,
                                fontWeight: isNow ? FontWeight.w600 : null,
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(width: 140),
                ],
              ),
            ),
            const Divider(height: 16),
            ...printers.expand((p) => _buildPrinterRows(context, p, cm, theme)),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildPrinterRows(
    BuildContext context,
    Printer p,
    int cm,
    ThemeData theme,
  ) {
    final rows = <Widget>[];
    final printerSchedules = schedules[p.id!] ?? const <PrinterTask>[];
    final tasks = [...printerSchedules]..sort((a, b) => a.taskName.compareTo(b.taskName));
    for (final t in tasks) {
      final s = DueStatus.evaluate(printer: p, schedule: t);
      int col = -1;
      String note = s.label;
      if (t.intervalHours != null && t.lastDoneHours != null) {
        final hInterval = t.intervalHours!;
        final hLast = t.lastDoneHours!;
        if (s.level != DueLevel.ok && s.level != DueLevel.unscheduled) {
          col = cm;
        }
        final remaining = hInterval - (p.totalPrintHours - hLast);
        if (remaining > 0) {
          note = '${_fmtHours(remaining)} h left';
        } else if (remaining < 0) {
          note = '${_fmtHours(-remaining)} h over';
        } else {
          note = 'Due now';
        }
      } else if (t.lastDoneAt != null) {
        final last = t.lastDoneAt!;
        DateTime due;
        final im = t.intervalMonths;
        if (im != null && im > 0) {
          due = DueStatus.addMonths(last, im);
        } else {
          final id = t.intervalDays ?? 0;
          due = DateTime.utc(last.year, last.month, last.day)
              .add(Duration(days: id));
        }
        col = due.month - 1;
        if (s.level == DueLevel.overdue) {
          note = 'Overdue · ${_fmtDate(due)}';
        } else if (s.level == DueLevel.dueSoon) {
          note = 'Due soon · ${_fmtDate(due)}';
        } else {
          note = 'Due ${_fmtDate(due)}';
        }
      }
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 110,
                child: Text(
                  t.taskName,
                  style: theme.textTheme.bodyMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Expanded(
                child: Row(
                  children: List<Widget>.generate(_months.length, (i) {
                    final isNow = i == cm;
                    final isMark = i == col;
                    Color? bg;
                    if (isMark) {
                      bg = s.level == DueLevel.overdue
                          ? theme.colorScheme.errorContainer
                          : s.level == DueLevel.dueSoon
                              ? theme.colorScheme.tertiaryContainer
                              : theme.colorScheme.primaryContainer;
                    }
                    return Expanded(
                      child: Container(
                        height: 20,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(
                          color: bg,
                          borderRadius: BorderRadius.circular(4),
                          border: isNow
                              ? Border.all(color: theme.colorScheme.primary, width: 1.5)
                              : null,
                        ),
                      ),
                    );
                  }),
                ),
              ),
              SizedBox(
                width: 140,
                child: Text(
                  note,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
      rows.add(const Divider(height: 1));
    }
    if (tasks.isNotEmpty) {
      rows.insert(
        0,
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            p.name,
            style: theme.textTheme.labelLarge,
          ),
        ),
      );
    }
    return rows;
  }

  String _fmtDate(DateTime d) {
    final y = d.year.toString();
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  String _fmtHours(double h) {
    if (h.abs() < 0.05) return '0.0';
    return h.toStringAsFixed(1);
  }
}
