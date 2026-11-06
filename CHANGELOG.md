# Changelog

All notable changes to PrintTender are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The release workflow takes each GitHub release's body from the matching section
below, so the entry has to exist before the tag is pushed.

## [1.3.0] - 2026-11-05

### Added

- **A battery-optimisation reminder on Android.** The daily digest is an alarm,
  and Android is free to defer or drop it while the app is in the background.
  The app now explains that once and offers the system exemption dialog, and
  Settings → Reliability shows whether PrintTender is exempt.
- **In-app update checks.** Settings → Updates shows the installed version, a
  switch for checking automatically (on by default, at most once a day) and a
  Check now button. When a newer release exists, Android downloads the APK and
  opens the system installer; macOS downloads the DMG and mounts it, since a
  sandboxed app cannot replace itself.

### Changed

- The app now makes one optional network request — `api.github.com` for the
  latest release — when an update check runs. Nothing else leaves the device, and
  the check can be switched off.

## [1.1.0] - 2026-11-01

### Added

- **An Android tablet layout.** From 600 dp on the screen's shorter side the phone
  screens give way to a printer list beside a content well: selecting a printer
  opens its schedules in the pane instead of pushing a new screen, and the year
  board is available there too.
- **A layout preference** under Settings → Layout, with Automatic (the 600 dp
  breakpoint), Always and Never. It is Android-only and stored per device.

## [1.0.1] - 2026-10-31

### Added

- **A Settings screen**, reachable from the app menu (⌘, on macOS) and from the
  overflow menu, with a pickable time for the daily digest. It stays at 09:00
  until changed, offers half-hour steps on macOS and the Material time picker on
  Android, and reschedules the next reminder as soon as it closes.

### Changed

- The digest time is per device, not part of the database, so importing a backup
  from another machine does not carry its reminder time along.
- Release APKs are now signed with a dedicated release key rather than the public
  Android debug key. **The 1.0.1 APK cannot install over a 1.0.0 install** — the
  signing identity changed — so uninstall 1.0.0 first. Releases after 1.0.1 install
  over it as updates.

## [1.0.0] - 2026-10-19

### Added

- First public release: printer inventory, a 58-task maintenance library,
  per-printer schedules graded OK / due soon / overdue, a dashboard of everything
  that needs attention, a maintenance log with parts and costs, per-printer
  history, a year board on desktop, and JSON backup export and import.
- Local notifications: one morning digest of what is overdue or due soon, silent
  when the workshop is healthy.
- A macOS build that restyles Material to follow AppKit conventions, alongside a
  stock-Material Android build.
