import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../services/due_status.dart';
import '../mac_controls.dart';
import '../macos_theme.dart';
import '../task_definition_dialog.dart';
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
    final saved = await showDialog<MaintenanceTask>(
      context: context,
      builder: (_) => TaskDefinitionDialog(task: task),
    );
    if (saved != null) await _reload();
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
      appBar: AppBar(
        title: const Text('Maintenance library'),
        automaticallyImplyLeading: !isMacOS,
        actions: <Widget>[
          // A floating action button would look wrong inside a macOS sheet;
          // iOS-style "+" in the title bar is where Mac puts it.
          if (isMacOS)
            IconButton(
              tooltip: 'New task',
              icon: const Icon(Icons.add),
              onPressed: () => _openEditor(),
            ),
          if (isMacOS) const SizedBox(width: 8),
        ],
      ),
      bottomNavigationBar: isMacOS
          ? MacSheetButtonBar(onDone: () => Navigator.of(context).pop())
          : null,
      floatingActionButton: isMacOS
          ? null
          : FloatingActionButton.extended(
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
            padding: EdgeInsets.fromLTRB(12, 8, 12, isMacOS ? 12 : 96),
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

