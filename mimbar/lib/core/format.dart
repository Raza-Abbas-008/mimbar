import 'package:flutter/material.dart';

import '../data/models.dart';
import 'hijri.dart';
import 'strings.dart';

const majlisColor = Color(0xFF000000);
const miladColor = Color(0xFFC62828);
const nikkahColor = Color(0xFF2E7D32);
const clashColor = Color(0xFFFFC107);

Color typeColor(EventType t) => switch (t) {
      EventType.majlis => majlisColor,
      EventType.milad => miladColor,
      EventType.nikkah => nikkahColor,
    };

const _gMonthsEn = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
const _gMonthsFullEn = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];
const _gMonthsUr = [
  'جنوری', 'فروری', 'مارچ', 'اپریل', 'مئی', 'جون',
  'جولائی', 'اگست', 'ستمبر', 'اکتوبر', 'نومبر', 'دسمبر',
];
const _wdEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _wdFullEn = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
];
const _wdUr = ['پیر', 'منگل', 'بدھ', 'جمعرات', 'جمعہ', 'ہفتہ', 'اتوار'];

String gregMonthName(int m, bool ur, {bool full = false}) =>
    ur ? _gMonthsUr[m - 1] : (full ? _gMonthsFullEn : _gMonthsEn)[m - 1];

String hijriMonthName(int m, bool ur) =>
    (ur ? hijriMonthsUr : hijriMonthsEn)[m - 1];

/// [weekday] is DateTime.weekday (1 = Monday).
String weekdayName(int weekday, bool ur, {bool full = false}) =>
    ur ? _wdUr[weekday - 1] : (full ? _wdFullEn : _wdEn)[weekday - 1];

String fmtTime(int minutes) {
  final m = minutes % 1440;
  final h = m ~/ 60, mm = m % 60;
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:${mm.toString().padLeft(2, '0')} ${h < 12 ? 'AM' : 'PM'}';
}

String fmtTimeRange(Event e) => '${fmtTime(e.startMin)} – ${fmtTime(e.endMin)}';

String fmtHijri(HDate h, bool ur) => ur
    ? '${h.d} ${hijriMonthName(h.m, true)} ${h.y}ھ'
    : '${h.d} ${hijriMonthName(h.m, false)} ${h.y}';

String fmtGreg(DateTime d, bool ur, {bool weekday = true}) {
  final s = '${d.day} ${gregMonthName(d.month, ur)} ${d.year}';
  return weekday ? '${weekdayName(d.weekday, ur)}, $s' : s;
}

/// "Majlis — topic", or just the type when there is no topic.
String eventTitle(Event e, bool ur) {
  final base = typeLabel(e.type, ur);
  return e.topic.isEmpty ? base : '$base — ${e.topic}';
}

String seriesBadge(Event e, bool ur) {
  if (e.seriesTotal == null || e.seriesTotal! <= 1) return '';
  final name = seriesLabel(e.seriesTotal!, ur).split(' (').first;
  return '$name — ${trL(ur, 'series_day')} ${e.seriesIndex}/${e.seriesTotal}';
}
