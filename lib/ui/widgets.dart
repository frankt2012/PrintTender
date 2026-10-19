import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/due_status.dart';
import 'macos_theme.dart';

Color dueColor(BuildContext context, DueLevel level) {
  final scheme = Theme.of(context).colorScheme;
  switch (level) {
    case DueLevel.overdue:
      return scheme.error;
    case DueLevel.dueSoon:
      return isMacOS ? MacColors.orange : const Color(0xFFB26A00);
    case DueLevel.ok:
      return isMacOS ? MacColors.green : const Color(0xFF2E7D32);
    case DueLevel.unscheduled:
      return scheme.outline;
  }
}

IconData dueIcon(DueLevel level) {
  switch (level) {
    case DueLevel.overdue:
      return Icons.error_outline;
    case DueLevel.dueSoon:
      return Icons.schedule;
    case DueLevel.ok:
      return Icons.check_circle_outline;
    case DueLevel.unscheduled:
      return Icons.remove_circle_outline;
  }
}

String formatHours(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(1);
}

String formatDate(DateTime date) => DateFormat.yMMMd().format(date);

String formatMoney(double value) => NumberFormat.simpleCurrency().format(value);

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

class DueBadge extends StatelessWidget {
  const DueBadge({super.key, required this.info, this.compact = false});

  final DueInfo info;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = dueColor(context, info.level);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.40)),
      ),
      child: Text(
        info.label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: compact ? 11 : 12,
        ),
      ),
    );
  }
}

class DueProgress extends StatelessWidget {
  const DueProgress({super.key, required this.info});

  final DueInfo info;

  @override
  Widget build(BuildContext context) {
    final color = dueColor(context, info.level);
    final value = (info.progress ?? 0).clamp(0.0, 1.0).toDouble();
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: LinearProgressIndicator(
        value: value,
        minHeight: 6,
        backgroundColor: color.withValues(alpha: 0.14),
        valueColor: AlwaysStoppedAnimation<Color>(color),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: theme.textTheme.labelMedium?.copyWith(
                letterSpacing: 0.9,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.warning_amber_rounded,
              size: 56,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text('Something went wrong', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              FilledButton.tonal(onPressed: onRetry, child: const Text('Try again')),
            ],
          ],
        ),
      ),
    );
  }
}

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = color ?? theme.colorScheme.primary;
    // On macOS the page sits on grey chrome, so a panel needs a hairline and a
    // white fill to read as raised. The translucent Material tint would
    // disappear against the window background.
    final mac = isMacOS;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: mac
            ? theme.colorScheme.surface
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(mac ? 6 : 14),
        border: mac
            ? Border.all(color: theme.colorScheme.outlineVariant)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: accent),
          const SizedBox(height: 10),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Prompts for a printer's odometer — the total print time shown on the machine.
///
/// Returns the entered reading, or `null` when the user cancels or types
/// something that isn't a number. Negative values are rejected, and an
/// unchanged value is still returned so callers can tell it apart from a cancel.
Future<double?> showPrintHoursDialog(
  BuildContext context, {
  required double currentHours,
}) async {
  return showDialog<double>(
    context: context,
    builder: (context) => _PrintHoursDialog(currentHours: currentHours),
  );
}

class _PrintHoursDialog extends StatefulWidget {
  const _PrintHoursDialog({required this.currentHours});

  final double currentHours;

  @override
  State<_PrintHoursDialog> createState() => _PrintHoursDialogState();
}

class _PrintHoursDialogState extends State<_PrintHoursDialog> {
  // Owned by the state so it is disposed with the dialog rather than leaking.
  late final TextEditingController _controller =
      TextEditingController(text: formatHours(widget.currentHours));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final parsed = double.tryParse(_controller.text.trim().replaceAll(',', '.'));
    Navigator.of(context).pop(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Total print hours'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onSubmitted: (_) => _submit(),
        decoration: const InputDecoration(
          labelText: 'Hours',
          helperText: 'The total print time your printer reports.',
          suffixText: 'h',
          border: OutlineInputBorder(),
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

/// A dropdown of suggested values with an "Other (type your own)" escape hatch.
///
/// Its value is a plain string, so callers keep storing what the user actually
/// typed — the presets are only writing help.
class PresetChoiceField extends StatefulWidget {
  const PresetChoiceField({
    super.key,
    required this.label,
    required this.presets,
    required this.onChanged,
    this.value,
    this.hint,
  });

  final String label;
  final List<String> presets;
  final ValueChanged<String?> onChanged;
  final String? value;
  final String? hint;

  @override
  State<PresetChoiceField> createState() => _PresetChoiceFieldState();
}

class _PresetChoiceFieldState extends State<PresetChoiceField> {
  static const String _other = '__other';

  late String _selection;
  late final TextEditingController _custom;

  @override
  void initState() {
    super.initState();
    final value = widget.value?.trim() ?? '';
    if (value.isEmpty) {
      _selection = '';
    } else if (widget.presets.contains(value)) {
      _selection = value;
    } else {
      _selection = _other;
    }
    _custom = TextEditingController(text: _selection == _other ? value : '');
  }

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  void _emit() {
    final resolved = _selection == _other ? _custom.text.trim() : _selection;
    widget.onChanged(resolved.isEmpty ? null : resolved);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        DropdownButtonFormField<String>(
          initialValue: _selection,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: widget.label,
            border: const OutlineInputBorder(),
          ),
          items: <DropdownMenuItem<String>>[
            const DropdownMenuItem<String>(
              value: '',
              child: Text('Not set'),
            ),
            ...widget.presets.map(
              (preset) => DropdownMenuItem<String>(
                value: preset,
                child: Text(preset, overflow: TextOverflow.ellipsis),
              ),
            ),
            const DropdownMenuItem<String>(
              value: _other,
              child: Text('Other (type your own)'),
            ),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() => _selection = value);
            _emit();
          },
        ),
        if (_selection == _other) ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: _custom,
            onChanged: (_) => _emit(),
            decoration: InputDecoration(
              labelText: '${widget.label} (your own)',
              hintText: widget.hint,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ],
    );
  }
}
