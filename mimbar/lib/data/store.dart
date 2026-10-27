import 'package:flutter/foundation.dart';

import '../core/format.dart';
import '../core/hijri.dart';
import '../core/strings.dart';
import '../services/notifications.dart';
import '../services/sync.dart';
import 'db.dart';
import 'models.dart';

final store = AppStore();

/// Single source of app state. Every mutation goes through here, then the
/// derived data (sort order, clashes, auto-Done, reminders) is refreshed.
class AppStore extends ChangeNotifier {
  final db = AppDb();

  AppSettings settings = AppSettings.defaults();
  List<Host> hosts = [];
  Map<int, Host> _hostById = {};

  /// All events sorted by start time.
  List<Event> events = [];

  /// Event id -> ids of the non-cancelled events it overlaps.
  Map<int, Set<int>> clashes = {};

  late HDate todayHijri;

  bool get ur => settings.lang == 'ur';

  /// Whether the Calendar tab shows the month grid. Kept per phone, not
  /// synced.
  bool calendarOn = true;

  Future<void> init() async {
    await db.open();
    calendarOn = await db.getMeta('calendar_on') != '0';
    await _reload();
  }

  Future<void> setCalendarOn(bool on) async {
    calendarOn = on;
    notifyListeners();
    await db.setMeta('calendar_on', on ? '1' : '0');
  }

  Future<void> _reload() async {
    settings = AppSettings.fromKv(await db.loadSettings());
    hosts = await db.loadHosts();
    events = await db.loadEvents();
    await _refreshDerived();
  }

  Future<void> _refreshDerived() async {
    _hostById = {for (final h in hosts) h.id!: h};
    todayHijri = hijriOfGreg(DateTime.now());
    await _autoDone();
    events.sort((a, b) => startOf(a).compareTo(startOf(b)));
    _computeClashes();
    notifyListeners();
    rescheduleReminders();
  }

  // ---------------------------------------------------------------- dates

  /// Gregorian date of a Hijri date with the global moon-sighting offset.
  DateTime gregOfHijri(HDate h) =>
      addDaysTo(h.toGregorianRaw(), settings.offset);

  /// Hijri date that falls on a Gregorian date, with the offset applied.
  HDate hijriOfGreg(DateTime g) =>
      HDate.fromGregorianRaw(addDaysTo(dateOnly(g), -settings.offset));

  DateTime gregOf(Event e) => e.gregOverride ?? gregOfHijri(e.hijri);

  DateTime startOf(Event e) {
    final g = gregOf(e);
    return DateTime(g.year, g.month, g.day, 0, e.startMin);
  }

  DateTime endOf(Event e) => startOf(e).add(Duration(minutes: e.durationMin));

  /// Re-evaluates "today" (called on resume and at midnight).
  Future<void> refreshDay() async {
    final t = hijriOfGreg(DateTime.now());
    if (t == todayHijri) return;
    await _refreshDerived();
  }

  /// Tentative/Confirmed events whose Hijri date has passed become Done.
  Future<void> _autoDone() async {
    final due = events
        .where((e) => e.isActive && e.hijri.compareTo(todayHijri) < 0)
        .toList();
    if (due.isEmpty) return;
    await db.markDone([for (final e in due) e.id!]);
    for (final e in due) {
      e.status = EventStatus.done;
    }
    sync.request();
  }

  // -------------------------------------------------------------- clashes

  bool _overlaps(Event a, Event b) =>
      startOf(a).isBefore(endOf(b)) && startOf(b).isBefore(endOf(a));

  void _computeClashes() {
    clashes = {};
    final active =
        events.where((e) => e.status != EventStatus.cancelled).toList();
    for (var i = 0; i < active.length; i++) {
      final a = active[i];
      final aEnd = endOf(a);
      for (var j = i + 1; j < active.length; j++) {
        final b = active[j];
        if (!startOf(b).isBefore(aEnd)) break;
        clashes.putIfAbsent(a.id!, () => {}).add(b.id!);
        clashes.putIfAbsent(b.id!, () => {}).add(a.id!);
      }
    }
  }

  bool isClashing(Event e) => e.id != null && (clashes[e.id]?.isNotEmpty ?? false);

  /// For each candidate (by index), the saved events it would clash with.
  Map<int, List<Event>> findClashes(List<Event> candidates,
      {int? ignoreId}) {
    final out = <int, List<Event>>{};
    for (var i = 0; i < candidates.length; i++) {
      final c = candidates[i];
      if (c.status == EventStatus.cancelled) continue;
      final hits = events
          .where((e) =>
              e.id != ignoreId &&
              e.status != EventStatus.cancelled &&
              _overlaps(c, e))
          .toList();
      if (hits.isNotEmpty) out[i] = hits;
    }
    return out;
  }

  /// Splits a sorted list into display groups: single events, or clusters of
  /// events that clash with each other (shown as "A + B (Clashing)").
  List<List<Event>> groupForDisplay(List<Event> list) {
    final byId = {for (final e in list) e.id!: e};
    final seen = <int>{};
    final out = <List<Event>>[];
    for (final e in list) {
      if (!seen.add(e.id!)) continue;
      final group = <Event>[];
      final stack = [e];
      while (stack.isNotEmpty) {
        final x = stack.removeLast();
        group.add(x);
        for (final y in clashes[x.id] ?? const <int>{}) {
          if (byId.containsKey(y) && seen.add(y)) stack.add(byId[y]!);
        }
      }
      group.sort((a, b) => startOf(a).compareTo(startOf(b)));
      out.add(group);
    }
    return out;
  }

  // ---------------------------------------------------------------- CRUD

  Host? hostOf(Event e) => e.hostId == null ? null : _hostById[e.hostId];

  Host? hostByPhone(String normalized) {
    for (final h in hosts) {
      if (h.phone == normalized) return h;
    }
    return null;
  }

  Event? eventById(int id) {
    for (final e in events) {
      if (e.id == id) return e;
    }
    return null;
  }

  List<Event> eventsOfHost(int hostId) =>
      events.where((e) => e.hostId == hostId).toList();

  Future<Host> saveHost(Host h) async {
    h.id = await db.saveHost(h);
    hosts = await db.loadHosts();
    await _refreshDerived();
    sync.request();
    return h;
  }

  Future<void> saveEvents(List<Event> list) async {
    await db.saveEvents(list);
    events = await db.loadEvents();
    await _refreshDerived();
    sync.request();
  }

  /// Attaches, replaces or (with null) removes a saved event's flier.
  Future<void> setFlier(Event e, String? name) async {
    await db.setFlier(e.id!, name);
    events = await db.loadEvents();
    await _refreshDerived();
    sync.request();
  }

  Future<void> deleteEvent(Event e) async {
    await db.deleteEvent(e.id!);
    events = await db.loadEvents();
    await _refreshDerived();
    sync.request();
  }

  Future<void> updateSettings(AppSettings s) async {
    await db.saveSettings(s.toKv());
    settings = s;
    await _refreshDerived();
    sync.request();
  }

  /// Called after a backup import or a sync has changed the database.
  Future<void> reloadAll() => _reload();

  // ------------------------------------------------------------ reminders

  Future<void> rescheduleReminders() async {
    final now = DateTime.now();
    final items = <Reminder>[];
    var count = 0;
    for (final e in events) {
      if (!e.isActive || !startOf(e).isAfter(now)) continue;
      // Android caps pending alarms (~500); the next 60 events is plenty.
      if (++count > 60) break;
      final host = hostOf(e);
      for (var i = 0; i < settings.reminderLeads.length; i++) {
        final lead = settings.reminderLeads[i];
        final when = startOf(e).subtract(Duration(minutes: lead));
        if (!when.isAfter(now)) continue;
        items.add(Reminder(
          id: e.id! * 10 + i,
          eventId: e.id!,
          when: when,
          title: '${typeLabel(e.type, ur)} · ${leadLabel(lead, ur)}',
          body: [
            '${fmtTime(e.startMin)} · ${fmtHijri(e.hijri, ur)}',
            if (e.venue.isNotEmpty) e.venue,
            if (host != null) host.name,
          ].join('\n'),
        ));
      }
    }
    await Notifs.reschedule(items);
  }
}
