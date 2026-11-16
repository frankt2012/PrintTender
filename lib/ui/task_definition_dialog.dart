import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repositories.dart';
import 'widgets.dart';

/// Create or edit one entry in the shared maintenance library.
///
/// Pops the saved [MaintenanceTask] (with its id) so a caller can use it
/// straight away — the library screen reloads, the "assign a task" sheet
/// assigns what was just created.
class TaskDefinitionDialog extends StatefulWidget {
  const TaskDefinitionDialog({super.key, this.task});

  final MaintenanceTask? task;

  @override
  State<TaskDefinitionDialog> createState() => _TaskDefinitionDialogState();
}

class _TaskDefinitionDialogState extends State<TaskDefinitionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _category = TextEditingController();
  final _hours = TextEditingController();
  final _days = TextEditingController();
  final _months = TextEditingController();

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    _name.text = task?.name ?? '';
    _description.text = task?.description ?? '';
    _category.text = task?.category ?? '';
    if (task?.intervalHours != null) {
      _hours.text = formatHours(task!.intervalHours!);
    }
    if (task?.intervalDays != null) {
      _days.text = '${task!.intervalDays}';
    }
    if (task?.intervalMonths != null) {
      _months.text = '${task!.intervalMonths}';
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _category.dispose();
    _hours.dispose();
    _days.dispose();
    _months.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final repository = TaskRepository();
    final task = MaintenanceTask(
      id: widget.task?.id,
      name: _name.text.trim(),
      description: _description.text.trim(),
      intervalHours: double.tryParse(_hours.text.trim().replaceAll(',', '.')),
      intervalDays: int.tryParse(_days.text.trim()),
      intervalMonths: int.tryParse(_months.text.trim()),
      category: _category.text.trim(),
      sortOrder: widget.task?.sortOrder ?? 100,
      isDefault: widget.task?.isDefault ?? false,
    );

    final MaintenanceTask saved;
    if (widget.task?.id != null) {
      await repository.updateDefinition(task);
      saved = task;
    } else {
      final id = await repository.insertDefinition(task);
      saved = task.copyWith(id: id);
    }

    if (!mounted) return;
    Navigator.of(context).pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.task == null ? 'New maintenance task' : 'Edit task'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _description,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _category,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  hintText: 'e.g. Motion and frame',
                  helperText: 'Groups this task in the library and the picker.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Remind me every',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
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
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Set any combination. Whichever limit is hit first wins.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
