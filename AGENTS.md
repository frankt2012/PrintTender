# Working on PrintTender

## Releasing

**Every user-visible change ships as a release.** Never leave a feature or fix
sitting in `main` with no installer behind it: bump the version, commit, tag and
push the tag. The tag is what publishes — the release workflow builds the signed
APK on Linux and the DMG on macOS and attaches both to a GitHub Release.

1. Bump `version:` in `pubspec.yaml` (for example `1.0.2+3`). The `+N` build
   number must increase too, and the tag is the part before the `+`: `v1.0.2`.
2. Update anything the change made stale in `README.md` — test counts, behaviour
   descriptions, the notification/signing notes.
3. Commit, then `git tag v1.0.2` and `git push origin main v1.0.2`.
4. Watch the run (`gh run watch`) and confirm both assets were attached.

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
