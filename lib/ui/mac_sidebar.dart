import 'package:flutter/material.dart';

import 'macos_theme.dart';

/// The source-list rail down the left edge of a macOS window: a chrome-grey
/// column separated from the content well by a single hairline.
class MacSidebar extends StatelessWidget {
  const MacSidebar({super.key, required this.children, this.width = 216});

  final List<Widget> children;
  final double width;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        border: Border(right: BorderSide(color: scheme.outlineVariant)),
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 10),
        children: children,
      ),
    );
  }
}

/// A titled group of [MacSidebarTile]s, the "PRINTERS" / "LIBRARY" headings in
/// a Finder-style source list.
class MacSidebarSection extends StatelessWidget {
  const MacSidebarSection({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 12, 5),
          child: Text(
            title.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 10.5,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        ...children,
      ],
    );
  }
}

/// A selectable row in a [MacSidebar]. When selected it fills with the system
/// accent, the way a source list highlights the current item.
class MacSidebarTile extends StatefulWidget {
  const MacSidebarTile({
    super.key,
    required this.label,
    required this.icon,
    this.selected = false,
    this.onTap,
    this.trailing,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  State<MacSidebarTile> createState() => _MacSidebarTileState();
}

class _MacSidebarTileState extends State<MacSidebarTile> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = widget.selected;
    final foreground = selected ? Colors.white : scheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: selected
                  ? MacColors.accent
                  : _hovering
                      ? scheme.onSurface.withValues(alpha: 0.06)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Row(
              children: <Widget>[
                Icon(widget.icon, size: 14, color: foreground),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    widget.label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: foreground,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                if (widget.trailing != null) ...<Widget>[
                  const SizedBox(width: 6),
                  widget.trailing!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A small count pill for a [MacSidebarTile]'s trailing edge.
class MacSidebarBadge extends StatelessWidget {
  const MacSidebarBadge({super.key, required this.count, this.color});

  final int count;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? MacColors.redFor(Theme.of(context).brightness);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

