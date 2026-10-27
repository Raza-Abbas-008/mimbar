import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/hijri.dart';
import '../core/strings.dart';
import '../data/models.dart';
import '../data/store.dart';
import 'widgets/event_card.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: store, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final ur = isUr(context);
    final theme = Theme.of(context);
    final now = DateTime.now();
    final todayK = gKey(now);
    final todays =
        store.events.where((e) => gKey(store.gregOf(e)) == todayK).toList();
    final upcoming =
        store.events.where((e) => gKey(store.gregOf(e)) > todayK).toList();

    Widget heading(String key) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
          child: Text(tr(context, key),
              style: theme.textTheme.titleMedium!
                  .copyWith(fontWeight: FontWeight.w700)),
        );

    Widget empty(String key) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: Text(tr(context, key),
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
          ),
        );

    List<Widget> cards(List<Event> list) => [
          for (final g in store.groupForDisplay(list))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: EventGroupCard(g),
            ),
        ];

    return ListView(
      padding: EdgeInsets.fromLTRB(
          16, 8, 16, MediaQuery.paddingOf(context).bottom + 88),
      children: [
        Card(
          margin: EdgeInsets.zero,
          color: theme.colorScheme.primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(weekdayName(now.weekday, ur, full: true),
                  style: TextStyle(color: theme.colorScheme.onPrimary.withValues(alpha: 0.8))),
              const SizedBox(height: 2),
              Text(fmtHijri(store.todayHijri, ur),
                  style: theme.textTheme.headlineSmall!.copyWith(
                      color: theme.colorScheme.onPrimary,
                      fontWeight: FontWeight.w700)),
              Text(fmtGreg(now, ur, weekday: false),
                  style: TextStyle(color: theme.colorScheme.onPrimary)),
            ]),
          ),
        ),
        heading('today'),
        if (todays.isEmpty) empty('no_today') else ...cards(todays),
        heading('upcoming'),
        if (upcoming.isEmpty) empty('no_upcoming') else ...cards(upcoming),
      ],
    );
  }
}
