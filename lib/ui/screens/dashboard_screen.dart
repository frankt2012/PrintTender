import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../services/backup.dart';
import '../../services/backup_io.dart';
import '../../services/battery_optimization.dart';
import '../../services/device_settings.dart';
import '../../services/due_status.dart';
import '../../services/notifications.dart';
import '../../services/updater.dart';
import '../mac_controls.dart';
import '../mac_sidebar.dart';
import '../macos_theme.dart';
import '../routes.dart';
import '../update_prompt.dart';
import '../widgets.dart';
import 'add_log_entry_screen.dart';
import 'edit_printer_screen.dart';
import 'printer_detail_screen.dart';
import 'settings_screen.dart';
import 'task_definitions_screen.dart';

class PrinterStatus {
  const PrinterStatus({
    required this.overdue,
    required this.dueSoon,
    required this.total,
  });

  final int overdue;
  final int dueSoon;
  final int total;
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _printers = PrinterRepository();
  final _tasks = TaskRepository();
  final _logs = LogRepository();

  List<Printer> _printersList = const <Printer>[];
  Map<int, PrinterStatus> _statuses = const <int, PrinterStatus>{};
  final Map<int, List<PrinterTask>> _schedules = <int, List<PrinterTask>>{};
  List<AttentionItem> _attention = const <AttentionItem>[];
  List<LogEntry> _recent = const <LogEntry>[];
  Map<int, String> _printerNames = const <int, String>{};
  int _overdueCount = 0;
  double _totalCost = 0;
  bool _loading = true;
  Object? _error;
  bool _showBoard = false;

  /// The layout preference read from this device's settings.
  TabletLayoutMode _tabletMode = TabletLayoutMode.auto;

  /// Whether this launch has already considered the one-time battery nudge.
  bool _batteryPromptConsidered = false;

  /// Whether this launch has already looked for an update.
  bool _updateCheckStarted = false;

  /// Which printer the macOS sidebar has selected; `null` means the overview.
  int? _selectedPrinterId;

  @override
  void initState() {
    super.initState();
    _loadDeviceSettings();
    _load();
  }

  /// Reads this device's preferences. Only the layout matters here; the digest
  /// time is read by the reminder service when it schedules.
  Future<void> _loadDeviceSettings() async {
    final mode = await DeviceSettings.readTabletLayout();
    if (!mounted) return;
    setState(() => _tabletMode = mode);
  }

  /// One-time nudge about Android's battery optimisation.
  ///
  /// The digest is an alarm, and without the exemption Android is free to defer
  /// or kill the app before it fires — silently. Nothing can change that
  /// without the user, so explain it once and offer the system dialog; the
  /// Settings row stays as the way back to it.
  Future<void> _maybeAskBattery(bool hasSchedule) async {
    if (_batteryPromptConsidered || !hasSchedule) return;
    _batteryPromptConsidered = true;
    if (await DeviceSettings.batteryPromptAsked()) return;
    final exempt = await BatteryOptimization.isIgnoring();
    if (exempt != false) return;

    await DeviceSettings.markBatteryPromptAsked();
    if (!mounted) return;

    final open = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Keep reminders on time'),
        content: const Text(
          'Android can delay or drop the daily reminder while PrintTender is '
          'in the background. Exempting the app from battery optimisation is '
          'what keeps the digest reliable.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Open settings'),
          ),
        ],
      ),
    );
    if (open == true) await BatteryOptimization.requestExemption();
  }

  /// At most one automatic update check per session, and at most one per day
  /// across sessions. A failure is silent: this app is meant to work offline,
  /// and a check that cannot reach GitHub is not worth interrupting anyone for.
  Future<void> _maybeCheckForUpdates() async {
    if (_updateCheckStarted) return;
    _updateCheckStarted = true;
    if (!await DeviceSettings.autoUpdateCheck()) return;

    final last = await DeviceSettings.lastUpdateCheck();
    if (last != null &&
        DateTime.now().difference(last) < const Duration(days: 1)) {
      return;
    }

    try {
      final update = await Updater.checkForUpdate();
      await DeviceSettings.writeLastUpdateCheck(DateTime.now());
      if (update != null && mounted) {
        await showUpdatePrompt(context, update);
      }
    } catch (error) {
      debugPrint('Updates: automatic check skipped ($error)');
    }
  }

  Future<void> _load() async {
    try {
      final printers = await _printers.all();
      final statuses = <int, PrinterStatus>{};
      final attention = <AttentionItem>[];
      final names = <int, String>{};
      var overdueCount = 0;
      var hasSchedule = false;

      for (final printer in printers) {
        names[printer.id!] = printer.name;
        final schedules = await _tasks.schedulesFor(printer.id!);
        if (schedules.isNotEmpty) hasSchedule = true;
        var overdue = 0;
        var dueSoon = 0;
        for (final schedule in schedules) {
          final info = DueStatus.evaluate(printer: printer, schedule: schedule);
          if (info.level == DueLevel.overdue) overdue++;
          if (info.level == DueLevel.dueSoon) dueSoon++;
          if (info.level == DueLevel.overdue ||
              info.level == DueLevel.dueSoon) {
            attention.add(
              AttentionItem(printer: printer, schedule: schedule, info: info),
            );
          }
        }
        overdueCount += overdue;
        _schedules[printer.id!] = schedules;
        statuses[printer.id!] = PrinterStatus(
          overdue: overdue,
          dueSoon: dueSoon,
          total: schedules.length,
        );
      }

      attention.sort((a, b) {
        final pa = a.info.progress ?? 2.0;
        final pb = b.info.progress ?? 2.0;
        return pb.compareTo(pa);
      });

      final recent = await _logs.recent(limit: 8);
      final totalCost = await _logs.totalCost();

      if (!mounted) return;
      setState(() {
        _printersList = printers;
        _statuses = statuses;
        _attention = attention;
        _recent = recent;
        _printerNames = names;
        _overdueCount = overdueCount;
        _totalCost = totalCost;
        _error = null;
        _loading = false;
        // The sidebar may be pointing at a printer that was just deleted.
        if (_selectedPrinterId != null &&
            !printers.any((p) => p.id == _selectedPrinterId)) {
          _selectedPrinterId = null;
        }
      });

      // The dashboard recomputes this list on launch, after every edit and on
      // pull-to-refresh, so it is also where the morning digest is kept
      // current. It is deliberately awaited after the frame is painted, and
      // the service swallows its own failures: a reminder that will not
      // schedule must never turn a working dashboard into an error screen.
      await ReminderService.instance.sync(
        attention: attention,
        hasSchedule: hasSchedule,
      );

      // Ask after the notification prompt has been answered, so two dialogs
      // never fight over the screen.
      await _maybeAskBattery(hasSchedule);
      await _maybeCheckForUpdates();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _addPrinter() async {
    final saved = await Navigator.of(context).push<bool>(
      pushPage(
        (_) => const EditPrinterScreen(),
        maxWidth: 720,
        maxHeight: 620,
        name: 'add-printer',
      ),
    );
    if (saved == true) await _load();
  }

  Future<void> _openLibrary() async {
    await Navigator.of(context).push(
      pushPage((_) => const TaskDefinitionsScreen(), name: 'library'),
    );
    await _load();
  }

  /// Device settings, which today means the time of the daily digest.
  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      pushPage(
        (_) => const SettingsScreen(),
        maxWidth: 520,
        maxHeight: 460,
        name: 'settings',
      ),
    );
    // The dashboard load reschedules the digest, so a changed time takes
    // effect as soon as the sheet closes; the layout is reread for the same
    // reason.
    await _loadDeviceSettings();
    await _load();
  }

  /// Whether this screen uses the Android tablet shell: a printer list beside
  /// the content instead of a pushed screen per printer.
  bool get _tabletShell =>
      isAndroid &&
      _tabletMode.resolve(MediaQuery.sizeOf(context).shortestSide);

  /// Writes the whole database to a JSON file and hands it to the share sheet,
  /// which is the one "save it wherever you like" affordance available on both
  /// Android and the desktop.
  Future<void> _exportBackup() async {
    final backup = BackupService();
    try {
      final json = backup.encode(await backup.snapshot());
      final fileName = backup.suggestedFileName();
      final saved = await shareBackupFile(json: json, fileName: fileName);
      if (!mounted || saved == null) return;
      showSnack(context, 'Backup saved to ${p.basename(saved)}.');
    } catch (error) {
      if (!mounted) return;
      showSnack(context, 'Could not export: $error');
    }
  }

  Future<void> _importBackup() async {
    final backup = BackupService();
    final String? source;
    try {
      source = await pickBackupFile();
    } catch (error) {
      if (!mounted) return;
      showSnack(context, 'Could not open that file: $error');
      return;
    }
    if (source == null) return;

    final Map<String, Object?> snapshot;
    try {
      snapshot = backup.decode(source);
    } on FormatException catch (error) {
      if (!mounted) return;
      showSnack(context, error.message);
      return;
    }

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Replace all data?'),
        content: const Text(
          'Importing a backup deletes every printer, task and log entry on this '
          'device and replaces them with the contents of the file. This cannot '
          'be undone.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Replace'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await backup.restore(snapshot);
    } catch (error) {
      if (!mounted) return;
      showSnack(context, 'Could not import: $error');
      return;
    }
    await _load();
    if (!mounted) return;
    showSnack(context, 'Backup imported.');
  }

  Future<void> _openPrinter(int printerId) async {
    // On macOS and on a tablet the detail lives in the pane beside the list
    // rather than on a pushed route, so "opening" a printer is just a change
    // of selection.
    if (isMacOS || _tabletShell) {
      setState(() => _selectedPrinterId = printerId);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PrinterDetailScreen(printerId: printerId),
      ),
    );
    await _load();
  }

  /// Bumps a printer's odometer without leaving the dashboard, so hour-based
  /// intervals can be kept current as a two-tap habit.
  Future<void> _editHours(Printer printer) async {
    final hours = await showPrintHoursDialog(
      context,
      currentHours: printer.totalPrintHours,
    );
    if (hours == null || hours < 0) return;
    await _printers.setPrintHours(printer.id!, hours);
    await _load();
  }

  Future<void> _logFor(Printer printer, [PrinterTask? schedule]) async {
    final saved = await Navigator.of(context).push<bool>(
      pushPage(
        (_) => AddLogEntryScreen(
          initialPrinter: printer,
          initialSchedule: schedule,
        ),
        maxWidth: 760,
        maxHeight: 660,
      ),
    );
    if (saved == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final scaffold = Scaffold(
      appBar: AppBar(
        title: const Text('PrintTender'),
        actions: <Widget>[
          if (isDesktop && _selectedPrinterId == null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: MacSegmentedControl<bool>(
                segments: const <MacSegment<bool>>[
                  MacSegment<bool>(
                    value: false,
                    label: 'Tasks',
                    icon: Icons.list_alt_outlined,
                  ),
                  MacSegment<bool>(
                    value: true,
                    label: 'Year Board',
                    icon: Icons.calendar_view_month_outlined,
                  ),
                ],
                value: _showBoard,
                onChanged: (selection) =>
                    setState(() => _showBoard = selection),
              ),
            ),
          IconButton(
            tooltip: 'Maintenance library',
            icon: const Icon(Icons.library_books_outlined),
            onPressed: _openLibrary,
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (value) {
              if (value == 'settings') _openSettings();
              if (value == 'export') _exportBackup();
              if (value == 'import') _importBackup();
            },
            itemBuilder: (context) => const <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'export',
                child: ListTile(
                  leading: Icon(Icons.ios_share_outlined),
                  title: Text('Export backup'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem<String>(
                value: 'import',
                child: ListTile(
                  leading: Icon(Icons.restore_outlined),
                  title: Text('Import backup'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem<String>(
                value: 'settings',
                child: ListTile(
                  leading: Icon(Icons.settings_outlined),
                  title: Text('Settings'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          if (isMacOS) ...<Widget>[
            const SizedBox(width: 4),
            OutlinedButton.icon(
              onPressed: _addPrinter,
              icon: const Icon(Icons.add, size: 14),
              label: const Text('Add Printer'),
            ),
            const SizedBox(width: 14),
          ],
        ],
      ),
      // macOS puts primary actions in the toolbar, never in a floating button.
      // On a tablet the button belongs to the overview, not to a printer's
      // pane, so it steps aside once one is selected.
      floatingActionButton:
          isMacOS || (_tabletShell && _selectedPrinterId != null)
          ? null
          : FloatingActionButton.extended(
              onPressed: _addPrinter,
              icon: const Icon(Icons.add),
              label: const Text('Add printer'),
            ),
      body: isMacOS
          ? _buildMacBody()
          : (_tabletShell ? _buildTabletBody() : _buildBody()),
    );

    if (!isMacOS) return scaffold;
    return PlatformMenuBar(menus: _macMenus(), child: scaffold);
  }

  /// On macOS the dashboard is a sidebar plus a content well, the way a
  /// Mac app is shaped: the printer list stays visible while you work.
  Widget _buildMacBody() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        MacSidebar(
          children: <Widget>[
            MacSidebarSection(
              title: 'Printers',
              children: <Widget>[
                MacSidebarTile(
                  label: 'All Printers',
                  icon: Icons.print_outlined,
                  selected: _selectedPrinterId == null,
                  onTap: () => setState(() => _selectedPrinterId = null),
                  trailing: _overdueCount > 0
                      ? MacSidebarBadge(count: _overdueCount)
                      : null,
                ),
                for (final printer in _printersList)
                  MacSidebarTile(
                    label: printer.name,
                    icon: Icons.print_outlined,
                    selected: _selectedPrinterId == printer.id,
                    onTap: () =>
                        setState(() => _selectedPrinterId = printer.id),
                    trailing: _sidebarBadgeFor(printer),
                  ),
              ],
            ),
            MacSidebarSection(
              title: 'Library',
              children: <Widget>[
                MacSidebarTile(
                  label: 'Maintenance Tasks',
                  icon: Icons.library_books_outlined,
                  onTap: _openLibrary,
                ),
              ],
            ),
          ],
        ),
        Expanded(child: _buildMacContent()),
      ],
    );
  }

  Widget _buildMacContent() {
    final id = _selectedPrinterId;
    if (id == null) return _buildBody();
    return PrinterDetailScreen(
      key: ValueKey<int>(id),
      printerId: id,
      embedded: true,
      onDeleted: () {
        setState(() => _selectedPrinterId = null);
        _load();
      },
      onChanged: _load,
    );
  }

  /// The Android tablet shell: a printer list beside a content well, which is
  /// the shape of the desktop app built from Material pieces instead.
  Widget _buildTabletBody() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _buildTabletSidebar(),
        const VerticalDivider(width: 1),
        Expanded(child: _buildTabletContent()),
      ],
    );
  }

  Widget _buildTabletSidebar() {
    final theme = Theme.of(context);
    final width = (MediaQuery.sizeOf(context).width * 0.28)
        .clamp(260.0, 340.0)
        .toDouble();

    return SizedBox(
      width: width,
      child: Material(
        color: theme.colorScheme.surfaceContainerLow,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: SectionHeader(title: 'Printers'),
            ),
            ListTile(
              leading: const Icon(Icons.print_outlined),
              title: const Text('All printers'),
              selected: _selectedPrinterId == null,
              trailing: _overdueCount > 0
                  ? _SidebarCount(
                      count: _overdueCount,
                      color: theme.colorScheme.error,
                      foreground: theme.colorScheme.onError,
                    )
                  : null,
              onTap: () => setState(() => _selectedPrinterId = null),
            ),
            for (final printer in _printersList)
              ListTile(
                leading: const Icon(Icons.print_outlined),
                title: Text(
                  printer.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                selected: _selectedPrinterId == printer.id,
                trailing: _tabletBadgeFor(printer),
                onTap: () => setState(() => _selectedPrinterId = printer.id),
              ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: SectionHeader(title: 'Library'),
            ),
            ListTile(
              leading: const Icon(Icons.library_books_outlined),
              title: const Text('Maintenance tasks'),
              onTap: _openLibrary,
            ),
          ],
        ),
      ),
    );
  }

  /// The count beside a printer in the tablet sidebar, in the same two states
  /// the macOS sidebar distinguishes.
  Widget? _tabletBadgeFor(Printer printer) {
    final status = _statuses[printer.id!];
    if (status == null) return null;
    final scheme = Theme.of(context).colorScheme;
    if (status.overdue > 0) {
      return _SidebarCount(
        count: status.overdue,
        color: scheme.error,
        foreground: scheme.onError,
      );
    }
    if (status.dueSoon > 0) {
      return _SidebarCount(
        count: status.dueSoon,
        color: scheme.tertiaryContainer,
        foreground: scheme.onTertiaryContainer,
      );
    }
    return null;
  }

  Widget _buildTabletContent() {
    final id = _selectedPrinterId;
    if (id == null) {
      // The sidebar already lists the printers, so the overview must not
      // repeat them; it gets the Tasks / Year Board switch instead.
      return _buildBody(listPrinters: false, showViewToggle: true);
    }
    return PrinterDetailScreen(
      key: ValueKey<int>(id),
      printerId: id,
      embedded: true,
      onDeleted: () {
        setState(() => _selectedPrinterId = null);
        _load();
      },
      onChanged: _load,
    );
  }

  /// The little overdue / due-soon count beside a printer's sidebar row.
  Widget? _sidebarBadgeFor(Printer printer) {
    final status = _statuses[printer.id!];
    if (status == null) return null;
    if (status.overdue > 0) return MacSidebarBadge(count: status.overdue);
    if (status.dueSoon > 0) {
      return MacSidebarBadge(
        count: status.dueSoon,
        color: MacColors.orangeFor(Theme.of(context).brightness),
      );
    }
    return null;
  }

  /// The real macOS menu bar, so the File, View and Printer commands land where
  /// Mac users reach for them instead of behind an overflow button.
  List<PlatformMenuItem> _macMenus() {
    return <PlatformMenuItem>[
      PlatformMenu(
        label: 'PrintTender',
        menus: <PlatformMenuItem>[
          const PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.about,
          ),
          PlatformMenuItem(
            label: 'Settings…',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.comma,
              meta: true,
            ),
            onSelected: _openSettings,
          ),
          const PlatformMenuItemGroup(
            members: <PlatformMenuItem>[
              PlatformProvidedMenuItem(
                type: PlatformProvidedMenuItemType.hide,
              ),
              PlatformProvidedMenuItem(
                type: PlatformProvidedMenuItemType.hideOtherApplications,
              ),
              PlatformProvidedMenuItem(
                type: PlatformProvidedMenuItemType.showAllApplications,
              ),
            ],
          ),
          const PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.quit,
          ),
        ],
      ),
      PlatformMenu(
        label: 'File',
        menus: <PlatformMenuItem>[
          PlatformMenuItem(
            label: 'Export Backup…',
            shortcut:
                const SingleActivator(LogicalKeyboardKey.keyE, meta: true),
            onSelected: _exportBackup,
          ),
          PlatformMenuItem(
            label: 'Import Backup…',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyI,
              meta: true,
            ),
            onSelected: _importBackup,
          ),
        ],
      ),
      PlatformMenu(
        label: 'Printer',
        menus: <PlatformMenuItem>[
          PlatformMenuItem(
            label: 'Add Printer…',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyN,
              meta: true,
            ),
            onSelected: _addPrinter,
          ),
          PlatformMenuItem(
            label: 'Maintenance Library…',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyL,
              meta: true,
            ),
            onSelected: _openLibrary,
          ),
        ],
      ),
      PlatformMenu(
        label: 'View',
        menus: <PlatformMenuItem>[
          PlatformMenuItem(
            label: 'Tasks',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.digit1,
              meta: true,
            ),
            onSelected: () => setState(() => _showBoard = false),
          ),
          PlatformMenuItem(
            label: 'Year Board',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.digit2,
              meta: true,
            ),
            onSelected: () => setState(() => _showBoard = true),
          ),
        ],
      ),
      PlatformMenu(
        label: 'Window',
        menus: const <PlatformMenuItem>[
          PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.minimizeWindow,
          ),
          PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.zoomWindow,
          ),
          PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.toggleFullScreen,
          ),
        ],
      ),
    ];
  }

  Widget _buildBody({bool? listPrinters, bool showViewToggle = false}) {
    final withPrinters = listPrinters ?? !isMacOS;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorView(error: _error!, onRetry: _load);

    if (_printersList.isEmpty) {
      return EmptyState(
        icon: Icons.print_outlined,
        title: 'No printers yet',
        message: 'Add your first 3D printer, then assign the maintenance tasks you care about.',
        action: FilledButton.icon(
          onPressed: _addPrinter,
          icon: const Icon(Icons.add),
          label: const Text('Add printer'),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: <Widget>[
          if (showViewToggle) ...<Widget>[
            Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<bool>(
                segments: const <ButtonSegment<bool>>[
                  ButtonSegment<bool>(
                    value: false,
                    label: Text('Tasks'),
                    icon: Icon(Icons.list_alt_outlined),
                  ),
                  ButtonSegment<bool>(
                    value: true,
                    label: Text('Year Board'),
                    icon: Icon(Icons.calendar_view_month_outlined),
                  ),
                ],
                selected: <bool>{_showBoard},
                onSelectionChanged: (selection) =>
                    setState(() => _showBoard = selection.first),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: <Widget>[
              Expanded(
                child: StatCard(
                  icon: Icons.print_outlined,
                  value: '${_printersList.length}',
                  label: 'Printers',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatCard(
                  icon: _overdueCount > 0
                      ? Icons.error_outline
                      : Icons.check_circle_outline,
                  value: '$_overdueCount',
                  label: _overdueCount == 1 ? 'Task overdue' : 'Tasks overdue',
                  color: _overdueCount > 0
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatCard(
                  icon: Icons.payments_outlined,
                  value: formatMoney(_totalCost),
                  label: 'Parts spend',
                ),
              ),
            ],
          ),
          if (_attention.isNotEmpty) ...<Widget>[
            const SizedBox(height: 24),
            SectionHeader(
              title: 'Needs attention',
              trailing: '${_attention.length}',
            ),
            ..._attention.map(
              (item) => _AttentionTile(
                item: item,
                onLog: () => _logFor(item.printer, item.schedule),
                onOpenPrinter: () => _openPrinter(item.printer.id!),
              ),
            ),
          ],
          if (_showBoard) ...<Widget>[
            const SizedBox(height: 24),
            SectionHeader(
              title: 'Year board',
              trailing: '${_printersList.length}',
            ),
            _BoardView(
              printers: _printersList,
              schedules: _schedules,
              onLog: (p, t) => _logFor(p, t),
              onOpenPrinter: (p) => _openPrinter(p.id!),
            ),
          ] else if (withPrinters) ...<Widget>[
            // macOS and the tablet shell list printers in the sidebar, so the
            // overview does not repeat them here.
            const SizedBox(height: 24),
            SectionHeader(
              title: 'My printers',
              trailing: '${_printersList.length}',
            ),
            ..._printersList.map(
              (printer) => _PrinterTile(
                printer: printer,
                status: _statuses[printer.id!],
                onTap: () => _openPrinter(printer.id!),
                onEditHours: () => _editHours(printer),
              ),
            ),
          ],
          if (_recent.isNotEmpty) ...<Widget>[
            const SizedBox(height: 24),
            const SectionHeader(title: 'Recent activity'),
            ..._recent.map(
              (entry) => _RecentTile(
                entry: entry,
                printerName: _printerNames[entry.printerId],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AttentionTile extends StatelessWidget {
  const _AttentionTile({
    required this.item,
    required this.onLog,
    required this.onOpenPrinter,
  });

  final AttentionItem item;
  final VoidCallback onLog;
  final VoidCallback onOpenPrinter;

  @override
  Widget build(BuildContext context) {
    final color = dueColor(context, item.info.level);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        leading: Icon(dueIcon(item.info.level), color: color),
        title: Text(item.schedule.taskName),
        subtitle: Text(
          '${item.printer.name}  ·  ${item.info.label}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: onLog,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextButton(onPressed: onLog, child: const Text('Log')),
            IconButton(
              tooltip: 'Open printer',
              icon: const Icon(Icons.chevron_right),
              onPressed: onOpenPrinter,
            ),
          ],
        ),
      ),
    );
  }
}

class _PrinterTile extends StatelessWidget {
  const _PrinterTile({
    required this.printer,
    required this.status,
    required this.onTap,
    required this.onEditHours,
  });

  final Printer printer;
  final PrinterStatus? status;
  final VoidCallback onTap;
  final VoidCallback onEditHours;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final overdue = status?.overdue ?? 0;
    final dueSoon = status?.dueSoon ?? 0;
    final total = status?.total ?? 0;

    final Widget trailing;
    if (overdue > 0) {
      trailing = DueBadge(
        info: DueInfo(level: DueLevel.overdue, label: '$overdue overdue'),
      );
    } else if (dueSoon > 0) {
      trailing = DueBadge(
        info: DueInfo(level: DueLevel.dueSoon, label: '$dueSoon due soon'),
      );
    } else if (total > 0) {
      trailing = DueBadge(
        info: const DueInfo(level: DueLevel.ok, label: 'All good'),
      );
    } else {
      trailing = DueBadge(
        info: const DueInfo(level: DueLevel.unscheduled, label: 'No schedule'),
      );
    }

    final subtitle = <String>[
      if (printer.subtitle.isNotEmpty) printer.subtitle,
      '${formatHours(printer.totalPrintHours)} h',
      '$total tracked',
    ].join('  ·  ');

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Icon(
            Icons.print_outlined,
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
        title: Text(printer.name),
        subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            trailing,
            IconButton(
              tooltip: 'Update print hours',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.speed_outlined, size: 20),
              onPressed: onEditHours,
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

class _RecentTile extends StatelessWidget {
  const _RecentTile({required this.entry, this.printerName});

  final LogEntry entry;
  final String? printerName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final details = <String>[
      ?printerName,
      formatDate(entry.performedAt),
      if (entry.cost != null) formatMoney(entry.cost!),
    ].join('  ·  ');

    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: const Icon(Icons.build_outlined),
      title: Text(entry.title),
      subtitle: Text(
        details,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}


class _BoardView extends StatelessWidget {
  const _BoardView({
    required this.printers,
    required this.schedules,
    required this.onLog,
    required this.onOpenPrinter,
  });

  final List<Printer> printers;
  final Map<int, List<PrinterTask>> schedules;
  final void Function(Printer, PrinterTask) onLog;
  final void Function(Printer) onOpenPrinter;

  static const List<String> _months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final cm = now.month - 1;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: <Widget>[
                  const SizedBox(width: 110),
                  Expanded(
                    child: Row(
                      children: List<Widget>.generate(_months.length, (i) {
                        final isNow = i == cm;
                        return Expanded(
                          child: Center(
                            child: Text(
                              _months[i],
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: isNow
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurfaceVariant,
                                fontWeight: isNow ? FontWeight.w600 : null,
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(width: 140),
                ],
              ),
            ),
            const Divider(height: 16),
            ...printers.expand((p) => _buildPrinterRows(context, p, cm, theme)),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildPrinterRows(
    BuildContext context,
    Printer p,
    int cm,
    ThemeData theme,
  ) {
    final rows = <Widget>[];
    final printerSchedules = schedules[p.id!] ?? const <PrinterTask>[];
    final tasks = [...printerSchedules]..sort((a, b) => a.taskName.compareTo(b.taskName));
    for (final t in tasks) {
      final s = DueStatus.evaluate(printer: p, schedule: t);
      int col = -1;
      String note = s.label;
      if (t.intervalHours != null && t.lastDoneHours != null) {
        final hInterval = t.intervalHours!;
        final hLast = t.lastDoneHours!;
        if (s.level != DueLevel.ok && s.level != DueLevel.unscheduled) {
          col = cm;
        }
        final remaining = hInterval - (p.totalPrintHours - hLast);
        if (remaining > 0) {
          note = '${_fmtHours(remaining)} h left';
        } else if (remaining < 0) {
          note = '${_fmtHours(-remaining)} h over';
        } else {
          note = 'Due now';
        }
      } else if (t.lastDoneAt != null) {
        final last = t.lastDoneAt!;
        DateTime due;
        final im = t.intervalMonths;
        if (im != null && im > 0) {
          due = DueStatus.addMonths(last, im);
        } else {
          final id = t.intervalDays ?? 0;
          due = DateTime.utc(last.year, last.month, last.day)
              .add(Duration(days: id));
        }
        col = due.month - 1;
        if (s.level == DueLevel.overdue) {
          note = 'Overdue · ${_fmtDate(due)}';
        } else if (s.level == DueLevel.dueSoon) {
          note = 'Due soon · ${_fmtDate(due)}';
        } else {
          note = 'Due ${_fmtDate(due)}';
        }
      }
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 110,
                child: Text(
                  t.taskName,
                  style: theme.textTheme.bodyMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Expanded(
                child: Row(
                  children: List<Widget>.generate(_months.length, (i) {
                    final isNow = i == cm;
                    final isMark = i == col;
                    Color? bg;
                    if (isMark) {
                      bg = s.level == DueLevel.overdue
                          ? theme.colorScheme.errorContainer
                          : s.level == DueLevel.dueSoon
                              ? theme.colorScheme.tertiaryContainer
                              : theme.colorScheme.primaryContainer;
                    }
                    return Expanded(
                      child: Container(
                        height: 20,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(
                          color: bg,
                          borderRadius: BorderRadius.circular(4),
                          border: isNow
                              ? Border.all(color: theme.colorScheme.primary, width: 1.5)
                              : null,
                        ),
                      ),
                    );
                  }),
                ),
              ),
              SizedBox(
                width: 140,
                child: Text(
                  note,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
      rows.add(const Divider(height: 1));
    }
    if (tasks.isNotEmpty) {
      rows.insert(
        0,
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            p.name,
            style: theme.textTheme.labelLarge,
          ),
        ),
      );
    }
    return rows;
  }

  String _fmtDate(DateTime d) {
    final y = d.year.toString();
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  String _fmtHours(double h) {
    if (h.abs() < 0.05) return '0.0';
    return h.toStringAsFixed(1);
  }
}

/// The small count beside a tablet sidebar row, mirroring the badges the macOS
/// sidebar uses: overdue and due soon, with nothing for a healthy printer.
class _SidebarCount extends StatelessWidget {
  const _SidebarCount({
    required this.count,
    required this.color,
    required this.foreground,
  });

  final int count;
  final Color color;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
      ),
    );
  }
}
