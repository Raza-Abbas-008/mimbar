import 'package:hijri/hijri_calendar.dart';

/// A Hijri (Umm al-Qura) calendar date. This is the source of truth for every
/// event; Gregorian dates are always derived from it.
class HDate implements Comparable<HDate> {
  final int y, m, d;
  const HDate(this.y, this.m, this.d);

  int get key => y * 10000 + m * 100 + d;

  /// Calculated Gregorian date with no moon-sighting offset applied.
  DateTime toGregorianRaw() {
    final g = HijriCalendar().hijriToGregorian(y, m, d);
    return DateTime(g.year, g.month, g.day);
  }

  static HDate fromGregorianRaw(DateTime g) {
    final h = HijriCalendar.fromDate(DateTime(g.year, g.month, g.day));
    return HDate(h.hYear, h.hMonth, h.hDay);
  }

  HDate addDays(int n) => fromGregorianRaw(addDaysTo(toGregorianRaw(), n));

  static int daysInMonth(int y, int m) {
    final first = HDate(y, m, 1).toGregorianRaw();
    final next = (m == 12 ? HDate(y + 1, 1, 1) : HDate(y, m + 1, 1)).toGregorianRaw();
    return DateTime.utc(next.year, next.month, next.day)
        .difference(DateTime.utc(first.year, first.month, first.day))
        .inDays;
  }

  @override
  int compareTo(HDate other) => key.compareTo(other.key);

  @override
  bool operator ==(Object other) => other is HDate && other.key == key;

  @override
  int get hashCode => key;

  @override
  String toString() => '$y-$m-$d';
}

/// Date-only arithmetic that is safe across DST changes.
DateTime addDaysTo(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// yyyymmdd integer key for a Gregorian date.
int gKey(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

const hijriMonthsEn = [
  'Muharram', 'Safar', 'Rabi al-Awwal', 'Rabi al-Thani', 'Jumada al-Ula',
  'Jumada al-Thani', 'Rajab', 'Shaban', 'Ramadan', 'Shawwal', 'Dhul Qadah',
  'Dhul Hijjah',
];

const hijriMonthsUr = [
  'محرم', 'صفر', 'ربیع الاول', 'ربیع الثانی', 'جمادی الاول', 'جمادی الثانی',
  'رجب', 'شعبان', 'رمضان', 'شوال', 'ذیقعد', 'ذوالحج',
];
