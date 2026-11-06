import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:printer_maintenance/services/updater.dart';
import 'package:printer_maintenance/ui/update_prompt.dart';

void main() {
  group('Updater.compareVersions', () {
    test('a newer patch wins', () {
      expect(Updater.compareVersions('1.2.1', '1.2.0'), greaterThan(0));
    });

    test('a leading v is ignored', () {
      expect(Updater.compareVersions('v1.2.0', '1.2.0'), 0);
    });

    test('minor numbers compare numerically, not as text', () {
      expect(Updater.compareVersions('1.10.0', '1.9.0'), greaterThan(0));
    });

    test('a missing patch counts as zero', () {
      expect(Updater.compareVersions('1.2', '1.2.0'), 0);
    });

    test('an older version is negative', () {
      expect(Updater.compareVersions('0.9.0', '1.0.0'), lessThan(0));
    });
  });

  group('Updater.parseRelease', () {
    String release({
      String tag = 'v1.3.0',
      bool withApk = true,
      bool withDmg = true,
    }) {
      return jsonEncode(<String, Object?>{
        'tag_name': tag,
        'html_url':
            'https://github.com/frankt2012/PrintTender/releases/tag/$tag',
        'body': "## What's new\n\n- Updates",
        'assets': <Object?>[
          if (withDmg)
            <String, Object?>{
              'name': 'PrintTender-1.3.0.dmg',
              'browser_download_url': 'https://example.test/app.dmg',
            },
          if (withApk)
            <String, Object?>{
              'name': 'PrintTender-1.3.0.apk',
              'browser_download_url': 'https://example.test/app.apk',
            },
        ],
      });
    }

    test('reads the version, page and both assets', () {
      final info = Updater.parseRelease(release())!;

      expect(info.version, '1.3.0');
      expect(info.tag, 'v1.3.0');
      expect(info.apkUrl, 'https://example.test/app.apk');
      expect(info.hasApk, isTrue);
      expect(info.dmgUrl, 'https://example.test/app.dmg');
      expect(info.hasDmg, isTrue);
      expect(info.releaseUrl, endsWith('/v1.3.0'));
      expect(info.notes, contains('Updates'));
    });

    test('a release without an APK still parses', () {
      final info = Updater.parseRelease(release(withApk: false))!;

      expect(info.apkUrl, isNull);
      expect(info.hasApk, isFalse);
      expect(info.hasDmg, isTrue);
    });

    test('a release without a DMG still parses', () {
      final info = Updater.parseRelease(release(withDmg: false))!;

      expect(info.dmgUrl, isNull);
      expect(info.hasDmg, isFalse);
      expect(info.hasApk, isTrue);
    });

    test('invalid JSON is rejected', () {
      expect(Updater.parseRelease('not json'), isNull);
    });

    test('a document without a tag is rejected', () {
      expect(
        Updater.parseRelease(jsonEncode(<String, Object?>{'body': 'x'})),
        isNull,
      );
    });
  });

  group('summariseNotes', () {
    test('drops heading hashes and bold markers', () {
      expect(
        summariseNotes("## What's new\n\n- **Updates**\n- Battery"),
        "What's new\n- Updates\n- Battery",
      );
    });

    test('long notes are cut with an ellipsis', () {
      final notes = List<String>.generate(14, (i) => '- line $i').join('\n');
      final summary = summariseNotes(notes);

      expect(summary.split('\n'), hasLength(11));
      expect(summary, endsWith('…'));
    });

    test('empty notes still say something useful', () {
      expect(summariseNotes('   '), contains('newer version'));
    });

    test('the install footer and checksums are left out', () {
      final notes =
          '### Added\n'
          '- Updates\n'
          '\n'
          '## Installing\n'
          'macOS — drag the app.\n'
          '\n'
          '## Checksums\n'
          '```\nabc123\n```';

      expect(summariseNotes(notes), 'Added\n- Updates');
    });
  });
}
