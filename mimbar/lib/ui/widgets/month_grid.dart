import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/hijri.dart';
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

/// Monday-first month grid that fills the space it is given. Row order
/// follows the text direction, so it mirrors in Urdu.
class MonthGrid extends StatelessWidget {
  final List<MonthCell> cells;
  final int? selectedKey;
  final Map<int, List<Color>> markers;
  final void Function(MonthCell) onTap;
  final bool ur;

  const MonthGrid({
    super.key,
    required this.cells,
    required this.onTap,
    required this.ur,
    this.selectedKey,
    this.markers = const {},
  });

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
      final dots = markers[k] ?? const [];
      return InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => onTap(c),
        child: Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: selected ? theme.colorScheme.primaryContainer : null,
            borderRadius: BorderRadius.circular(10),
            border: today
                ? Border.all(color: theme.colorScheme.primary, width: 1.5)
                : null,
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(c.primary,
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 16,
                      fontWeight: today ? FontWeight.w800 : FontWeight.w600,
                    )),
                Text(c.secondary,
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.2,
                      color: theme.colorScheme.onSurfaceVariant,
                    )),
                SizedBox(
                  height: 7,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    for (final col in dots.take(4))
                      Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration:
                            BoxDecoration(color: col, shape: BoxShape.circle),
                      ),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      );
    }

    return Column(children: [
      Row(children: [
        for (var wd = 1; wd <= 7; wd++)
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(weekdayName(wd, ur),
                    style: theme.textTheme.labelSmall!.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
              ),
            ),
          ),
      ]),
      Expanded(
        child: Column(children: [
          for (var r = 0; r < rows; r++)
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < 7; i++)
                    Expanded(child: cell(slots[r * 7 + i])),
                ],
              ),
            ),
        ]),
      ),
    ]);
  }
}
