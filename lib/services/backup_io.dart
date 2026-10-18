import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Platform plumbing for backups: hand a JSON document to the OS share sheet,
/// and let the user pick one back. Kept apart from `BackupService` so the
/// serialisation logic stays unit-testable.
///
/// The share sheet also covers desktop, where it offers "Save to file"; there is
/// no separate save-location picker on Android, which is why export goes through
/// the share sheet rather than a file dialog.
Future<void> shareBackupFile({
  required String json,
  required String fileName,
}) async {
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
