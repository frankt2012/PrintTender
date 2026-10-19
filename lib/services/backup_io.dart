import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Platform plumbing for backups: write a JSON document where the user asks for
/// it, and let them pick one back. Kept apart from `BackupService` so the
/// serialisation logic stays unit-testable.

/// The desktop targets all have a real save panel; Android does not.
bool get _hasSavePanel =>
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.windows ||
    defaultTargetPlatform == TargetPlatform.linux;

/// Saves [json] as [fileName], returning the path it was written to, or `null`
/// if the user cancelled or the platform can only hand it to the share sheet.
///
/// Desktop gets an ordinary save panel. Android has no save panel, so the file
/// goes to a temporary directory and out through the system share sheet, which
/// offers "Save to Files", Drive, email and so on.
Future<String?> shareBackupFile({
  required String json,
  required String fileName,
}) async {
  if (_hasSavePanel) {
    final location = await getSaveLocation(
      suggestedName: fileName,
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(label: 'JSON backup', extensions: <String>['json']),
      ],
    );
    if (location == null) return null;
    await File(location.path).writeAsString(json);
    return location.path;
  }

  final directory = await getTemporaryDirectory();
  final file = File(p.join(directory.path, fileName));
  await file.writeAsString(json);

  await SharePlus.instance.share(
    ShareParams(
      files: <XFile>[
        XFile(file.path, mimeType: 'application/json', name: fileName),
      ],
      subject: 'Printer maintenance backup',
    ),
  );
  return null;
}

/// Returns the contents of the chosen backup file, or `null` if the user
/// cancelled.
Future<String?> pickBackupFile() async {
  const typeGroup = XTypeGroup(
    label: 'JSON backup',
    extensions: <String>['json'],
    mimeTypes: <String>['application/json'],
  );
  final file = await openFile(acceptedTypeGroups: <XTypeGroup>[typeGroup]);
  if (file == null) return null;
  return file.readAsString();
}
