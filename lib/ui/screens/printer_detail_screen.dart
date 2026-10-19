import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../services/due_status.dart';
import '../widgets.dart';
import 'add_log_entry_screen.dart';
import 'edit_printer_screen.dart';

class PrinterDetailScreen extends StatefulWidget {
  const PrinterDetailScreen({
    super.key,
    required this.printerId,
    this.embedded = false,
    this.onDeleted,
    this.onChanged,
  });

  final int printerId;

  /// Render as a plain pane instead of a pushed route: no [Scaffold] or
  /// `AppBar`, and the printer's own actions move into a header row. Used by
  /// the macOS sidebar shell, where the detail lives beside the printer list.
  final bool embedded;

  /// Called instead of popping when an embedded detail deletes its printer.
  final VoidCallback? onDeleted;

  /// Called after an embedded detail changes the printer, so the surrounding
  /// shell can refresh the names it is showing.
  final VoidCallback? onChanged;

  @override
  State<PrinterDetailScreen> createState() => _PrinterDetailScreenState();
}

class _PrinterDetailScreenState extends State<PrinterDetailScreen> {
  final _printers = PrinterRepository();
  final _tasks = TaskRepository();
  final _logs = LogRepository();

  Printer? _printer;
  List<PrinterTask> _schedules = const <PrinterTask>[];
  List<LogEntry> _entries = const <LogEntry>[];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final printer = await _printers.byId(widget.printerId);
      if (printer == null) {
        if (!mounted) return;
        setState(() {
          _error = 'This printer no longer exists.';
          _loading = false;
        });
        return;
      }
      final schedules = await _tasks.schedulesFor(printer.id!);
      final entries = await _logs.forPrinter(printer.id!);
      if (!mounted) return;
      setState(() {
        _printer = printer;
        _schedules = schedules;
        _entries = entries;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  // -- actions ---------------------------------------------------------------

  Future<void> _editPrinter() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EditPrinterScreen(printer: _printer)),
    );
    if (saved == true) {
      await _load();
      widget.onChanged?.call();
    }
  }

  Future<void> _deletePrinter() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete printer?'),
        content: Text(
          '"${_printer!.name}" and its maintenance history and schedule will be '
          'permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _printers.delete(widget.printerId);
    if (!mounted) return;
    if (widget.embedded) {
      widget.onDeleted?.call();
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _editHours() async {
    final printer = _printer!;
    final result = await showPrintHoursDialog(
      context,
      currentHours: printer.totalPrintHours,
    );
    if (result == null || result < 0) return;
    await _printers.setPrintHours(printer.id!, result);
    await _load();
  }

  Future<void> _addLogEntry() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddLogEntryScreen(initialPrinter: _printer),
      ),
    );
    if (saved == true) await _load();
  }

  Future<void> _assignTask() async {
    final printer = _printer!;
    final definitions = await _tasks.definitions();
    final assigned = _schedules.map((s) => s.taskId).toSet();
    final available =
        definitions.where((d) => !assigned.contains(d.id)).toList();

    if (!mounted) return;

    if (available.isEmpty) {
      showSnack(context, 'Every task in the library is already assigned.');
      return;
    }

    final chosen = await showModalBottomSheet<MaintenanceTask>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 12),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(
                'Assign a task',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ..._groupByCategory(available).entries.expand(
              (group) => <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                  child: Text(
                    group.key.toUpperCase(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          letterSpacing: 0.8,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
                ...group.value.map(
                  (task) => ListTile(
                    leading: const Icon(Icons.build_outlined),
                    title: Text(task.name),
                    subtitle: Text(
                      task.description ??
                          DueStatus.describeInterval(
                            hours: task.intervalHours,
                            days: task.intervalDays,
                            months: task.intervalMonths,
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => Navigator.of(context).pop(task),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;

    final result = await showDialog<_ScheduleResult>(
      context: context,
      builder: (_) => _ScheduleDialog(
        heading: 'Schedule "${chosen.name}"',
        taskDescription: chosen.description,
        initialHours: chosen.intervalHours,
        initialDays: chosen.intervalDays,
        initialMonths: chosen.intervalMonths,
        printerHours: printer.totalPrintHours,
      ),
    );
    if (result == null) return;

    final id = await _tasks.assign(
      printerId: printer.id!,
      taskId: chosen.id!,
      intervalHours: result.intervalHours,
      intervalDays: result.intervalDays,
      intervalMonths: result.intervalMonths,
    );
    if (result.lastDoneAt != null || result.lastDoneHours != null) {
      await _tasks.updateSchedule(PrinterTask(
        id: id,
        printerId: printer.id!,
        taskId: chosen.id!,
        intervalHours: result.intervalHours,
        intervalDays: result.intervalDays,
        intervalMonths: result.intervalMonths,
        lastDoneAt: result.lastDoneAt,
        lastDoneHours: result.lastDoneHours,
        enabled: true,
        taskName: chosen.name,
      ));
    }
    await _load();
  }

  /// Groups the picker's choices by their library category, preserving the
  /// library's own ordering. Junior tasks with no category fall under "My tasks".
  Map<String, List<MaintenanceTask>> _groupByCategory(
    List<MaintenanceTask> tasks,
  ) {
    final groups = <String, List<MaintenanceTask>>{};
    for (final task in tasks) {
      groups.putIfAbsent(task.category ?? 'My tasks', () => <MaintenanceTask>[])
          .add(task);
    }
    return groups;
  }

  Future<void> _editSchedule(PrinterTask schedule) async {
    final result = await showDialog<_ScheduleResult>(
      context: context,
      builder: (_) => _ScheduleDialog(
        heading: 'Edit "${schedule.taskName}"',
        taskDescription: schedule.taskDescription,
        initialHours: schedule.intervalHours,
        initialDays: schedule.intervalDays,
        initialMonths: schedule.intervalMonths,
        initialLastDoneAt: schedule.lastDoneAt,
        initialLastDoneHours: schedule.lastDoneHours,
        initialEnabled: schedule.enabled,
        printerHours: _printer!.totalPrintHours,
      ),
    );
    if (result == null) return;

    await _tasks.updateSchedule(PrinterTask(
      id: schedule.id,
      printerId: schedule.printerId,
      taskId: schedule.taskId,
      intervalHours: result.intervalHours,
      intervalDays: result.intervalDays,
      intervalMonths: result.intervalMonths,
      lastDoneAt: result.lastDoneAt,
      lastDoneHours: result.lastDoneHours,
      enabled: result.enabled,
      taskName: schedule.taskName,
      taskDescription: schedule.taskDescription,
    ));
    await _load();
  }

  Future<void> _markDoneNow(PrinterTask schedule) async {
    final printer = _printer!;
    final now = DateTime.now();
    await _logs.insert(LogEntry(
      printerId: printer.id!,
      printerTaskId: schedule.id,
      title: schedule.taskName,
      performedAt: now,
      hoursAtService: printer.totalPrintHours,
      createdAt: now,
    ));
    await _tasks.markDone(
      printerTaskId: schedule.id!,
      performedAt: now,
      hoursAtService: printer.totalPrintHours,
    );
    await _load();
    if (!mounted) return;
    showSnack(context, 'Logged "${schedule.taskName}"');
  }

  Future<void> _removeSchedule(PrinterTask schedule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove from schedule?'),
        content: Text(
          '"${schedule.taskName}" will no longer be tracked for this printer. '
          'History entries are kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _tasks.removeSchedule(schedule.id!);
    await _load();
  }

  Future<void> _deleteEntry(LogEntry entry) async {
    await _logs.delete(entry.id!);
    await _load();
  }

  // -- build -----------------------------------------------------------------

  int get _overdueCount => _schedules.where((s) {
        final info = DueStatus.evaluate(printer: _printer!, schedule: s);
        return info.level == DueLevel.overdue;
      }).length;

  int get _dueSoonCount => _schedules.where((s) {
        final info = DueStatus.evaluate(printer: _printer!, schedule: s);
        return info.level == DueLevel.dueSoon;
      }).length;

  @override
  Widget build(BuildContext context) {
    final printer = _printer;

    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (printer != null) _buildEmbeddedHeader(context, printer),
          Expanded(child: _buildBody(printer)),        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(printer?.name ?? 'Printer'),
        actions: [
          if (printer != null)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'edit') _editPrinter();
                if (value == 'delete') _deletePrinter();
              },
              itemBuilder: (context) => const <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  value: 'edit',
                  child: ListTile(
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Edit printer'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete_outline),
                    title: Text('Delete printer'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
        ],
      ),
      floatingActionButton: printer == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _addLogEntry,
              icon: const Icon(Icons.add),
              label: const Text('Log maintenance'),
            ),
      body: _buildBody(printer),
    );
  }

  Widget _buildBody(Printer? printer) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorView(error: _error!, onRetry: _load);
    if (printer == null) {
      return const EmptyState(
        icon: Icons.print_disabled_outlined,
        title: 'Not found',
        message: 'This printer is no longer in your workshop.',
      );
    }

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          _HeaderCard(
            printer: printer,
            overdue: _overdueCount,
            dueSoon: _dueSoonCount,
            onEditHours: _editHours,
          ),
          const TabBar(
            tabs: <Widget>[
              Tab(text: 'Schedule'),
              Tab(text: 'History'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: <Widget>[
                _buildScheduleTab(printer),
                _buildHistoryTab(printer),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The pane header used when [PrinterDetailScreen.embedded]: the printer's
  /// name and the actions that would otherwise live in the `AppBar`.
  Widget _buildEmbeddedHeader(BuildContext context, Printer printer) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              printer.name,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          OutlinedButton.icon(
            onPressed: _addLogEntry,
            icon: const Icon(Icons.add, size: 14),
            label: const Text('New Log Entry'),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Edit printer',
            icon: const Icon(Icons.edit_outlined),
            onPressed: _editPrinter,
          ),
          IconButton(
            tooltip: 'Delete printer',
            icon: const Icon(Icons.delete_outline),
            onPressed: _deletePrinter,
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleTab(Printer printer) {
    // Most urgent first: whatever has burned through the largest share of its
    // interval sits at the top, so the eye lands on what needs doing.
    final ranked = _schedules
        .map((schedule) => (
              schedule: schedule,
              info: DueStatus.evaluate(printer: printer, schedule: schedule),
            ))
        .toList()
      ..sort((a, b) =>
          (b.info.progress ?? -1).compareTo(a.info.progress ?? -1));

    return CustomScrollView(
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          sliver: SliverToBoxAdapter(
            child: OutlinedButton.icon(
              onPressed: _assignTask,
              icon: const Icon(Icons.add_task),
              label: const Text('Assign a maintenance task'),
            ),
          ),
        ),
        if (_schedules.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.checklist_rtl,
              title: 'Nothing scheduled',
              message:
                  'Assign tasks from your library to get reminded before things wear out.',
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            sliver: SliverList.separated(
              itemCount: ranked.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final row = ranked[index];
                return _ScheduleCard(
                  schedule: row.schedule,
                  info: row.info,
                  onTap: () => _editSchedule(row.schedule),
                  onMarkDone: () => _markDoneNow(row.schedule),
                  onRemove: () => _removeSchedule(row.schedule),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildHistoryTab(Printer printer) {
    if (_entries.isEmpty) {
      return const EmptyState(
        icon: Icons.history,
        title: 'No history yet',
        message: 'Logged maintenance will appear here, newest first.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: _entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final entry = _entries[index];
        return Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            title: Text(entry.title),
            subtitle: Text(_entrySubtitle(entry)),
            isThreeLine: _entrySubtitle(entry).contains('\n'),
            trailing: IconButton(
              tooltip: 'Delete entry',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _deleteEntry(entry),
            ),
          ),
        );
      },
    );
  }

  String _entrySubtitle(LogEntry entry) {
    final lines = <String>[
      formatDate(entry.performedAt) +
          (entry.hoursAtService != null
              ? '  ·  ${formatHours(entry.hoursAtService!)} h'
              : ''),
    ];
    if (entry.partsUsed != null) lines.add('Parts: ${entry.partsUsed}');
    if (entry.cost != null) lines.add('Cost: ${formatMoney(entry.cost!)}');
    if (entry.notes != null) lines.add(entry.notes!);
    return lines.join('\n');
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.printer,
    required this.overdue,
    required this.dueSoon,
    required this.onEditHours,
  });

  final Printer printer;
  final int overdue;
  final int dueSoon;
  final VoidCallback onEditHours;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (printer.subtitle.isNotEmpty)
            Text(
              printer.subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: InkWell(
                  onTap: onEditHours,
                  borderRadius: BorderRadius.circular(14),
                  child: StatCard(
                    icon: Icons.timer_outlined,
                    value: '${formatHours(printer.totalPrintHours)} h',
                    label: 'Print hours  ·  tap to edit',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatCard(
                  icon: overdue > 0 ? Icons.error_outline : Icons.check_circle_outline,
                  value: '$overdue',
                  label: overdue > 0 ? 'Overdue' : 'Nothing overdue',
                  color: overdue > 0 ? theme.colorScheme.error : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatCard(
                  icon: Icons.schedule,
                  value: '$dueSoon',
                  label: 'Due soon',
                  color: dueSoon > 0 ? const Color(0xFFB26A00) : null,
                ),
              ),
            ],
          ),
          if (printer.serialNumber != null || printer.purchaseDate != null) ...[
            const SizedBox(height: 12),
            Text(
              [
                if (printer.serialNumber != null) 'S/N ${printer.serialNumber}',
                if (printer.purchaseDate != null)
                  'Purchased ${formatDate(printer.purchaseDate!)}',
              ].join('  ·  '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (printer.notes != null) ...[
            const SizedBox(height: 8),
            Text(printer.notes!, style: theme.textTheme.bodySmall),
          ],
          if (printer.nozzleLabel.isNotEmpty ||
              printer.buildPlate != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                if (printer.nozzleLabel.isNotEmpty)
                  _SetupChip(
                    icon: Icons.local_fire_department_outlined,
                    label: 'Nozzle',
                    value: printer.nozzleLabel,
                  ),
                if (printer.buildPlate != null)
                  _SetupChip(
                    icon: Icons.layers_outlined,
                    label: 'Build plate',
                    value: printer.buildPlate!,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A small read-only "Nozzle · 0.4 mm brass" style chip for the header.
class _SetupChip extends StatelessWidget {
  const _SetupChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 15, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Schedule card
// ---------------------------------------------------------------------------

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({
    required this.schedule,
    required this.info,
    required this.onTap,
    required this.onMarkDone,
    required this.onRemove,
  });

  final PrinterTask schedule;
  final DueInfo info;
  final VoidCallback onTap;
  final VoidCallback onMarkDone;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lastDone = schedule.lastDoneAt == null
        ? 'Never recorded'
        : 'Last done ${formatDate(schedule.lastDoneAt!)}'
            '${schedule.lastDoneHours != null ? ' at ${formatHours(schedule.lastDoneHours!)} h' : ''}';

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Text(
                      schedule.taskName,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  const SizedBox(width: 8),
                  DueBadge(info: info, compact: true),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'done') onMarkDone();
                      if (value == 'remove') onRemove();
                    },
                    itemBuilder: (context) => const <PopupMenuEntry<String>>[
                      PopupMenuItem<String>(
                        value: 'done',
                        child: Text('Mark done now'),
                      ),
                      PopupMenuItem<String>(
                        value: 'remove',
                        child: Text('Remove from schedule'),
                      ),
                    ],
                  ),
                ],
              ),
              Text(
                lastDone,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              DueProgress(info: info),
              const SizedBox(height: 6),
              Text(
                'Interval: ${_intervalLabel(schedule)}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _intervalLabel(PrinterTask schedule) =>
      DueStatus.describeInterval(
        hours: schedule.intervalHours,
        days: schedule.intervalDays,
        months: schedule.intervalMonths,
      );
}

// ---------------------------------------------------------------------------
// Schedule editor dialog
// ---------------------------------------------------------------------------

class _ScheduleResult {
  const _ScheduleResult({
    this.intervalHours,
    this.intervalDays,
    this.intervalMonths,
    this.lastDoneAt,
    this.lastDoneHours,
    this.enabled = true,
  });

  final double? intervalHours;
  final int? intervalDays;
  final int? intervalMonths;
  final DateTime? lastDoneAt;
  final double? lastDoneHours;
  final bool enabled;
}

class _ScheduleDialog extends StatefulWidget {
  const _ScheduleDialog({
    required this.heading,
    required this.printerHours,
    this.taskDescription,
    this.initialHours,
    this.initialDays,
    this.initialMonths,
    this.initialLastDoneAt,
    this.initialLastDoneHours,
    this.initialEnabled = true,
  });

  final String heading;
  final String? taskDescription;
  final double printerHours;
  final double? initialHours;
  final int? initialDays;
  final int? initialMonths;
  final DateTime? initialLastDoneAt;
  final double? initialLastDoneHours;
  final bool initialEnabled;

  @override
  State<_ScheduleDialog> createState() => _ScheduleDialogState();
}

class _ScheduleDialogState extends State<_ScheduleDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _hours;
  late final TextEditingController _days;
  late final TextEditingController _months;
  late final TextEditingController _lastHours;

  DateTime? _lastDoneAt;
  bool _enabled = true;

  @override
  void initState() {
    super.initState();
    _hours = TextEditingController(
      text: widget.initialHours == null ? '' : formatHours(widget.initialHours!),
    );
    _days = TextEditingController(
      text: widget.initialDays == null ? '' : '${widget.initialDays}',
    );
    _months = TextEditingController(
      text: widget.initialMonths == null ? '' : '${widget.initialMonths}',
    );
    _lastHours = TextEditingController(
      text: widget.initialLastDoneHours == null
          ? ''
          : formatHours(widget.initialLastDoneHours!),
    );
    _lastDoneAt = widget.initialLastDoneAt;
    _enabled = widget.initialEnabled;
  }

  @override
  void dispose() {
    _hours.dispose();
    _days.dispose();
    _months.dispose();
    _lastHours.dispose();
    super.dispose();
  }

  Future<void> _pickLastDone() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _lastDoneAt ?? now,
      firstDate: DateTime(now.year - 10),
      lastDate: now,
    );
    if (picked != null) setState(() => _lastDoneAt = picked);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(_ScheduleResult(
      intervalHours: double.tryParse(_hours.text.trim().replaceAll(',', '.')),
      intervalDays: int.tryParse(_days.text.trim()),
      intervalMonths: int.tryParse(_months.text.trim()),
      lastDoneAt: _lastDoneAt,
      lastDoneHours: double.tryParse(_lastHours.text.trim().replaceAll(',', '.')),
      enabled: _enabled,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.heading),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (widget.taskDescription != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    widget.taskDescription!,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Remind me every', style: theme.textTheme.labelLarge),
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextFormField(
                      controller: _hours,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Hours',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _days,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Days',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _months,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Months',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Set any combination — whichever limit is reached first '
                  'triggers the reminder.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              const Divider(height: 28),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Last performed', style: theme.textTheme.labelLarge),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: _pickLastDone,
                borderRadius: BorderRadius.circular(4),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Date',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.calendar_today_outlined),
                  ),
                  child: Text(
                    _lastDoneAt == null ? 'Not set' : formatDate(_lastDoneAt!),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _lastHours,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Print hours at that time',
                  helperText:
                      'Printer now reads ${formatHours(widget.printerHours)} h',
                  suffixText: 'h',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _enabled,
                onChanged: (value) => setState(() => _enabled = value),
                title: const Text('Track this task'),
                subtitle: const Text('Turn off to hide it from reminders.'),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
