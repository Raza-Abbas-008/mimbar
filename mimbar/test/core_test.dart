import 'package:flutter_test/flutter_test.dart';
import 'package:mimbar/core/hijri.dart';
import 'package:mimbar/data/models.dart';

void main() {
  group('Hijri (Umm al-Qura)', () {
    test('known month starts convert to the right Gregorian date', () {
      expect(const HDate(1446, 9, 1).toGregorianRaw(), DateTime(2025, 3, 1));
      expect(const HDate(1447, 1, 1).toGregorianRaw(), DateTime(2025, 6, 26));
      expect(const HDate(1447, 1, 10).toGregorianRaw(), DateTime(2025, 7, 5));
    });

    test('round-trips Gregorian -> Hijri -> Gregorian over 1440-1470', () {
      var g = const HDate(1440, 1, 1).toGregorianRaw();
      final end = const HDate(1470, 12, 1).toGregorianRaw();
      while (g.isBefore(end)) {
        final h = HDate.fromGregorianRaw(g);
        expect(h.toGregorianRaw(), g, reason: '$g -> $h');
        g = addDaysTo(g, 7);
      }
    });

    test('months are 29 or 30 days', () {
      for (var y = 1440; y <= 1470; y++) {
        for (var m = 1; m <= 12; m++) {
          expect(HDate.daysInMonth(y, m), inInclusiveRange(29, 30),
              reason: '$y-$m');
        }
      }
    });

    test('addDays crosses month and year boundaries', () {
      final last = HDate(1446, 12, HDate.daysInMonth(1446, 12));
      expect(last.addDays(1), const HDate(1447, 1, 1));
      // An Ashra starting 1 Muharram ends on 10 Muharram.
      expect(const HDate(1447, 1, 1).addDays(9), const HDate(1447, 1, 10));
    });
  });

  group('normalizePhone', () {
    test('Pakistani forms are equal', () {
      const expected = '03001234567';
      for (final raw in [
        '0300 1234567',
        '0300-123-4567',
        '+92 300 1234567',
        '+923001234567',
        '00923001234567',
        '923001234567',
      ]) {
        expect(normalizePhone(raw), expected, reason: raw);
      }
    });

    test('foreign numbers keep their plus', () {
      expect(normalizePhone('+44 7700 900123'), '+447700900123');
    });
  });

  group('Event', () {
    test('duration handles past-midnight end', () {
      final e = Event(
          type: EventType.majlis,
          hijri: const HDate(1447, 1, 1),
          startMin: 23 * 60,
          endMin: 30);
      expect(e.durationMin, 90);
    });

    test('map round-trip keeps every field', () {
      final e = Event(
        id: 4,
        type: EventType.nikkah,
        hijri: const HDate(1447, 3, 12),
        gregOverride: DateTime(2025, 9, 5),
        startMin: 600,
        endMin: 660,
        venue: 'Imambargah',
        hostId: 2,
        topic: 'x',
        status: EventStatus.tentative,
        seriesId: 's1',
        seriesIndex: 2,
        seriesTotal: 10,
      );
      expect(Event.fromMap(e.toMap()).toMap(), e.toMap());
    });
  });

  test('settings defaults and round-trip', () {
    final d = AppSettings.defaults();
    expect(d.durations[EventType.majlis], 90);
    expect(d.durations[EventType.milad], 90);
    expect(d.durations[EventType.nikkah], 60);
    final s = d.copy()
      ..lang = 'ur'
      ..offset = -1
      ..reminderLeads = [];
    final back = AppSettings.fromKv(s.toKv());
    expect(back.lang, 'ur');
    expect(back.offset, -1);
    expect(back.reminderLeads, isEmpty);
  });
}
