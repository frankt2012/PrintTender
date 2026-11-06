import 'package:flutter/material.dart';

import '../services/updater.dart';

/// Turns a release body into something readable in a dialog: headings lose
/// their hashes, bold markers go, blank lines collapse, and a long list is cut
/// with an ellipsis.
String summariseNotes(String notes, {int maxLines = 10}) {
  final lines = <String>[];
  for (final raw in notes.split('\n')) {
    // A release body carries the install steps and checksums after the
    // changelog; those belong on the page, not in an update dialog.
    if (RegExp(r'^#+\s+(Installing|Checksums)\b').hasMatch(raw.trim())) {
      break;
    }
    final line = raw
        .replaceFirst(RegExp(r'^#+\s*'), '')
        .replaceAll('**', '')
        .trimRight();
    if (line.trim().isEmpty) continue;
    lines.add(line);
  }
  if (lines.isEmpty) return 'A newer version is ready to install.';
  if (lines.length <= maxLines) return lines.join('\n');
  return '${lines.take(maxLines).join('\n')}\n…';
}

/// Shows what is new and, if the user agrees, updates the app.
///
/// On Android that means downloading the APK and opening the system installer,
/// which always asks for confirmation. Elsewhere it opens the release page,
/// because a sandboxed desktop app cannot replace itself.
Future<void> showUpdatePrompt(BuildContext context, UpdateInfo update) async {
  final installable = Updater.isAndroid;
  final canDownload = installable ? update.hasApk : update.hasDmg;
  final canInstall = installable && canDownload && await Updater.canInstall();
  if (!context.mounted) return;

  final go = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('PrintTender ${update.version} is available'),
      content: SingleChildScrollView(
        child: Text(
          summariseNotes(update.notes),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Later'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            !canDownload
                ? 'Open download page'
                : !installable
                ? 'Download update'
                : (canInstall ? 'Download & install' : 'Allow updates'),
          ),
        ),
      ],
    ),
  );
  if (go != true || !context.mounted) return;

  if (!canDownload) {
    await Updater.openReleasePage(update);
    return;
  }

  if (installable && !canInstall) {
    await Updater.openInstallSettings();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Allow updates'),
        content: const Text(
          'Switch on "Allow from this source" for PrintTender, then come back '
          'and check again. Android asks for this once.',
        ),
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
    return;
  }

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _DownloadDialog(update: update),
  );
}

class _DownloadDialog extends StatefulWidget {
  const _DownloadDialog({required this.update});

  final UpdateInfo update;

  @override
  State<_DownloadDialog> createState() => _DownloadDialogState();
}

class _DownloadDialogState extends State<_DownloadDialog> {
  double? _progress;
  String? _error;
  bool _installing = false;

  /// macOS: the DMG is mounted and the user has one drag left.
  bool _readyToDrag = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  void _onProgress(int received, int total) {
    if (!mounted) return;
    setState(() {
      _progress = total > 0 ? received / total : null;
    });
  }

  Future<void> _run() async {
    try {
      if (Updater.isAndroid) {
        final file = await Updater.downloadApk(
          widget.update,
          onProgress: _onProgress,
        );
        if (!mounted) return;
        setState(() => _installing = true);

        final started = await Updater.installApk(file);
        if (!mounted) return;
        if (!started) {
          setState(() => _error = 'Android could not open the installer.');
          return;
        }
        Navigator.of(context).pop();
        return;
      }

      // macOS: download the image and let Finder mount it. The sandbox stops
      // the app from replacing its own bundle, so the last step is the drag.
      final file = await Updater.downloadDmg(
        widget.update,
        onProgress: _onProgress,
      );
      if (!mounted) return;
      final opened = await Updater.openFile(file);
      if (!mounted) return;
      if (!opened) {
        setState(() => _error = 'The DMG downloaded but could not be opened.');
        return;
      }
      setState(() => _readyToDrag = true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final percent = _progress == null ? null : (_progress! * 100).round();

    return AlertDialog(
      title: Text('PrintTender ${widget.update.version}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (_error != null)
            Text(_error!)
          else if (_readyToDrag)
            const Text(
              'The disk image is open in Finder. Drag PrintTender onto '
              'Applications, then quit and reopen the app.',
            )
          else ...<Widget>[
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 12),
            Text(
              _installing
                  ? 'Opening the installer…'
                  : percent == null
                  ? 'Downloading…'
                  : 'Downloading… $percent%',
            ),
          ],
        ],
      ),
      actions: <Widget>[
        if (_error != null || _readyToDrag)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
      ],
    );
  }
}
