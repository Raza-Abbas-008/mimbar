import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/strings.dart';
import '../data/models.dart';
import '../data/store.dart';
import '../services/sync.dart';
import 'calendar_screen.dart';
import 'create_screen.dart';
import 'event_form_screen.dart';
import 'home_screen.dart';
import 'selection.dart';
import 'settings_screen.dart';
import 'share_sheet.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  int tab = 0;
  Timer? _midnight;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _armMidnight();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnight?.cancel();
    super.dispose();
  }

  /// Re-checks the Hijri date (and auto-Done) just after midnight.
  void _armMidnight() {
    _midnight?.cancel();
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day + 1, 0, 0, 5);
    _midnight = Timer(next.difference(now), () {
      store.refreshDay();
      _armMidnight();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      store.refreshDay();
      _armMidnight();
      sync.request(delay: Duration.zero);
    }
  }

  static const _tabKeys = ['home', 'create', 'calendar'];

  List<Event> get _picked => [
    for (final id in eventSelection.ids) ?store.eventById(id),
  ];

  Future<void> _deleteSelected() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr(c, 'delete_events_q')),
        content: Text(
          '${_picked.length} ${tr(c, 'events_count')}. ${tr(c, 'delete_body')}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(tr(c, 'cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(c, true),
            child: Text(tr(c, 'delete')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await store.deleteEvents(_picked);
    eventSelection.clear();
  }

  Future<void> _statusSelected() async {
    final ur = isUr(context);
    final s = await showDialog<EventStatus>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text(tr(c, 'change_status')),
        children: [
          for (final st in EventStatus.values)
            SimpleDialogOption(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              onPressed: () => Navigator.pop(c, st),
              child: Text(statusLabel(st, ur)),
            ),
        ],
      ),
    );
    if (s == null) return;
    HapticFeedback.lightImpact();
    await store.setStatus(_picked, s);
    eventSelection.clear();
  }

  PreferredSizeWidget _selectionBar(BuildContext context) => AppBar(
    leading: IconButton(
      tooltip: tr(context, 'cancel'),
      icon: const Icon(Icons.close),
      onPressed: eventSelection.clear,
    ),
    title: Text('${eventSelection.ids.length} ${tr(context, 'selected')}'),
    actions: [
      IconButton(
        tooltip: tr(context, 'select_all'),
        icon: const Icon(Icons.select_all),
        onPressed: () => eventSelection.selectAll(_tabKeys[tab]),
      ),
      IconButton(
        tooltip: tr(context, 'share'),
        icon: const Icon(Icons.share),
        onPressed: () => showEventsShare(context, _picked),
      ),
      IconButton(
        tooltip: tr(context, 'change_status'),
        icon: const Icon(Icons.fact_check_outlined),
        onPressed: _statusSelected,
      ),
      IconButton(
        tooltip: tr(context, 'delete'),
        icon: const Icon(Icons.delete_outline),
        onPressed: _deleteSelected,
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: eventSelection,
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    const titles = ['app_name', 'tab_create', 'tab_calendar'];
    final selecting = eventSelection.active;
    return PopScope(
      // Back leaves selection mode first.
      canPop: !selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) eventSelection.clear();
      },
      child: _scaffold(context, titles, selecting),
    );
  }

  Widget _scaffold(BuildContext context, List<String> titles, bool selecting) {
    return Scaffold(
      appBar: selecting
          ? _selectionBar(context)
          : AppBar(
              title: Text(tr(context, titles[tab])),
              actions: [
                IconButton(
                  tooltip: tr(context, 'settings'),
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  ),
                ),
              ],
            ),
      body: IndexedStack(
        index: tab,
        children: const [HomeScreen(), CreateScreen(), CalendarScreen()],
      ),
      floatingActionButton: tab == 2 || selecting
          ? null
          : FloatingActionButton.extended(
              elevation: 3,
              icon: const Icon(Icons.add),
              label: Text(tr(context, 'new_event')),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const EventFormScreen()),
              ),
            ),
      // Content scrolls under a frosted, translucent tab bar.
      extendBody: true,
      bottomNavigationBar: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0x14000000))),
            ),
            child: _tabBar(context),
          ),
        ),
      ),
    );
  }

  Widget _tabBar(BuildContext context) => NavigationBar(
    selectedIndex: tab,
    onDestinationSelected: (i) {
      if (i != tab) {
        HapticFeedback.selectionClick();
        eventSelection.clear();
      }
      setState(() => tab = i);
    },
    destinations: [
      NavigationDestination(
        icon: const Icon(Icons.home_outlined),
        selectedIcon: const Icon(Icons.home),
        label: tr(context, 'tab_home'),
      ),
      NavigationDestination(
        icon: const Icon(Icons.dashboard_outlined),
        selectedIcon: const Icon(Icons.dashboard),
        label: tr(context, 'tab_create'),
      ),
      NavigationDestination(
        icon: const Icon(Icons.calendar_month_outlined),
        selectedIcon: const Icon(Icons.calendar_month),
        label: tr(context, 'tab_calendar'),
      ),
    ],
  );
}
