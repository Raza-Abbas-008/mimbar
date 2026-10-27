import '../data/models.dart';

/// What a calendar day shows: event counts per type, in the fixed order
/// Majlis, Milad, Nikkah. One type → a wide bar; several → one dot each.
/// A count is drawn only when it is above 1.
class DayMarks {
  final Map<EventType, int> counts;
  final bool clash;
  const DayMarks(this.counts, {this.clash = false});

  bool get isBar => counts.length == 1;
}

/// Marks for one day's events. Cancelled events are not counted; returns
/// null when nothing is left to show.
DayMarks? marksFor(Iterable<Event> events, bool Function(Event) isClashing) {
  final n = <EventType, int>{};
  var clash = false;
  for (final e in events) {
    if (e.status == EventStatus.cancelled) continue;
    n[e.type] = (n[e.type] ?? 0) + 1;
    clash |= isClashing(e);
  }
  if (n.isEmpty) return null;
  return DayMarks({
    for (final t in EventType.values)
      if (n[t] != null) t: n[t]!,
  }, clash: clash);
}
