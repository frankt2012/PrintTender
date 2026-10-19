import 'package:flutter/material.dart';

import 'macos_theme.dart';

/// Marks the sheet panel itself, so it can be measured or targeted.
const Key macSheetPanelKey = ValueKey<String>('macSheetPanel');

/// Pushes [builder] the ordinary way on Android, and as a macOS sheet on the
/// desktop: a panel that drops from just under the title bar over a dimmed
/// window. That is where Mac apps put "add", "edit" and picker flows, rather
/// than stacking a whole new window on top of the current one.
Route<T> pushPage<T>(
  WidgetBuilder builder, {
  double maxWidth = 820,
  double? maxHeight,
  String? name,
}) {
  final settings = RouteSettings(name: name);
  if (!isMacOS) {
    return MaterialPageRoute<T>(builder: builder, settings: settings);
  }
  return _MacSheetRoute<T>(
    builder: builder,
    maxWidth: maxWidth,
    maxHeight: maxHeight,
    settings: settings,
  );
}

class _MacSheetRoute<T> extends PageRouteBuilder<T> {
  _MacSheetRoute({
    required WidgetBuilder builder,
    required double maxWidth,
    required double? maxHeight,
    super.settings,
  }) : super(
         opaque: false,
         // A sheet is modal: clicking the dimmed window behind it does nothing.
         barrierDismissible: false,
         barrierColor: const Color(0x40000000),
         transitionDuration: const Duration(milliseconds: 240),
         reverseTransitionDuration: const Duration(milliseconds: 180),
         pageBuilder: (context, animation, secondaryAnimation) =>
             _MacSheetPanel(
               maxWidth: maxWidth,
               maxHeight: maxHeight,
               child: builder(context),
             ),
         transitionsBuilder: (context, animation, secondaryAnimation, child) {
           final curved = CurvedAnimation(
             parent: animation,
             curve: Curves.easeOutCubic,
             reverseCurve: Curves.easeInCubic,
           );
           return FadeTransition(
             opacity: curved,
             child: SlideTransition(
               position: Tween<Offset>(
                 begin: const Offset(0, -0.05),
                 end: Offset.zero,
               ).animate(curved),
               child: child,
             ),
           );
         },
       );
}

class _MacSheetPanel extends StatelessWidget {
  const _MacSheetPanel({
    required this.child,
    required this.maxWidth,
    required this.maxHeight,
  });

  final Widget child;
  final double maxWidth;
  final double? maxHeight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Clears the traffic-light strip the window reserves at the top.
      padding: const EdgeInsets.fromLTRB(24, 34, 24, 24),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: maxWidth,
            maxHeight: maxHeight ?? double.infinity,
          ),
          child: DecoratedBox(
            key: macSheetPanelKey,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x38000000),
                  blurRadius: 40,
                  offset: Offset(0, 16),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
