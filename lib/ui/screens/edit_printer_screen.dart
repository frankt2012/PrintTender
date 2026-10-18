import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../data/task_library.dart';
import '../widgets.dart';

/// Create or edit a printer. Returns `true` from [Navigator.pop] on save.
class EditPrinterScreen extends StatefulWidget {
  const EditPrinterScreen({super.key, this.printer});

  final Printer? printer;

  @override
  State<EditPrinterScreen> createState() => _EditPrinterScreenState();
}

class _EditPrinterScreenState extends State<EditPrinterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _repository = PrinterRepository();
  final _tasks = TaskRepository();

  late final TextEditingController _name;
  late final TextEditingController _manufacturer;
  late final TextEditingController _model;
  late final TextEditingController _serial;
  late final TextEditingController _hours;
  late final TextEditingController _nozzleSize;
  late final TextEditingController _notes;

  DateTime? _purchaseDate;
  String? _nozzleType;
  String? _buildPlate;

  /// New printers only: assign the eight essentials with the clock starting now.
  bool _seedDefaults = true;
  bool _saving = false;

  bool get _isEditing => widget.printer?.id != null;

  @override
  void initState() {
    super.initState();
    final printer = widget.printer;
    _name = TextEditingController(text: printer?.name ?? '');
    _manufacturer = TextEditingController(text: printer?.manufacturer ?? '');
    _model = TextEditingController(text: printer?.model ?? '');
    _serial = TextEditingController(text: printer?.serialNumber ?? '');
    _hours = TextEditingController(
      text: (printer?.totalPrintHours ?? 0) == 0
          ? ''
          : formatHours(printer!.totalPrintHours),
    );
    _nozzleSize = TextEditingController(text: printer?.nozzleSize ?? '');
    _notes = TextEditingController(text: printer?.notes ?? '');
    _purchaseDate = printer?.purchaseDate;
    _nozzleType = printer?.nozzleType;
    _buildPlate = printer?.buildPlate;
  }

  @override
  void dispose() {
    _name.dispose();
    _manufacturer.dispose();
    _model.dispose();
    _serial.dispose();
    _hours.dispose();
    _nozzleSize.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickPurchaseDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _purchaseDate ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1),
    );
    if (picked != null) setState(() => _purchaseDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final existing = widget.printer;
    final printer = Printer(
      id: existing?.id,
      name: _name.text.trim(),
      manufacturer: _manufacturer.text.trim(),
      model: _model.text.trim(),
      serialNumber: _serial.text.trim(),
      purchaseDate: _purchaseDate,
      totalPrintHours: double.tryParse(_hours.text.trim().replaceAll(',', '.')) ?? 0,
      nozzleType: _nozzleType,
      nozzleSize: _nozzleSize.text.trim(),
      buildPlate: _buildPlate,
      notes: _notes.text.trim(),
      archived: existing?.archived ?? false,
      createdAt: existing?.createdAt ?? DateTime.now(),
    );

    try {
      if (_isEditing) {
        await _repository.update(printer);
      } else {
        final id = await _repository.insert(printer);
        if (_seedDefaults) {
          // The clock starts now, so a machine added today does not open with
          // eight immediately-overdue jobs.
          await _tasks.seedDefaultSchedules(
            printerId: id,
            at: DateTime.now(),
            hours: printer.totalPrintHours,
          );
        }
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(context, 'Could not save printer: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit printer' : 'Add printer'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            TextFormField(
              controller: _name,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. Voron 2.4',
                border: OutlineInputBorder(),
              ),
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? 'Give it a name' : null,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _manufacturer,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Manufacturer',
                      hintText: 'Prusa',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _model,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Model',
                      hintText: 'MK4S',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _serial,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Serial number',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: _pickPurchaseDate,
              borderRadius: BorderRadius.circular(4),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Purchase date',
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.calendar_today_outlined),
                ),
                child: Text(
                  _purchaseDate == null ? 'Not set' : formatDate(_purchaseDate!),
                ),
              ),
            ),
            if (_purchaseDate != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => setState(() => _purchaseDate = null),
                  icon: const Icon(Icons.clear, size: 18),
                  label: const Text('Clear date'),
                ),
              ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _hours,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Total print hours',
                helperText: 'Your best estimate — drives hour-based reminders.',
                suffixText: 'h',
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
            const SizedBox(height: 24),
            const SectionHeader(title: 'Setup'),
            PresetChoiceField(
              label: 'Nozzle type',
              presets: nozzleTypes,
              value: _nozzleType,
              hint: 'e.g. CHT brass',
              onChanged: (value) => _nozzleType = value,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nozzleSize,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Nozzle size',
                hintText: 'e.g. 0.4 mm',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            PresetChoiceField(
              label: 'Build plate installed',
              presets: buildPlateTypes,
              value: _buildPlate,
              hint: 'e.g. Textured G10',
              onChanged: (value) => _buildPlate = value,
            ),
            if (!_isEditing) ...[
              const SizedBox(height: 4),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _seedDefaults,
                onChanged: (value) =>
                    setState(() => _seedDefaults = value ?? false),
                title: const Text('Start with the eight essentials'),
                subtitle: const Text(
                  'Adds the usual jobs (nozzle, belts, fans, rods, screws…) with '
                  'their intervals counting from today. Editable afterwards.',
                ),
              ),
            ],
            const SizedBox(height: 24),
            const SectionHeader(title: 'Notes'),
            TextFormField(
              controller: _notes,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Notes',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(_isEditing ? 'Save changes' : 'Add printer'),
            ),
          ],
        ),
      ),
    );
  }
}
