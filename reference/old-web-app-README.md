# 3D Printer Maintenance Log

A free, single-page web app for tracking maintenance on your 3D printers. No account and no build step. Use it in a browser tab, or install it as an app on your computer or phone.

**Live app:** https://frankt2012.github.io/3d-printer-maintenance-log/

## What it does

- **Multiple printers.** Each printer has its own print-hours counter, installed nozzle (type and size) and installed build plate.
- **Maintenance categories.** New printers start with eight: carbon rods, linear rods, lead screws, belts, cutter, extruder, fans and nozzle. Add, edit or remove any category.
- **Quick picks.** Around 50 ready-made categories (motion, hotend, bed, filament handling, electronics, enclosure, multi-material systems such as CFS, AMS Lite, AMS and MMU, and resin printers) with a suggested starting interval you can change.
- **Flexible intervals.** Repeat by print hours, calendar days or months, and set the date you last serviced each item.
- **Two views.** A task list with progress gauges, and a Year board with one row per category and a frame on the month it is next due. Frames turn orange when due soon and red when overdue.
- **Service history.** Log each service with a date, print hours and a note.
- **Light and dark themes** that follow your system setting.

## Install it as an app

Installing gives the log its own icon and window, with no browser address bar. It also works offline after your first visit.

Install from the live address above. A file you downloaded and opened from your computer can't be installed. The steps below are for each major browser. Menu names change between versions, so if yours looks different, look for an option called Install, Install page as app, or Add to Home Screen.

### Chrome on Windows, macOS, Linux and ChromeOS

1. Open the live app in Chrome.
2. Click the **Install** icon at the right end of the address bar. If you don't see it, open the **More** menu (three dots), then **Cast, save, and share**, then **Install page as app...**.
3. Follow the prompts.

To remove it, open the app, select **More** (three dots) at the top right, then **Uninstall**. You can also manage installed apps at `chrome://apps`.

### Chrome on Android

1. Open the live app in Chrome.
2. Tap **More** (three dots) next to the address bar, then **Install and create shortcut**, then **Install**.

To remove it, go to Settings, then Apps, then See all apps, tap the app and choose Uninstall.

### Microsoft Edge on Windows and macOS

1. Open the live app in Edge.
2. If Edge offers to install it, accept. Otherwise open **Settings and more** (three dots), then **More tools**, then **Apps**, then **Install this site as an app**.

Installed apps are listed at `edge://apps`, where you can select Details and then Uninstall.

### Safari on Mac (macOS Sonoma 14 or later)

1. Open the live app in Safari.
2. Choose **File, then Add to Dock**, or click the **Share** button in the toolbar and choose **Add to Dock**.
3. Enter a name and click **Add**.

The app appears in your Dock and in Spotlight.

### Safari on iPhone and iPad

1. Open the live app in Safari.
2. Tap the **Share** button, then **Add to Home Screen**.
3. If you see an **Open as Web App** option, leave it on. Tap **Add**.

To remove it, press and hold the icon on your Home Screen and delete it. From iOS 16.4, other browsers such as Chrome can also add it with **Share, then Add to Home Screen, then Add**.

### Firefox

- **Windows (Firefox 143 or later, or 150 or later if installed from the Microsoft Store):** open the live app and select the web apps icon in the address bar. Firefox adds it to your taskbar and Start menu.
- **macOS and Linux:** Firefox has no built-in install. You can use the app in a normal tab, or open the live address in Chrome, Edge or Safari and install it there.
- **Android:** open the browser menu and look for **Install** or **Add to Home screen**.

### Samsung Internet, Brave, Opera, Vivaldi and others

Most Chromium-based browsers offer an install icon in the address bar or a menu item named **Install** or **Install page as app**. Samsung Internet has an option to add the page to your Home screen from its menu. If you can't find it, the live app still works as a normal web page.

### Good to know

- **Updates.** The installed app gets new versions automatically when you are online.
- **Your data stays on one device.** Each browser and device keeps its own list. On some devices, especially iPhone and iPad, the installed app has its own storage, so printers you added in a browser tab may not appear in it. Add your printers after you install.

Sources for these steps: [Chrome Help](https://support.google.com/chrome/answer/9658361), [Microsoft Edge](https://support.microsoft.com/en-us/edge/install-manage-or-uninstall-apps-in-microsoft-edge), [Apple: Safari on Mac](https://support.apple.com/en-us/104996), [Mozilla: web apps in Firefox for Windows](https://support.mozilla.org/en-US/kb/web-apps-firefox-windows), [MDN: Installing PWAs](https://developer.mozilla.org/en-US/docs/Web/Progressive_web_apps/Guides/Installing).

## Using it without installing

Open the live address, or download `index.html` and open it in any browser. To host your own copy, turn on GitHub Pages for your fork (Settings, Pages, deploy from the `main` branch).

## Your data

Everything is saved in your browser's local storage on the device you use. Nothing is sent anywhere. That means:

- Each browser and device keeps its own separate list.
- Clearing your browsing data erases it.
- The app has no export button yet, so there is no built-in backup.

The suggested intervals are general starting points, not manufacturer schedules. Adjust them to match your printers.

## Files

| File | What it is |
| --- | --- |
| `index.html` | The whole app. |
| `manifest.webmanifest` | Name, colors and icons used when the app is installed. |
| `sw.js` | Small service worker that lets the app work offline. |
| `icons/` | App icons. |

## Fonts

The page loads Barlow Condensed, IBM Plex Sans and IBM Plex Mono from Google Fonts. Without an internet connection it falls back to your system fonts and still works.

## License

MIT. See [LICENSE](LICENSE).
