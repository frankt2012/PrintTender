import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// A published release that is newer than this build.
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.tag,
    required this.notes,
    required this.releaseUrl,
    this.apkUrl,
    this.dmgUrl,
  });

  /// Without the leading `v`: `1.3.0`.
  final String version;

  /// The tag as published: `v1.3.0`.
  final String tag;

  /// The release notes body.
  final String notes;

  /// The release page, which is how macOS offers the download.
  final String releaseUrl;

  /// The Android asset, when the release has one.
  final String? apkUrl;

  /// The macOS disk image, when the release has one.
  final String? dmgUrl;

  bool get hasApk => apkUrl != null;

  bool get hasDmg => dmgUrl != null;
}

/// A check or download that could not complete, with a message fit for the UI.
class UpdateException implements Exception {
  const UpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Talks to the project's GitHub releases.
///
/// This is the only place in the app that uses the network. It is deliberately
/// small: one unauthenticated request for the latest release, and, on Android,
/// one download of the APK that request points at.
abstract final class Updater {
  static const String _repository = 'frankt2012/PrintTender';
  static const MethodChannel _channel = MethodChannel(
    'printer_maintenance/updates',
  );

  static bool get isAndroid => defaultTargetPlatform == TargetPlatform.android;

  /// Compares dotted numeric versions, ignoring a leading `v` and any `+build`
  /// suffix. Positive when [a] is newer than [b].
  static int compareVersions(String a, String b) {
    final left = _numericParts(a);
    final right = _numericParts(b);
    final length = left.length > right.length ? left.length : right.length;
    for (var i = 0; i < length; i++) {
      final l = i < left.length ? left[i] : 0;
      final r = i < right.length ? right[i] : 0;
      if (l != r) return l.compareTo(r);
    }
    return 0;
  }

  static List<int> _numericParts(String version) {
    final cleaned = version
        .trim()
        .replaceFirst(RegExp(r'^[vV]'), '')
        .split('+')
        .first;
    return cleaned.split('.').map((part) {
      final digits = RegExp(r'^\d+').firstMatch(part);
      return digits == null ? 0 : int.tryParse(digits.group(0)!) ?? 0;
    }).toList();
  }

  /// Parses a GitHub release document. Pure, so it can be tested without a
  /// network, and tolerant: anything unexpected yields null.
  static UpdateInfo? parseRelease(String body) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;

    final tag = decoded['tag_name'];
    final releaseUrl = decoded['html_url'];
    if (tag is! String || releaseUrl is! String) return null;

    String? apkUrl;
    String? dmgUrl;
    final assets = decoded['assets'];
    if (assets is List) {
      for (final asset in assets) {
        if (asset is! Map) continue;
        final name = asset['name'];
        final url = asset['browser_download_url'];
        if (name is! String || url is! String) continue;
        if (name.endsWith('.apk')) apkUrl = url;
        if (name.endsWith('.dmg')) dmgUrl = url;
      }
    }

    return UpdateInfo(
      version: tag.replaceFirst(RegExp(r'^[vV]'), ''),
      tag: tag,
      notes: decoded['body'] is String ? decoded['body'] as String : '',
      releaseUrl: releaseUrl,
      apkUrl: apkUrl,
      dmgUrl: dmgUrl,
    );
  }

  /// The installed version, without the build number.
  static Future<String> currentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  /// The installed version as shown in Settings, or null when the platform
  /// cannot report it (which happens in tests, where the plugin is absent).
  static Future<String?> currentVersionLabel() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return '${info.version} (build ${info.buildNumber})';
    } catch (error) {
      debugPrint('Updates: could not read the app version ($error)');
      return null;
    }
  }

  /// The latest release, whatever its version.
  ///
  /// Throws [UpdateException] when GitHub cannot be reached or answers with
  /// something unexpected, so callers can tell "no update" from "check failed".
  static Future<UpdateInfo> fetchLatest() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(
        Uri.parse('https://api.github.com/repos/$_repository/releases/latest'),
      );
      request.headers.set(HttpHeaders.userAgentHeader, 'PrintTender');
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        throw UpdateException(
          'GitHub answered HTTP ${response.statusCode}.',
        );
      }
      final release = parseRelease(body);
      if (release == null) {
        throw const UpdateException('That release could not be read.');
      }
      return release;
    } on UpdateException {
      rethrow;
    } catch (error) {
      throw UpdateException('Could not reach GitHub ($error).');
    } finally {
      client.close(force: true);
    }
  }

  /// The newer release, or null when this build is current.
  static Future<UpdateInfo?> checkForUpdate() async {
    final String current;
    try {
      current = await currentVersion();
    } catch (error) {
      throw UpdateException('Could not read the installed version ($error).');
    }
    final latest = await fetchLatest();
    return compareVersions(latest.version, current) > 0 ? latest : null;
  }

  /// Downloads the APK into the cache folder the FileProvider shares.
  static Future<File> downloadApk(
    UpdateInfo update, {
    void Function(int received, int total)? onProgress,
  }) {
    return _download(
      update.apkUrl,
      'PrintTender-${update.version}.apk',
      missing: 'That release has no APK.',
      onProgress: onProgress,
    );
  }

  /// Downloads the macOS disk image. The app is sandboxed and cannot install
  /// it itself, so the caller opens the image and hands the drag to the user.
  static Future<File> downloadDmg(
    UpdateInfo update, {
    void Function(int received, int total)? onProgress,
  }) {
    return _download(
      update.dmgUrl,
      'PrintTender-${update.version}.dmg',
      missing: 'That release has no DMG.',
      onProgress: onProgress,
    );
  }

  static Future<File> _download(
    String? url,
    String fileName, {
    required String missing,
    void Function(int received, int total)? onProgress,
  }) async {
    if (url == null) {
      throw UpdateException(missing);
    }

    final directory = Directory(
      p.join((await getTemporaryDirectory()).path, 'updates'),
    );
    await directory.create(recursive: true);
    final file = File(p.join(directory.path, fileName));

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set(HttpHeaders.userAgentHeader, 'PrintTender');
      final response = await request.close();
      if (response.statusCode != 200) {
        throw UpdateException(
          'The download failed (HTTP ${response.statusCode}).',
        );
      }
      final total = response.contentLength;
      var received = 0;
      final sink = file.openWrite();
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
      } finally {
        await sink.close();
      }
      if (received == 0) {
        throw const UpdateException('The download was empty.');
      }
      return file;
    } on UpdateException {
      rethrow;
    } catch (error) {
      throw UpdateException('The download failed ($error).');
    } finally {
      client.close(force: true);
    }
  }

  /// Opens a downloaded file with its default handler; a DMG mounts in Finder.
  static Future<bool> openFile(File file) async {
    try {
      return await launchUrl(
        Uri.file(file.path),
        mode: LaunchMode.externalApplication,
      );
    } catch (error) {
      debugPrint('Updates: could not open the download ($error)');
      return false;
    }
  }

  /// Whether Android will let this app open the package installer.
  static Future<bool> canInstall() async {
    if (!isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('canInstallPackages') ?? false;
    } on MissingPluginException {
      return false;
    } catch (error) {
      debugPrint('Updates: could not read the install permission ($error)');
      return false;
    }
  }

  /// The per-app "install unknown apps" switch.
  static Future<bool> openInstallSettings() async {
    if (!isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('openInstallSettings') ?? false;
    } on MissingPluginException {
      return false;
    } catch (error) {
      debugPrint('Updates: could not open the install settings ($error)');
      return false;
    }
  }

  /// Hands the downloaded APK to Android's installer.
  static Future<bool> installApk(File file) async {
    if (!isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('installApk', <String, Object?>{
            'path': file.path,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } catch (error) {
      debugPrint('Updates: could not start the installer ($error)');
      return false;
    }
  }

  /// Opens the release page in the default browser.
  static Future<bool> openReleasePage(UpdateInfo update) async {
    try {
      return await launchUrl(
        Uri.parse(update.releaseUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (error) {
      debugPrint('Updates: could not open the release page ($error)');
      return false;
    }
  }
}
