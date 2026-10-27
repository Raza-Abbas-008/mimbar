import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/hijri.dart';
import '../../core/markers.dart';
import '../../data/store.dart';

class MonthCell {
  final DateTime greg;
  final HDate hijri;
  final String primary;
  final String secondary;
  const MonthCell(this.greg, this.hijri, this.primary, this.secondary);
}

/// Cells for a Hijri month; each shows the Hijri day with the Gregorian day
/// beneath it.
List<MonthCell> hijriMonthCells(int y, int m, bool ur) {
  final n = HDate.daysInMonth(y, m);
  return [
    for (var d = 1; d <= n; d++)
      () {
        final h = HDate(y, m, d);
        final g = store.gregOfHijri(h);
        final sec = (d == 1 || g.day == 1)
            ? '${g.day} ${gregMonthName(g.month, ur)}'
            : '${g.day}';
        return MonthCell(g, h, '$d', sec);
      }(),
  ];
}

/// Cells for a Gregorian month; each shows the Gregorian day with the Hijri
/// day beneath it.
List<MonthCell> gregMonthCells(int y, int m, bool ur) {
  final n = DateUtils.getDaysInMonth(y, m);
  return [
    for (var d = 1; d <= n; d++)
      () {
        final g = DateTime(y, m, d);
        final h = store.hijriOfGreg(g);
        final sec = (d == 1 || h.d == 1)
            ? '${h.d} ${hijriMonthName(h.m, ur)}'
            : '${h.d}';
        return MonthCell(g, h, '$d', sec);
      }(),
  ];
}

/// Monday-first month grid. With [rowHeight] the rows have that fixed
/// height (the Calendar tab); without it they share the space given (the
/// date picker). Row order follows the text direction, so it mirrors in
/// Urdu.
class MonthGrid extends StatelessWidget {
  final List<MonthCell> cells;
  final int? selectedKey;
  final Map<int, DayMarks> markers;
  final void Function(MonthCell) onTap;
  final bool ur;
  final double? rowHeight;

  const MonthGrid({
    super.key,
    required this.cells,
    required this.onTap,
    required this.ur,
    this.selectedKey,
    this.markers = const {},
    this.rowHeight,
  });

  static const weekdayRowHeight = 22.0;

  /// Height of the grid for [cells] with fixed rows of [rowHeight].
  static double heightFor(List<MonthCell> cells, double rowHeight) {
    final lead = cells.first.greg.weekday - 1;
    final rows = ((lead + cells.length) / 7).ceil();
    return weekdayRowHeight + rows * rowHeight;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final todayKey = gKey(DateTime.now());
    final lead = cells.first.greg.weekday - 1;
    final slots = <MonthCell?>[
      ...List.filled(lead, null),
      ...cells,
    ];
    while (slots.length % 7 != 0) {
      slots.add(null);
    }
    final rows = slots.length ~/ 7;

    Widget cell(MonthCell? c) {
      if (c == null) return const SizedBox.shrink();
      final k = gKey(c.greg);
      final selected = k == selectedKey;
      final today = k == todayKey;
      final marks = markers[k];
      return InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => onTap(c),
        child: Container(
          margin: const EdgeInsets.all(1.5),
          padding: const EdgeInsets.fromLTRB(3, 3, 3, 4),
          decoration: BoxDecoration(
            color: selected ? theme.colorScheme.primaryContainer : null,
            borderRadius: BorderRadius.circular(10),
            border: today
                ? Border.all(color: theme.colorScheme.primary, width: 1.5)
                : null,
          ),
          child: Stack(clipBehavior: Clip.none, children: [
            Column(children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(c.primary,
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: 15,
                          height: 1.1,
                          fontWeight: today ? FontWeight.w800 : FontWeight.w600,
                        )),
                    Text(c.secondary,
                        style: TextStyle(
                          fontSize: 9,
                          height: 1.15,
                          color: theme.colorScheme.onSurfaceVariant,
                        )),
                  ]),
                ),
              ),
              if (marks != null)
                Opacity(
                  opacity: k < todayKey ? 0.38 : 1,
                  child: DayMarker(marks),
                ),
            ]),
            if (marks?.clash ?? false)
              const PositionedDirectional(
                top: -1,
                end: -1,
                child: Icon(Icons.warning_rounded,
                    size: 11, color: Color(0xFFFFB300)),
              ),
          ]),
        ),
      );
    }

    final weekdays = Row(children: [
      for (var wd = 1; wd <= 7; wd++)
        Expanded(
          child: SizedBox(
            height: weekdayRowHeight,
            child: Center(
              child: Text(weekdayName(wd, ur),
                  style: theme.textTheme.labelSmall!
                      .copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
          ),
        ),
    ]);

    Widget row(int r) => Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < 7; i++) Expanded(child: cell(slots[r * 7 + i])),
          ],
        );

    if (rowHeight != null) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        weekdays,
        for (var r = 0; r < rows; r++) SizedBox(height: rowHeight, child: row(r)),
      ]);
    }
    return Column(children: [
      weekdays,
      Expanded(
        child: Column(children: [
          for (var r = 0; r < rows; r++) Expanded(child: row(r)),
        ]),
      ),
    ]);
  }
}

/// One type of event on a day: a wide bar in its colour, with the count
/// when there is more than one. Several types: one dot per type.
class DayMarker extends StatelessWidget {
  final DayMarks marks;
  const DayMarker(this.marks, {super.key});

  static const size = 11.0;

  static Widget _count(int n) => n > 1
      ? Text('$n',
          style: const TextStyle(
              fontFamily: 'Roboto',
              color: Colors.white,
              fontSize: 8.5,
              height: 1,
              fontWeight: FontWeight.w700))
      : const SizedBox.shrink();

  @override
  Widget build(BuildContext context) {
    if (marks.isBar) {
      final MapEntry(key: type, value: n) = marks.counts.entries.first;
      return Container(
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: typeColor(type), borderRadius: BorderRadius.circular(3)),
        child: _count(n),
      );
    }
    return SizedBox(
      height: size,
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (final MapEntry(key: type, value: n) in marks.counts.entries)
          Container(
            constraints: const BoxConstraints(minWidth: size),
            height: size,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: typeColor(type),
                borderRadius: BorderRadius.circular(size / 2)),
            child: _count(n),
          ),
      ]),
    );
  }
}
