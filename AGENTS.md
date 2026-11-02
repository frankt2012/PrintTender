# Working on PrintTender

## Releasing

**Nothing goes public until the user has tested it.** Do not push, tag or publish
on your own initiative. The repository is public and the user tests updates on
their own devices first. The flow is: build locally → hand it over → wait for an
explicit go-ahead → push, tag, release.

1. Make the change and bump `version:` in `pubspec.yaml` (for example
   `1.0.2+3`). The `+N` build number must increase too, and the eventual tag is
   the part before the `+`: `v1.0.2`.
2. Update anything the change made stale: `README.md` (test counts, behaviour,
   notification/signing notes) and `CHANGELOG.md` — move the `Unreleased` entry
   under `## [1.0.2] - YYYY-MM-DD`. The release workflow takes the release body
   from that section and fails if it is missing.
3. Build what the user needs to test, locally, signed with the release key (the
   APK for Android, the app for macOS). Say exactly where it is. **Do not push.**
4. When the user has tested it and said it is good: commit, `git push origin main`,
   `git tag v1.0.2`, `git push origin v1.0.2`, then watch the run
   (`gh run watch`) until both assets are attached.

The tag is what publishes — the release workflow builds the signed APK on Linux
and the DMG on macOS and attaches both to a GitHub Release.

Notes:

- The APK is signed from the `ANDROID_KEYSTORE_*` repository secrets. Never
  commit the keystore or `android/key.properties`.
- The DMG built by CI is signed ad-hoc. Locally, re-sign with the
  `PrintTender Local Signer` identity so the app keeps one code identity across
  rebuilds — see "Why the built app is re-signed" in the README.
- `PrintTender-<version>.dmg` and `PrintTender-<version>.apk` on the release are
  what users download; the repository by itself has no installers.

## Conventions

- Do not run `dart format`. The tree is not formatter-clean and a format pass
  would rewrite nearly every file; hand-edit indentation instead.
- Do not run `flutter test integration_test/` against a real phone — it wipes the
  device's data.
- Keep the macOS look gated on `isMacOS`. Android stays stock Material, and its
  behaviour must not change when the desktop shell does.
- `flutter analyze` clean and `flutter test` passing are the bar before tagging.
- Commits written with AI assistance carry an `Assisted-by:` trailer.
- Device state (notification permission flag, digest time) lives beside the app's
  support files, not in the database: importing a backup replaces the workshop,
  not the machine's own preferences.
