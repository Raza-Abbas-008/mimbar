import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/format.dart';
import '../core/hijri.dart';
import '../core/markers.dart';
import '../core/strings.dart';
import '../data/models.dart';
import '../data/store.dart';
import 'selection.dart';
import 'widgets/event_card.dart';
import 'widgets/month_grid.dart';

/// A pinned month header, then (when switched on) a compact month grid that
/// scrolls away with the list of that month's events, or the tapped day's.
/// The month can be a Hijri or a Gregorian month.
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

  Map<int, DayMarks> _markers(List<Event> inMonth) {
    final byDay = <int, List<Event>>{};
    for (final e in inMonth) {
      byDay.putIfAbsent(gKey(store.gregOf(e)), () => []).add(e);
    }
    return {
      for (final MapEntry(key: k, value: list) in byDay.entries)
        k: ?marksFor(list, store.isClashing),
    };
  }

  static const _rowHeight = 46.0;

  void _toggleCalendar() {
    HapticFeedback.selectionClick();
    setState(() => selectedKey = null);
    store.setCalendarOn(!store.calendarOn);
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
    eventSelection.setVisible('calendar', [for (final e in shown) e.id!]);

    final title = hijriMode
        ? '${hijriMonthName(m, ur)} $y${ur ? 'ھ' : ''}'
        : '${gregMonthName(m, ur, full: true)} $y';

    final on = store.calendarOn;
    final header = Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(4, 2, 8, 2),
      child: Row(children: [
        IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => _step(-1),
            icon: const Icon(Icons.chevron_left)),
        Expanded(
          child: GestureDetector(
            onTap: _goToday,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              // Long month names shrink rather than wrap.
              child: FittedBox(
                key: ValueKey(title),
                fit: BoxFit.scaleDown,
                child: Text(title,
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium),
              ),
            ),
          ),
        ),
        IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => _step(1),
            icon: const Icon(Icons.chevron_right)),
        on
            ? IconButton.filled(
                visualDensity: VisualDensity.compact,
                tooltip: tr(context, 'hide_calendar'),
                onPressed: _toggleCalendar,
                icon: const Icon(Icons.calendar_month_outlined, size: 20))
            : IconButton.outlined(
                visualDensity: VisualDensity.compact,
                tooltip: tr(context, 'show_calendar'),
                onPressed: _toggleCalendar,
                icon: const Icon(Icons.event_busy_outlined, size: 20)),
        const SizedBox(width: 4),
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
    );

    final grid = AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      height: MonthGrid.heightFor(cells, _rowHeight) + 6,
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
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
            child: Align(
              alignment: Alignment.topCenter,
              child: MonthGrid(
                ur: ur,
                cells: pc,
                rowHeight: _rowHeight,
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
            ),
          );
        },
      ),
    );

    final dayBar = selectedKey == null
        ? null
        : Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            child: Row(children: [
              Expanded(
                child: Builder(builder: (_) {
                  final c = cells.firstWhere((c) => gKey(c.greg) == selectedKey);
                  return Text('${fmtHijri(c.hijri, ur)} · ${fmtGreg(c.greg, ur)}',
                      style: theme.textTheme.labelLarge);
                }),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => setState(() => selectedKey = null),
              ),
            ]),
          );

    return Column(children: [
      header,
      const Divider(height: 1),
      Expanded(
        child: CustomScrollView(slivers: [
          if (on) ...[
            SliverToBoxAdapter(child: grid),
            const SliverToBoxAdapter(child: Divider(height: 1)),
          ],
          if (dayBar != null) SliverToBoxAdapter(child: dayBar),
          if (groups.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text(tr(context, 'no_events'),
                      style:
                          TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                ),
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                  12, 10, 12, MediaQuery.paddingOf(context).bottom + 16),
              sliver: SliverList.separated(
                itemCount: groups.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) => EventGroupCard(groups[i], selectable: true),
              ),
            ),
        ]),
      ),
    ]);
  }
}
