import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/repositories.dart';
import '../mac_controls.dart';
import '../macos_theme.dart';
import '../widgets.dart';

/// Records a maintenance job. Optionally pre-filled with a printer and one of
/// its scheduled tasks. Returns `true` from [Navigator.pop] when something was
/// logged.
class AddLogEntryScreen extends StatefulWidget {
  const AddLogEntryScreen({super.key, this.initialPrinter, this.initialSchedule});

  final Printer? initialPrinter;
  final PrinterTask? initialSchedule;

  @override
  State<AddLogEntryScreen> createState() => _AddLogEntryScreenState();
}

class _AddLogEntryScreenState extends State<AddLogEntryScreen> {
  static const int _adHocValue = -1;

  final _formKey = GlobalKey<FormState>();
  final _printers = PrinterRepository();
  final _tasks = TaskRepository();
  final _logs = LogRepository();

  final _title = TextEditingController();
  final _hours = TextEditingController();
  final _parts = TextEditingController();
  final _cost = TextEditingController();
  final _notes = TextEditingController();

  List<Printer> _printerOptions = const <Printer>[];
  List<PrinterTask> _scheduleOptions = const <PrinterTask>[];

  /// Dropdowns are keyed by id rather than by model object, because [Printer]
  /// has no value equality and an instance arriving from another screen would
  /// never match the freshly-loaded options.
  int? _selectedPrinterId;

  int _selectedTaskValue = _adHocValue;
  DateTime _performedAt = DateTime.now();
  bool _loading = true;
  bool _saving = false;

  static Printer? _find(List<Printer> printers, int? id) {
    for (final printer in printers) {
      if (printer.id == id) return printer;
    }
    return null;
  }

  Printer? get _printer => _find(_printerOptions, _selectedPrinterId);

  /// Whether a print-hour reading is meaningful for the current selection: an
  /// ad-hoc job just records where the odometer stood, and an hour-scheduled
  /// task needs it as a baseline. A day- or month-only task has no use for it.
  bool get _showHours {
    final schedule = _selectedSchedule;
    return schedule == null || schedule.intervalHours != null;
  }

  /// Seeds the hours field with the printer's current reading, so the usual
  /// action is accepting it or typing the newer number.
  void _prefillHours(Printer? printer) {
    _hours.text = printer == null ? '' : formatHours(printer.totalPrintHours);
  }

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _title.dispose();
    _hours.dispose();
    _parts.dispose();
    _cost.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final printers = await _printers.all();

    int? printerId = widget.initialPrinter?.id ??
        widget.initialSchedule?.printerId;
    if (printerId == null || !printers.any((p) => p.id == printerId)) {
      printerId = printers.isEmpty ? null : printers.first.id;
    }

    var schedules = const <PrinterTask>[];
    if (printerId != null) {
      schedules = await _tasks.schedulesFor(printerId);
    }

    final preselected = widget.initialSchedule;
    final matchIndex = preselected == null
        ? -1
        : schedules.indexWhere((s) => s.id == preselected.id);

    if (!mounted) return;
    setState(() {
      _printerOptions = printers;
      _selectedPrinterId = printerId;
      _scheduleOptions = schedules;
      _prefillHours(_find(printers, printerId));
      if (matchIndex >= 0) {
        _selectedTaskValue = schedules[matchIndex].id!;
        _title.text = schedules[matchIndex].taskName;
      }
      _loading = false;
    });
  }

  Future<void> _onPrinterChanged(int? printerId) async {
    if (printerId == null) return;
    final selected = _find(_printerOptions, printerId);
    setState(() {
      _selectedPrinterId = printerId;
      _selectedTaskValue = _adHocValue;
      _scheduleOptions = const <PrinterTask>[];
      _prefillHours(selected);
      _loading = true;
    });
    final schedules = await _tasks.schedulesFor(printerId);
    if (!mounted) return;
    setState(() {
      _scheduleOptions = schedules;
      _loading = false;
    });
  }

  void _onTaskChanged(int? value) {
    if (value == null) return;
    setState(() {
      _selectedTaskValue = value;
      final match = _scheduleOptions.where((s) => s.id == value);
      _title.text = match.isEmpty ? '' : match.first.taskName;
    });
  }

  PrinterTask? get _selectedSchedule {
    if (_selectedTaskValue == _adHocValue) return null;
    for (final schedule in _scheduleOptions) {
      if (schedule.id == _selectedTaskValue) return schedule;
    }
    return null;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _performedAt,
      firstDate: DateTime(now.year - 10),
      lastDate: now,
    );
    if (picked != null) setState(() => _performedAt = picked);
  }

  double? get _hoursValue {
    final raw = _hours.text.trim().replaceAll(',', '.');
    if (raw.isEmpty) return null;
    return double.tryParse(raw);
  }

  Future<void> _save() async {
    final printer = _printer;
    if (printer == null) {
      showSnack(context, 'Add a printer first.');
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    final schedule = _selectedSchedule;
    final hours = _hoursValue;
    final cost = double.tryParse(_cost.text.trim().replaceAll(',', '.'));

    setState(() => _saving = true);
    try {
      await _logs.insert(LogEntry(
        printerId: printer.id!,
        printerTaskId: schedule?.id,
        title: schedule?.taskName ?? _title.text.trim(),
        performedAt: _performedAt,
        hoursAtService: hours,
        partsUsed: _parts.text.trim(),
        cost: cost,
        notes: _notes.text.trim(),
        createdAt: DateTime.now(),
      ));

      if (schedule?.id != null) {
        await _tasks.markDone(
          printerTaskId: schedule!.id!,
          performedAt: _performedAt,
          hoursAtService: hours ?? schedule.lastDoneHours,
        );
      }

      // A logged reading is the odometer: if the machine now reports more hours
      // than we had recorded, move the total forward to match. Never backwards.
      if (hours != null && hours > printer.totalPrintHours) {
        await _printers.setPrintHours(printer.id!, hours);
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(context, 'Could not save log entry: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        body: const Center(child: CircularProgressIndicator()),
        bottomNavigationBar: isMacOS
            ? MacSheetButtonBar(
                onCancel: () => Navigator.of(context).pop(),
              )
            : null,
      );
    }
    if (_printerOptions.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Log maintenance'),
          automaticallyImplyLeading: !isMacOS,
        ),
        bottomNavigationBar: isMacOS
            ? MacSheetButtonBar(
                onCancel: () => Navigator.of(context).pop(),
              )
            : null,
        body: const EmptyState(
          icon: Icons.print_disabled_outlined,
          title: 'No printers',
          message: 'Add a printer before logging maintenance.',
        ),
      );
    }

    final printer = _printer;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Log maintenance'),
        automaticallyImplyLeading: !isMacOS,
      ),
      bottomNavigationBar: isMacOS
          ? MacSheetButtonBar(
              onCancel: () => Navigator.of(context).pop(),
              onDone: _save,
              doneLabel: 'Save Entry',
              busy: _saving,
            )
          : null,
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 16, 16, isMacOS ? 16 : 96),
          children: [
            DropdownButtonFormField<int>(
              initialValue: _selectedPrinterId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Printer',
                border: OutlineInputBorder(),
              ),
              items: _printerOptions
                  .map((p) => DropdownMenuItem<int>(
                        value: p.id,
                        child: Text(
                          p.subtitle.isEmpty
                              ? p.name
                              : '${p.name}  ·  ${p.subtitle}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ))
                  .toList(),
              onChanged: _saving ? null : _onPrinterChanged,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: _selectedTaskValue,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Task',
                helperText:
                    'Pick a scheduled task to reset its timer, or log a one-off job.',
                border: OutlineInputBorder(),
              ),
              items: <DropdownMenuItem<int>>[
                const DropdownMenuItem<int>(
                  value: _adHocValue,
                  child: Text('One-off / other'),
                ),
                ..._scheduleOptions.map(
                  (s) => DropdownMenuItem<int>(
                    value: s.id,
                    child: Text(s.taskName, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
              onChanged: _saving ? null : _onTaskChanged,
            ),
            if (_selectedSchedule == null) ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: _title,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'What did you do?',
                  hintText: 'e.g. Replaced thermistor',
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? 'Describe the job' : null,
              ),
            ] else if (_selectedSchedule!.taskDescription != null) ...[
              const SizedBox(height: 12),
              Text(
                _selectedSchedule!.taskDescription!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 16),
            InkWell(
              onTap: _saving ? null : _pickDate,
              borderRadius: BorderRadius.circular(4),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Date performed',
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.calendar_today_outlined),
                ),
                child: Text(formatDate(_performedAt)),
              ),
            ),
            const SizedBox(height: 16),
            if (_showHours)
              TextFormField(
                controller: _hours,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Print hours at service',
                  helperText: printer == null
                      ? null
                      : 'Printer currently reads ${formatHours(printer.totalPrintHours)} h',
                  suffixText: 'h',
                  border: const OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return null;
                  final parsed =
                      double.tryParse(value.trim().replaceAll(',', '.'));
                  if (parsed == null) return 'Enter a number';
                  if (parsed < 0) return 'Cannot be negative';
                  return null;
                },
              )
            else
              Text(
                'This task is scheduled by calendar only, so print hours are '
                'not needed.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _parts,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Parts used',
                hintText: 'e.g. 0.4 mm brass nozzle',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _cost,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Cost',
                prefixText: r'$ ',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) return null;
                final parsed = double.tryParse(value.trim().replaceAll(',', '.'));
                if (parsed == null) return 'Enter a number';
                if (parsed < 0) return 'Cannot be negative';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notes,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notes',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            if (!isMacOS) FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: const Text('Save entry'),
            ),
          ],
        ),
      ),
    );
  }
}
