## Installing

**macOS** — open the DMG, drag **PrintTender** onto **Applications**, then
**right-click the app in Finder and choose Open** once and confirm. The build is
not notarized (there is no Apple Developer ID), so macOS quarantines the download;
after that first open it launches normally. Equivalently, from Terminal:

```bash
xattr -dr com.apple.quarantine /Applications/PrintTender.app
```

Requires macOS 12 or later. The app is universal: Apple Silicon and Intel.

**Android** — allow your browser or file manager to install unknown apps. The APK
is signed with PrintTender's own release key, so later releases install over it as
updates. Requires Android 7.0 or later.
