import 'package:flutter/material.dart';

/// One choice in a [MacSegmentedControl].
class MacSegment<T> {
  const MacSegment({required this.value, required this.label, this.icon});

  final T value;
  final String label;
  final IconData? icon;
}

/// A hand-built stand-in for `NSSegmentedControl`: a recessed track with the
/// selected segment raised on a light capsule.
///
/// Material's `SegmentedButton` is pill-shaped with a filled accent, which is
/// the single most Android-looking control in the app. This keeps the same
/// behaviour with AppKit's geometry.
class MacSegmentedControl<T> extends StatelessWidget {
  const MacSegmentedControl({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
  });

  final List<MacSegment<T>> segments;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1C1C1E) : const Color(0xFFE4E4E6),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: dark ? const Color(0xFF3A3A3C) : const Color(0xFFD0D0D2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final segment in segments)
            _SegmentButton<T>(
              segment: segment,
              selected: segment.value == value,
              selectedColor: dark ? const Color(0xFF515154) : Colors.white,
              onSelected: () => onChanged(segment.value),
            ),
        ],
      ),
    );
  }
}

class _SegmentButton<T> extends StatefulWidget {
  const _SegmentButton({
    required this.segment,
    required this.selected,
    required this.selectedColor,
    required this.onSelected,
  });

  final MacSegment<T> segment;
  final bool selected;
  final Color selectedColor;
  final VoidCallback onSelected;

  @override
  State<_SegmentButton<T>> createState() => _SegmentButtonState<T>();
}

class _SegmentButtonState<T> extends State<_SegmentButton<T>> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground =
        widget.selected ? scheme.onSurface : scheme.onSurfaceVariant;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onSelected,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: widget.selected
                ? widget.selectedColor
                : _hovering
                    ? scheme.onSurface.withValues(alpha: 0.06)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
            boxShadow: widget.selected
                ? const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x1A000000),
                      blurRadius: 3,
                      offset: Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (widget.segment.icon != null) ...<Widget>[
                Icon(widget.segment.icon, size: 14, color: foreground),
                const SizedBox(width: 5),
              ],
              Text(
                widget.segment.label,
                style: TextStyle(
                  fontSize: 12,
                  color: foreground,
                  fontWeight:
                      widget.selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
