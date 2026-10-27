import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/strings.dart';
import '../data/store.dart';
import '../services/sync.dart';
import 'calendar_screen.dart';
import 'create_screen.dart';
import 'event_form_screen.dart';
import 'home_screen.dart';
import 'settings_screen.dart';

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

  @override
  Widget build(BuildContext context) {
    const titles = ['app_name', 'tab_create', 'tab_calendar'];
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, titles[tab])),
        actions: [
          IconButton(
            tooltip: tr(context, 'settings'),
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: IndexedStack(
        index: tab,
        children: const [HomeScreen(), CreateScreen(), CalendarScreen()],
      ),
      floatingActionButton: tab == 2
          ? null
          : FloatingActionButton.extended(
              elevation: 3,
              icon: const Icon(Icons.add),
              label: Text(tr(context, 'new_event')),
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const EventFormScreen())),
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
          if (i != tab) HapticFeedback.selectionClick();
          setState(() => tab = i);
        },
        destinations: [
          NavigationDestination(
              icon: const Icon(Icons.home_outlined),
              selectedIcon: const Icon(Icons.home),
              label: tr(context, 'tab_home')),
          NavigationDestination(
              icon: const Icon(Icons.dashboard_outlined),
              selectedIcon: const Icon(Icons.dashboard),
              label: tr(context, 'tab_create')),
          NavigationDestination(
              icon: const Icon(Icons.calendar_month_outlined),
              selectedIcon: const Icon(Icons.calendar_month),
              label: tr(context, 'tab_calendar')),
        ],
      );
}
