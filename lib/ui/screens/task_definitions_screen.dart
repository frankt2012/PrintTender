import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../services/due_status.dart';
import '../widgets.dart';

/// CRUD for the shared library of maintenance task definitions.
class TaskDefinitionsScreen extends StatefulWidget {
  const TaskDefinitionsScreen({super.key});

  @override
  State<TaskDefinitionsScreen> createState() => _TaskDefinitionsScreenState();
}

class _TaskDefinitionsScreenState extends State<TaskDefinitionsScreen> {
  final _repository = TaskRepository();
  late Future<List<MaintenanceTask>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repository.definitions();
  }

  Future<void> _reload() async {
    setState(() => _future = _repository.definitions());
    await _future;
  }

  Future<void> _openEditor({MaintenanceTask? task}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _TaskDefinitionDialog(task: task),
    );
    if (saved == true) await _reload();
  }

  Future<void> _confirmDelete(MaintenanceTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete task?'),
        content: Text(
          '"${task.name}" will be removed from your library and unassigned from '
          'every printer. Past log entries are kept.',
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
    await _repository.deleteDefinition(task.id!);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Maintenance library')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('New task'),
      ),
      body: FutureBuilder<List<MaintenanceTask>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ErrorView(error: snapshot.error!, onRetry: _reload);
          }
          final tasks = snapshot.data ?? const <MaintenanceTask>[];
          if (tasks.isEmpty) {
            return const EmptyState(
              icon: Icons.library_books_outlined,
              title: 'Library is empty',
              message: 'Add reusable maintenance tasks to assign to your printers.',
            );
          }
          final items = _flatten(tasks);
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              if (item is String) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                  child: Text(
                    item.toUpperCase(),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          letterSpacing: 0.9,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                );
              }
              final task = item as MaintenanceTask;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    title: Text(task.name),
                    subtitle: Text(
                      [
                        if (task.description != null) task.description!,
                        _intervalSummary(task),
                      ].join('\n'),
                    ),
                    isThreeLine: task.description != null,
                    onTap: () => _openEditor(task: task),
                    trailing: IconButton(
                      tooltip: 'Delete',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _confirmDelete(task),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  /// Interleaves category headings into the flat, library-ordered task list.
  List<Object> _flatten(List<MaintenanceTask> tasks) {
    final items = <Object>[];
    String? current;
    for (final task in tasks) {
      final category = task.category ?? 'My tasks';
      if (category != current) {
        items.add(category);
        current = category;
      }
      items.add(task);
    }
    return items;
  }

  String _intervalSummary(MaintenanceTask task) =>
      DueStatus.describeInterval(
        hours: task.intervalHours,
        days: task.intervalDays,
        months: task.intervalMonths,
      );
}

class _TaskDefinitionDialog extends StatefulWidget {
  const _TaskDefinitionDialog({this.task});

  final MaintenanceTask? task;

  @override
  State<_TaskDefinitionDialog> createState() => _TaskDefinitionDialogState();
}

class _TaskDefinitionDialogState extends State<_TaskDefinitionDialog> {
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
    if (widget.task?.id != null) {
      await repository.updateDefinition(task);
    } else {
      await repository.insertDefinition(task);
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
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
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
