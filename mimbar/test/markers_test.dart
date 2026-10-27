import 'package:flutter_test/flutter_test.dart';
import 'package:mimbar/core/hijri.dart';
import 'package:mimbar/core/markers.dart';
import 'package:mimbar/data/models.dart';

Event ev(EventType t, {EventStatus s = EventStatus.confirmed}) => Event(
    type: t, hijri: const HDate(1448, 5, 1), startMin: 0, endMin: 60, status: s);

const m = EventType.majlis, l = EventType.milad, n = EventType.nikkah;

void main() {
  bool noClash(Event _) => false;

  test('one type is a bar with its count', () {
    final d = marksFor([ev(l), ev(l), ev(l)], noClash)!;
    expect(d.isBar, isTrue);
    expect(d.counts, {l: 3});
  });

  test('several types are dots in Majlis, Milad, Nikkah order', () {
    final d = marksFor([ev(n), ev(l), ev(l), ev(l)], noClash)!;
    expect(d.isBar, isFalse);
    expect(d.counts.keys.toList(), [l, n]);
    expect(d.counts, {l: 3, n: 1});
    expect(marksFor([ev(n), ev(l), ev(m)], noClash)!.counts.keys.toList(),
        [m, l, n]);
  });

  test('cancelled events are not counted', () {
    final d = marksFor(
        [ev(l), ev(m, s: EventStatus.cancelled)], noClash)!;
    expect(d.isBar, isTrue);
    expect(d.counts, {l: 1});
    expect(marksFor([ev(m, s: EventStatus.cancelled)], noClash), isNull);
  });

  test('a clash on any counted event flags the day', () {
    final a = ev(m), b = ev(m);
    expect(marksFor([a, b], (e) => identical(e, b))!.clash, isTrue);
    expect(marksFor([a, b], noClash)!.clash, isFalse);
  });
}
