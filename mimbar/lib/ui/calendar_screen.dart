import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/format.dart';
import '../core/hijri.dart';
import '../core/strings.dart';
import '../data/models.dart';
import '../data/store.dart';
import 'widgets/event_card.dart';
import 'widgets/month_grid.dart';

/// Month grid on the top half, that month's events (or the tapped day's) on
/// the bottom half. The month can be a Hijri or a Gregorian month.
///
/// Months live in a PageView so the grid follows the finger 1:1 and snaps
/// with the release velocity; in Urdu the paging direction mirrors.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

/// (year, month) shifted by [delta] months; both calendars have 12 months.
(int, int) shiftMonth(int y, int m, int delta) {
  final t = y * 12 + (m - 1) + delta;
  return (t ~/ 12, t % 12 + 1);
}

class _CalendarScreenState extends State<CalendarScreen> {
  static const _origin = 10000;
  final _pager = PageController(initialPage: _origin);

  bool hijriMode = true;
  late int baseY, baseM; // month shown at page [_origin]
  int page = _origin;
  int? selectedKey;

  (int, int) get _month => shiftMonth(baseY, baseM, page - _origin);

  @override
  void initState() {
    super.initState();
    baseY = store.todayHijri.y;
    baseM = store.todayHijri.m;
  }

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  (int, int) _todayMonth(bool hijri) {
    if (hijri) return (store.todayHijri.y, store.todayHijri.m);
    final n = DateTime.now();
    return (n.year, n.month);
  }

  void _toggleMode(bool toHijri) {
    if (toHijri == hijriMode) return;
    HapticFeedback.selectionClick();
    final (y, m) = _month;
    setState(() {
      // Keep roughly the same period on screen when switching.
      if (toHijri) {
        final h = store.hijriOfGreg(DateTime(y, m, 15));
        baseY = h.y;
        baseM = h.m;
      } else {
        final g = store.gregOfHijri(HDate(y, m, 15));
        baseY = g.year;
        baseM = g.month;
      }
      hijriMode = toHijri;
      selectedKey = null;
      page = _origin;
    });
    _pager.jumpToPage(_origin);
  }

  void _step(int delta) => _pager.animateToPage(page + delta,
      duration: const Duration(milliseconds: 340), curve: Curves.easeOutCubic);

  void _goToday() {
    final (ty, tm) = _todayMonth(hijriMode);
    final (cy, cm) = _month;
    final delta = (ty * 12 + tm) - (cy * 12 + cm);
    if (delta == 0) return;
    if (delta.abs() <= 3) {
      _step(delta);
    } else {
      _pager.jumpToPage(page + delta);
    }
  }

  List<MonthCell> _cells(int y, int m, bool ur) =>
      hijriMode ? hijriMonthCells(y, m, ur) : gregMonthCells(y, m, ur);

  List<Event> _eventsIn(List<MonthCell> cells) {
    final firstK = gKey(cells.first.greg), lastK = gKey(cells.last.greg);
    return store.events.where((e) {
      final k = gKey(store.gregOf(e));
      return k >= firstK && k <= lastK;
    }).toList();
  }

  Map<int, List<Color>> _markers(List<Event> inMonth) {
    final markers = <int, List<Color>>{};
    for (final e in inMonth) {
      final c = e.status == EventStatus.cancelled
          ? const Color(0xFFBDBDBD)
          : store.isClashing(e)
              ? clashColor
              : typeColor(e.type);
      final list = markers.putIfAbsent(gKey(store.gregOf(e)), () => []);
      if (!list.contains(c)) list.add(c);
    }
    return markers;
  }

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: store, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final ur = isUr(context);
    final theme = Theme.of(context);
    final (y, m) = _month;
    final cells = _cells(y, m, ur);
    final inMonth = _eventsIn(cells);
    final shown = selectedKey == null
        ? inMonth
        : inMonth.where((e) => gKey(store.gregOf(e)) == selectedKey).toList();
    final groups = store.groupForDisplay(shown);

    final title = hijriMode
        ? '${hijriMonthName(m, ur)} $y${ur ? 'ھ' : ''}'
        : '${gregMonthName(m, ur, full: true)} $y';

    return LayoutBuilder(builder: (context, box) {
      return Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
          child: Row(children: [
            IconButton(
                onPressed: () => _step(-1),
                icon: const Icon(Icons.chevron_left)),
            Expanded(
              child: GestureDetector(
                onTap: _goToday,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: Text(title,
                      key: ValueKey(title),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium),
                ),
              ),
            ),
            IconButton(
                onPressed: () => _step(1),
                icon: const Icon(Icons.chevron_right)),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: [
                ButtonSegment(value: true, label: Text(tr(context, 'hijri_view'))),
                ButtonSegment(value: false, label: Text(tr(context, 'greg_view'))),
              ],
              selected: {hijriMode},
              onSelectionChanged: (s) => _toggleMode(s.first),
            ),
          ]),
        ),
        SizedBox(
          height: box.maxHeight * 0.5,
          child: PageView.builder(
            controller: _pager,
            onPageChanged: (p) => setState(() {
              page = p;
              selectedKey = null;
            }),
            itemBuilder: (context, p) {
              final (py, pm) = shiftMonth(baseY, baseM, p - _origin);
              final pc = _cells(py, pm, ur);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: MonthGrid(
                  ur: ur,
                  cells: pc,
                  markers: _markers(_eventsIn(pc)),
                  selectedKey: p == page ? selectedKey : null,
                  onTap: (c) {
                    HapticFeedback.selectionClick();
                    setState(() {
                      final k = gKey(c.greg);
                      selectedKey = selectedKey == k ? null : k;
                    });
                  },
                ),
              );
            },
          ),
        ),
        const Divider(height: 1),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: selectedKey == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                  child: Row(children: [
                    Expanded(
                      child: Builder(builder: (_) {
                        final c =
                            cells.firstWhere((c) => gKey(c.greg) == selectedKey);
                        return Text(
                            '${fmtHijri(c.hijri, ur)} · ${fmtGreg(c.greg, ur)}',
                            style: theme.textTheme.labelLarge);
                      }),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() => selectedKey = null),
                    ),
                  ]),
                ),
        ),
        Expanded(
          child: groups.isEmpty
              ? Center(
                  child: Text(tr(context, 'no_events'),
                      style: TextStyle(color: theme.colorScheme.onSurfaceVariant)))
              : ListView.separated(
                  padding: EdgeInsets.fromLTRB(
                      12, 10, 12, MediaQuery.paddingOf(context).bottom + 16),
                  itemCount: groups.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => EventGroupCard(groups[i]),
                ),
        ),
      ]);
    });
  }
}
