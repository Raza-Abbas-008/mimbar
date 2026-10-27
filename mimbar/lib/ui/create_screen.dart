import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../core/format.dart';
import '../core/hijri.dart';
import '../core/strings.dart';
import '../data/models.dart';
import '../data/store.dart';
import 'selection.dart';
import 'widgets/event_card.dart';

/// Keep-style grid. The scroll view is centred on today: upcoming events grow
/// downwards, and past events sit above and are revealed by scrolling up.
class CreateScreen extends StatefulWidget {
  const CreateScreen({super.key});

  @override
  State<CreateScreen> createState() => _CreateScreenState();
}

class _CreateScreenState extends State<CreateScreen> {
  final _centerKey = UniqueKey();
  String q = '';
  final types = <EventType>{};
  final statuses = <EventStatus>{};

  bool _matches(Event e) {
    if (types.isNotEmpty && !types.contains(e.type)) return false;
    if (statuses.isNotEmpty && !statuses.contains(e.status)) return false;
    final s = q.trim().toLowerCase();
    if (s.isEmpty) return true;
    final host = store.hostOf(e);
    final phoneQ = normalizePhone(s);
    return [
      host?.name,
      e.venue,
      e.topic,
    ].any((f) => f != null && f.toLowerCase().contains(s)) ||
        (phoneQ.isNotEmpty && (host?.phone.contains(phoneQ) ?? false));
  }

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: store, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final ur = isUr(context);
    final theme = Theme.of(context);
    final todayK = gKey(DateTime.now());
    final filtered = store.events.where(_matches).toList();
    eventSelection.setVisible('create', [for (final e in filtered) e.id!]);
    final upcoming = store.groupForDisplay(
        filtered.where((e) => gKey(store.gregOf(e)) >= todayK).toList());
    // Most recent first, so the newest past event sits just above today.
    final past = store
        .groupForDisplay(
            filtered.where((e) => gKey(store.gregOf(e)) < todayK).toList())
        .reversed
        .toList();

    SliverMasonryGrid grid(List<List<Event>> groups) => SliverMasonryGrid.count(
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childCount: groups.length,
          itemBuilder: (_, i) => EventGroupCard(groups[i], selectable: true),
        );

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: TextField(
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: tr(context, 'search_hint'),
            isDense: true,
          ),
          onChanged: (v) => setState(() => q = v),
        ),
      ),
      SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          children: [
            for (final t in EventType.values)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 6),
                child: FilterChip(
                  avatar: Icon(Icons.circle, size: 12, color: typeColor(t)),
                  label: Text(typeLabel(t, ur)),
                  selected: types.contains(t),
                  onSelected: (v) =>
                      setState(() => v ? types.add(t) : types.remove(t)),
                ),
              ),
            const VerticalDivider(),
            for (final s in EventStatus.values)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 6),
                child: FilterChip(
                  label: Text(statusLabel(s, ur)),
                  selected: statuses.contains(s),
                  onSelected: (v) =>
                      setState(() => v ? statuses.add(s) : statuses.remove(s)),
                ),
              ),
          ],
        ),
      ),
      Expanded(
        child: CustomScrollView(
          center: _centerKey,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              sliver: grid(past),
            ),
            SliverToBoxAdapter(
              key: _centerKey,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: Row(children: [
                  Text(
                    '${tr(context, 'today')} · ${fmtHijri(store.todayHijri, ur)}',
                    style: theme.textTheme.titleSmall!
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  if (past.isNotEmpty)
                    Flexible(
                      child: Text('↑ ${tr(context, 'scroll_up_past')}',
                          textAlign: TextAlign.end,
                          style: theme.textTheme.labelSmall!.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ),
                ]),
              ),
            ),
            if (upcoming.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(child: Text(tr(context, 'no_upcoming'))),
                ),
              ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                  12, 0, 12, MediaQuery.paddingOf(context).bottom + 88),
              sliver: grid(upcoming),
            ),
          ],
        ),
      ),
    ]);
  }
}
