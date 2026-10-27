import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/format.dart';
import '../core/hijri.dart';
import '../core/strings.dart';
import '../data/store.dart';
import 'calendar_screen.dart' show shiftMonth;
import 'widgets/month_grid.dart';

/// Hijri-first date picker: a swipeable Hijri month grid with the matching
/// Gregorian date shown for the current selection.
Future<HDate?> pickHijriDate(BuildContext context, HDate initial) =>
    showDialog<HDate>(
        context: context, builder: (_) => _HijriPicker(initial: initial));

class _HijriPicker extends StatefulWidget {
  final HDate initial;
  const _HijriPicker({required this.initial});

  @override
  State<_HijriPicker> createState() => _HijriPickerState();
}

class _HijriPickerState extends State<_HijriPicker> {
  static const _origin = 10000;
  final _pager = PageController(initialPage: _origin);
  int page = _origin;
  late HDate selected = widget.initial;

  (int, int) _monthAt(int p) =>
      shiftMonth(widget.initial.y, widget.initial.m, p - _origin);

  void _step(int delta) => _pager.animateToPage(page + delta,
      duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ur = isUr(context);
    final theme = Theme.of(context);
    final (y, m) = _monthAt(page);
    return AlertDialog(
      contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      title: Text(tr(context, 'pick_hijri')),
      content: SizedBox(
        width: 360,
        height: 410,
        child: Column(children: [
          Row(children: [
            IconButton(
                onPressed: () => _step(-1),
                icon: const Icon(Icons.chevron_left)),
            Expanded(
              child: Text('${hijriMonthName(m, ur)} $y',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium),
            ),
            IconButton(
                onPressed: () => _step(1),
                icon: const Icon(Icons.chevron_right)),
          ]),
          Expanded(
            child: PageView.builder(
              controller: _pager,
              onPageChanged: (p) => setState(() => page = p),
              itemBuilder: (_, p) {
                final (py, pm) = _monthAt(p);
                return MonthGrid(
                  ur: ur,
                  cells: hijriMonthCells(py, pm, ur),
                  selectedKey: gKey(store.gregOfHijri(selected)),
                  onTap: (c) {
                    HapticFeedback.selectionClick();
                    setState(() => selected = c.hijri);
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(children: [
              Text(fmtHijri(selected, ur), style: theme.textTheme.titleSmall),
              Text(fmtGreg(store.gregOfHijri(selected), ur),
                  style: theme.textTheme.bodySmall!
                      .copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ]),
          ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr(context, 'cancel'))),
        FilledButton(
            onPressed: () => Navigator.pop(context, selected),
            child: Text(tr(context, 'ok'))),
      ],
    );
  }
}
