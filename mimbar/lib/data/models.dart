import '../core/hijri.dart';

enum EventType { majlis, milad, nikkah }

enum EventStatus { tentative, confirmed, cancelled, done }

EventType _type(String s) => EventType.values.byName(s);
EventStatus _status(String s) => EventStatus.values.byName(s);

class Host {
  int? id;
  String name;

  /// Normalised phone number; unique across hosts.
  String phone;

  /// Saved default venue, pre-filled when this host is picked for an event.
  String venue;

  Host({this.id, required this.name, required this.phone, this.venue = ''});

  Map<String, Object?> toMap() =>
      {'id': id, 'name': name, 'phone': phone, 'venue': venue};

  factory Host.fromMap(Map<String, Object?> m) => Host(
        id: m['id'] as int?,
        name: m['name'] as String,
        phone: m['phone'] as String,
        venue: (m['venue'] as String?) ?? '',
      );
}

class Event {
  int? id;
  EventType type;
  HDate hijri;

  /// Manual per-event Gregorian date; when set it ignores the global offset.
  DateTime? gregOverride;

  /// Minutes from midnight. An end before the start means it runs past midnight.
  int startMin;
  int endMin;
  String venue;
  int? hostId;
  String topic;
  EventStatus status;

  String? seriesId;
  int? seriesIndex;
  int? seriesTotal;

  /// File name of the attached flier (Majlis and Milad only), or null.
  String? flier;

  Event({
    this.id,
    required this.type,
    required this.hijri,
    this.gregOverride,
    required this.startMin,
    required this.endMin,
    this.venue = '',
    this.hostId,
    this.topic = '',
    this.status = EventStatus.confirmed,
    this.seriesId,
    this.seriesIndex,
    this.seriesTotal,
    this.flier,
  });

  /// Length in minutes, handling events that run past midnight.
  int get durationMin {
    final d = (endMin - startMin) % 1440;
    return d == 0 ? 1440 : d;
  }

  bool get isActive =>
      status == EventStatus.tentative || status == EventStatus.confirmed;

  /// Fliers are offered for Majlis and Milad, never Nikkah.
  bool get takesFlier => type != EventType.nikkah;

  /// The flier to show or share, if this event type takes one.
  String? get shownFlier => takesFlier ? flier : null;

  Event copy() => Event.fromMap(toMap());

  Map<String, Object?> toMap() => {
        'id': id,
        'type': type.name,
        'h_year': hijri.y,
        'h_month': hijri.m,
        'h_day': hijri.d,
        'greg_override': gregOverride == null
            ? null
            : '${gregOverride!.year.toString().padLeft(4, '0')}-'
                '${gregOverride!.month.toString().padLeft(2, '0')}-'
                '${gregOverride!.day.toString().padLeft(2, '0')}',
        'start_min': startMin,
        'end_min': endMin,
        'venue': venue,
        'host_id': hostId,
        'topic': topic,
        'status': status.name,
        'series_id': seriesId,
        'series_index': seriesIndex,
        'series_total': seriesTotal,
        'flier': flier,
      };

  factory Event.fromMap(Map<String, Object?> m) {
    final go = m['greg_override'] as String?;
    String s(String k) => (m[k] as String?) ?? '';
    return Event(
      id: m['id'] as int?,
      type: _type(m['type'] as String),
      hijri: HDate(m['h_year'] as int, m['h_month'] as int, m['h_day'] as int),
      gregOverride: go == null ? null : DateTime.parse(go),
      startMin: m['start_min'] as int,
      endMin: m['end_min'] as int,
      venue: s('venue'),
      hostId: m['host_id'] as int?,
      topic: s('topic'),
      status: _status(m['status'] as String),
      seriesId: m['series_id'] as String?,
      seriesIndex: m['series_index'] as int?,
      seriesTotal: m['series_total'] as int?,
      flier: m['flier'] as String?,
    );
  }
}

class AppSettings {
  String lang;
  int offset;
  Map<EventType, int> durations;
  List<int> reminderLeads;

  AppSettings({
    required this.lang,
    required this.offset,
    required this.durations,
    required this.reminderLeads,
  });

  factory AppSettings.defaults() => AppSettings(
        lang: 'en',
        offset: 0,
        durations: {
          EventType.majlis: 90,
          EventType.milad: 90,
          EventType.nikkah: 60,
        },
        reminderLeads: [1440, 120],
      );

  AppSettings copy() => AppSettings.fromKv(toKv());

  Map<String, String> toKv() => {
        'lang': lang,
        'offset': '$offset',
        for (final t in EventType.values) 'dur_${t.name}': '${durations[t]}',
        'reminders': reminderLeads.join(','),
      };

  factory AppSettings.fromKv(Map<String, String> kv) {
    final d = AppSettings.defaults();
    int i(String k, int def) => int.tryParse(kv[k] ?? '') ?? def;
    final rem = kv['reminders'];
    return AppSettings(
      lang: kv['lang'] == 'ur' ? 'ur' : 'en',
      offset: i('offset', 0).clamp(-2, 2),
      durations: {
        for (final t in EventType.values)
          t: i('dur_${t.name}', d.durations[t]!),
      },
      reminderLeads: rem == null
          ? d.reminderLeads
          : (rem.split(',').map(int.tryParse).whereType<int>().toList()
            ..sort((a, b) => b.compareTo(a))),
    );
  }
}

/// Strips formatting and maps Pakistani international forms to local form,
/// so "+92 300-1234567", "0092 3001234567" and "0300 1234567" are equal.
String normalizePhone(String raw) {
  var digits = raw.replaceAll(RegExp(r'[^0-9+]'), '');
  final plus = digits.startsWith('+');
  digits = digits.replaceAll('+', '');
  if (digits.startsWith('0092')) return '0${digits.substring(4)}';
  if ((plus || digits.length == 12) && digits.startsWith('92')) {
    return '0${digits.substring(2)}';
  }
  return plus ? '+$digits' : digits;
}
