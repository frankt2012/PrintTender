import 'package:flutter/material.dart';

import '../../services/device_settings.dart';
import '../mac_controls.dart';
import '../macos_theme.dart';
import '../widgets.dart';

/// Device settings, as opposed to workshop data: the time of the daily digest
/// and, on Android, which layout to use. A screen of its own so later settings
/// have somewhere to live.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// The chosen time as minutes past midnight. Starts at the default so the
  /// pane paints at once, then takes the stored value when it arrives.
  int _minutes = DeviceSettings.defaultDigestMinutes;

  /// The layout preference; [TabletLayoutMode.auto] until the read returns.
  TabletLayoutMode _tabletMode = TabletLayoutMode.auto;

  /// Set once a value is changed here, so a slow read cannot overwrite the
  /// choice the user has just made.
  bool _touched = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final minutes = await DeviceSettings.readDigestMinutes();
    final tabletMode = await DeviceSettings.readTabletLayout();
    if (!mounted || _touched) return;
    setState(() {
      _minutes = minutes;
      _tabletMode = tabletMode;
    });
  }

  Future<void> _setMinutes(int minutes) async {
    _touched = true;
    // The picker should react at once; persistence is a small file write.
    setState(() => _minutes = minutes);
    await DeviceSettings.writeDigestMinutes(minutes);
  }

  Future<void> _setTabletMode(TabletLayoutMode mode) async {
    _touched = true;
    setState(() => _tabletMode = mode);
    await DeviceSettings.writeTabletLayout(mode);
  }

  /// Android uses the Material picker. macOS does not: a clock dial is not an
  /// AppKit control, so it gets the pop-up in [_macTimeControl] instead.
  Future<void> _pickTime() async {
    final current = _minutes;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: current ~/ Duration.minutesPerHour,
        minute: current % Duration.minutesPerHour,
      ),
      helpText: 'Morning digest',
    );
    if (picked == null || !mounted) return;
    await _setMinutes(picked.hour * Duration.minutesPerHour + picked.minute);
  }

  String _label(BuildContext context, int minutes) {
    return MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay(
        hour: minutes ~/ Duration.minutesPerHour,
        minute: minutes % Duration.minutesPerHour,
      ),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
  }

  /// A pop-up button of delivery times, the way a Mac settings pane offers
  /// one. Half-hour steps keep the list short; the current value is always
  /// included so a time with an odd minute still selects.
  Widget _macTimeControl() {
    final current = _minutes;
    final options = <int>{
      for (var minutes = 0; minutes < Duration.minutesPerDay; minutes += 30)
        minutes,
      current,
    }.toList()..sort();

    return DropdownButton<int>(
      value: current,
      isDense: true,
      menuMaxHeight: 320,
      underline: const SizedBox.shrink(),
      borderRadius: BorderRadius.circular(6),
      items: <DropdownMenuItem<int>>[
        for (final minutes in options)
          DropdownMenuItem<int>(
            value: minutes,
            child: Text(_label(context, minutes)),
          ),
      ],
      onChanged: (value) {
        if (value != null) _setMinutes(value);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        // A sheet closes from its bottom bar, so the title bar does not also
        // offer a back chevron.
        automaticallyImplyLeading: !isMacOS,
      ),
      bottomNavigationBar: isMacOS
          ? MacSheetButtonBar(
              onDone: () => Navigator.of(context).pop(),
              doneLabel: 'Done',
            )
          : null,
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 8, 16, isMacOS ? 16 : 24),
        children: <Widget>[
          const SectionHeader(title: 'Notifications'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Morning digest'),
            subtitle: const Text(
              'One reminder a day, shown only when something is overdue '
              'or coming due.',
            ),
            trailing: isMacOS
                ? _macTimeControl()
                : TextButton(
                    onPressed: _pickTime,
                    child: Text(_label(context, _minutes)),
                  ),
            onTap: isMacOS ? null : _pickTime,
          ),
          const SizedBox(height: 8),
          Text(
            'Scheduled by the system on this device. Moving the time '
            'reschedules the next digest.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (isAndroid) ...<Widget>[
            const SizedBox(height: 24),
            const SectionHeader(title: 'Layout'),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.tablet_android_outlined),
              title: const Text('Tablet layout'),
              subtitle: const Text(
                'A printer list beside the content, instead of a screen per '
                'printer.',
              ),
              trailing: DropdownButton<TabletLayoutMode>(
                value: _tabletMode,
                isDense: true,
                underline: const SizedBox.shrink(),
                borderRadius: BorderRadius.circular(6),
                items: const <DropdownMenuItem<TabletLayoutMode>>[
                  DropdownMenuItem<TabletLayoutMode>(
                    value: TabletLayoutMode.auto,
                    child: Text('Automatic'),
                  ),
                  DropdownMenuItem<TabletLayoutMode>(
                    value: TabletLayoutMode.always,
                    child: Text('Always'),
                  ),
                  DropdownMenuItem<TabletLayoutMode>(
                    value: TabletLayoutMode.never,
                    child: Text('Never'),
                  ),
                ],
                onChanged: (mode) {
                  if (mode != null) _setTabletMode(mode);
                },
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Automatic switches when the shorter side of the screen is '
              '600 dp or more.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
