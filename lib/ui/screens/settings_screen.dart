import 'package:flutter/material.dart';

import '../../services/battery_optimization.dart';
import '../../services/device_settings.dart';
import '../../services/updater.dart';
import '../mac_controls.dart';
import '../macos_theme.dart';
import '../update_prompt.dart';
import '../widgets.dart';

/// Device settings, as opposed to workshop data: the time of the daily digest
/// and, on Android, which layout to use. A screen of its own so later settings
/// have somewhere to live.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  /// The chosen time as minutes past midnight. Starts at the default so the
  /// pane paints at once, then takes the stored value when it arrives.
  int _minutes = DeviceSettings.defaultDigestMinutes;

  /// The layout preference; [TabletLayoutMode.auto] until the read returns.
  TabletLayoutMode _tabletMode = TabletLayoutMode.auto;

  /// Whether Android exempts the app from battery optimisation. Null until the
  /// platform answers, and null where the setting does not exist.
  bool? _batteryExempt;

  /// The installed version, for the Updates row.
  String? _version;

  /// Whether the app may ask GitHub for a newer release on its own.
  bool _autoUpdate = true;

  /// A manual check is in flight.
  bool _checking = false;

  /// The outcome of the last manual check.
  String? _updateStatus;

  /// Set once a value is changed here, so a slow read cannot overwrite the
  /// choice the user has just made.
  bool _touched = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _loadBattery();
    _loadUpdates();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning from the system exemption dialog: re-read the answer.
    if (state == AppLifecycleState.resumed) _loadBattery();
  }

  Future<void> _loadBattery() async {
    final exempt = await BatteryOptimization.isIgnoring();
    if (!mounted) return;
    setState(() => _batteryExempt = exempt);
  }

  Future<void> _requestBatteryExemption() async {
    await BatteryOptimization.requestExemption();
    await _loadBattery();
  }

  Future<void> _loadUpdates() async {
    final auto = await DeviceSettings.autoUpdateCheck();
    final version = await Updater.currentVersionLabel();
    if (!mounted) return;
    setState(() {
      _autoUpdate = auto;
      _version = version;
    });
  }

  Future<void> _setAutoUpdate(bool enabled) async {
    setState(() => _autoUpdate = enabled);
    await DeviceSettings.writeAutoUpdateCheck(enabled);
  }

  Future<void> _checkForUpdates() async {
    setState(() {
      _checking = true;
      _updateStatus = null;
    });
    try {
      final update = await Updater.checkForUpdate();
      if (!mounted) return;
      if (update == null) {
        setState(() {
          _checking = false;
          _updateStatus = 'You are on the latest version.';
        });
        return;
      }
      setState(() => _checking = false);
      await showUpdatePrompt(context, update);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _updateStatus = 'Could not check right now. Try again later.';
      });
    }
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
            if (_batteryExempt != null) ...<Widget>[
              const SizedBox(height: 24),
              const SectionHeader(title: 'Reliability'),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.battery_saver_outlined),
                title: const Text('Battery optimisation'),
                subtitle: Text(
                  _batteryExempt!
                      ? 'PrintTender is exempt, so reminders can fire while it '
                            'is in the background.'
                      : 'Android may delay or drop the daily reminder while '
                            'PrintTender is in the background.',
                ),
                trailing: _batteryExempt!
                    ? Icon(
                        Icons.check_circle_outline,
                        color: Theme.of(context).colorScheme.primary,
                      )
                    : TextButton(
                        onPressed: _requestBatteryExemption,
                        child: const Text('Fix'),
                      ),
              ),
            ],
          ],
          const SizedBox(height: 24),
          const SectionHeader(title: 'Updates'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.system_update_outlined),
            title: Text(
              _version == null ? 'PrintTender' : 'PrintTender $_version',
            ),
            subtitle: const Text(
              'Asks GitHub for the newest release. Nothing else uses the '
              'network.',
            ),
            trailing: _checking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : TextButton(
                    onPressed: _checkForUpdates,
                    child: const Text('Check now'),
                  ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.schedule_outlined),
            title: const Text('Check automatically'),
            subtitle: const Text('At most once a day, when the app opens.'),
            value: _autoUpdate,
            onChanged: _setAutoUpdate,
          ),
          if (_updateStatus != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              _updateStatus!,
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
