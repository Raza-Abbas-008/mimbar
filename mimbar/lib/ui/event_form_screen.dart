import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/format.dart';
import '../core/hijri.dart';
import '../core/strings.dart';
import '../data/models.dart';
import '../data/store.dart';
import 'flier_screen.dart';
import 'hijri_picker.dart';
import 'host_picker.dart';
import 'share_sheet.dart';

const seriesOptions = [1, 3, 5, 10];

class EventFormScreen extends StatefulWidget {
  final Event? existing;
  final HDate? initialDate;
  const EventFormScreen({super.key, this.existing, this.initialDate});

  @override
  State<EventFormScreen> createState() => _EventFormScreenState();
}

class _EventFormScreenState extends State<EventFormScreen> {
  final _form = GlobalKey<FormState>();
  late Event e;
  Host? host;
  int seriesLen = 1;

  late final venue = TextEditingController(text: e.venue);
  late final topic = TextEditingController(text: e.topic);

  bool get isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      e = widget.existing!.copy();
      host = store.hostOf(e);
    } else {
      const start = 20 * 60;
      e = Event(
        type: EventType.majlis,
        hijri: widget.initialDate ?? store.todayHijri,
        startMin: start,
        endMin: start + store.settings.durations[EventType.majlis]!,
      );
    }
  }

  void _setType(EventType t) => setState(() {
        HapticFeedback.selectionClick();
        e.type = t;
        e.endMin = (e.startMin + store.settings.durations[t]!) % 1440;
        if (t != EventType.majlis) seriesLen = 1;
      });

  Future<void> _pickDate() async {
    final h = await pickHijriDate(context, e.hijri);
    if (h != null) setState(() => e.hijri = h);
  }

  Future<void> _toggleOverride(bool on) async {
    if (!on) return setState(() => e.gregOverride = null);
    final g = await showDatePicker(
      context: context,
      initialDate: store.gregOf(e),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (g != null) setState(() => e.gregOverride = dateOnly(g));
  }

  Future<void> _pickTime(bool start) async {
    final cur = start ? e.startMin : e.endMin;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: cur ~/ 60, minute: cur % 60),
      // Always the 12-hour dial with AM/PM, even when the phone's clock is
      // set to 24-hour time.
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: false),
        child: child!,
      ),
    );
    if (t == null) return;
    setState(() {
      final m = t.hour * 60 + t.minute;
      if (start) {
        final dur = e.durationMin;
        e.startMin = m;
        e.endMin = (m + dur) % 1440;
      } else {
        e.endMin = m;
      }
    });
  }

  Future<void> _pickHost() async {
    final h = await pickHost(context);
    if (h == null) return;
    setState(() {
      // Don't overwrite a venue the user typed themselves.
      final typed = venue.text.trim();
      if (typed.isEmpty || typed == host?.venue) venue.text = h.venue;
      host = h;
    });
  }

  /// A saved event's flier changes at once (like the viewer's Replace and
  /// Remove); a new event's is kept with the form until Save.
  Future<void> _setFlier(String? name) async {
    if (!isNew) await store.setFlier(widget.existing!, name);
    if (mounted) setState(() => e.flier = name);
  }

  Future<void> _addFlier() async {
    final name = await pickFlier();
    if (name != null) await _setFlier(name);
  }

  void _viewFlier() => Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FlierScreen(name: e.flier!, onChanged: _setFlier)));

  void _collect() {
    e
      ..hostId = host?.id
      ..venue = venue.text.trim()
      ..topic = topic.text.trim();
  }

  List<Event> _buildEvents() {
    if (seriesLen <= 1) return [e];
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    return [
      for (var i = 0; i < seriesLen; i++)
        e.copy()
          ..hijri = e.hijri.addDays(i)
          ..gregOverride = null
          ..seriesId = id
          ..seriesIndex = i + 1
          ..seriesTotal = seriesLen,
    ];
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    _collect();
    final list = _buildEvents();
    final hits = store.findClashes(list, ignoreId: e.id);
    if (hits.isNotEmpty) {
      HapticFeedback.heavyImpact();
      if (!await _confirmClash(list, hits)) return;
    }
    await store.saveEvents(list);
    HapticFeedback.lightImpact();
    if (mounted) Navigator.pop(context);
  }

  Future<bool> _confirmClash(List<Event> list, Map<int, List<Event>> hits) async {
    final ur = isUr(context);
    final lines = <String>[];
    hits.forEach((i, others) {
      final c = list[i];
      final prefix = list.length > 1
          ? '${trL(ur, 'series_day')} ${i + 1} (${fmtHijri(c.hijri, ur)}): '
          : '';
      for (final o in others) {
        final h = store.hostOf(o);
        lines.add('$prefix${typeLabel(o.type, ur)}'
            '${h == null ? '' : ' (${h.name})'} · '
            '${fmtGreg(store.gregOf(o), ur, weekday: false)} · ${fmtTimeRange(o)}');
      }
    });
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: Color(0xFFB28704)),
        title: Text(tr(c, 'clash_title')),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(tr(c, 'clash_body')),
              const SizedBox(height: 8),
              for (final l in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('• $l'),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(tr(c, 'go_back'))),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: clashColor, foregroundColor: Colors.black),
              onPressed: () => Navigator.pop(c, true),
              child: Text(tr(c, 'save_anyway'))),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr(c, 'delete_q')),
        content: Text(tr(c, 'delete_body')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(tr(c, 'cancel'))),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(c, true),
              child: Text(tr(c, 'delete'))),
        ],
      ),
    );
    if (ok != true) return;
    await store.deleteEvent(widget.existing!);
    if (mounted) Navigator.pop(context);
  }

  void _share() {
    final saved = store.eventById(widget.existing!.id!) ?? widget.existing!;
    showEventShare(context, saved);
  }

  @override
  Widget build(BuildContext context) {
    final ur = isUr(context);
    final theme = Theme.of(context);
    String? req(String? v) =>
        (v == null || v.trim().isEmpty) ? tr(context, 'required') : null;

    Widget field(TextEditingController c, String key,
            {bool required = false, int maxLines = 1}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextFormField(
            controller: c,
            minLines: 1,
            maxLines: maxLines,
            validator: required ? req : null,
            decoration: InputDecoration(
              labelText: tr(context, key) + (required ? ' *' : ''),
            ),
          ),
        );

    Widget section(String key) => Padding(
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 6),
          child: Text(tr(context, key),
              style: theme.textTheme.titleSmall!
                  .copyWith(color: theme.colorScheme.primary)),
        );

    final greg = store.gregOf(e);
    final seriesEnd = seriesLen > 1 ? e.hijri.addDays(seriesLen - 1) : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, isNew ? 'new_event' : 'edit_event')),
        actions: [
          if (!isNew) ...[
            IconButton(
              tooltip: tr(context, 'share'),
              icon: const Icon(Icons.share),
              onPressed: _share,
            ),
            IconButton(
              tooltip: tr(context, 'delete'),
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
          ],
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          children: [
            if (e.takesFlier) ...[
              e.flier == null
                  ? OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        foregroundColor: theme.colorScheme.onSurface,
                        side: const BorderSide(color: Color(0x668E8E93)),
                      ),
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: Text(tr(context, 'add_flier')),
                      onPressed: _addFlier,
                    )
                  : FilledButton.icon(
                      style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48)),
                      icon: const Icon(Icons.image_outlined),
                      label: Text(tr(context, 'view_flier')),
                      onPressed: _viewFlier,
                    ),
              const SizedBox(height: 12),
            ],
            SegmentedButton<EventType>(
              showSelectedIcon: false,
              segments: [
                for (final t in EventType.values)
                  ButtonSegment(
                    value: t,
                    label: Text(typeLabel(t, ur)),
                    icon: Icon(Icons.circle, size: 12, color: typeColor(t)),
                  ),
              ],
              selected: {e.type},
              onSelectionChanged: (s) => _setType(s.first),
            ),
            if (isNew && e.type == EventType.majlis) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: seriesLen,
                decoration: InputDecoration(
                  labelText: tr(context, 'series'),
                ),
                items: [
                  for (final n in seriesOptions)
                    DropdownMenuItem(value: n, child: Text(seriesLabel(n, ur))),
                ],
                onChanged: (v) => setState(() {
                  seriesLen = v ?? 1;
                  if (seriesLen > 1) e.gregOverride = null;
                }),
              ),
            ],
            section('date'),
            Card(
              margin: EdgeInsets.zero,
              child: Column(children: [
                ListTile(
                  leading: const Icon(Icons.calendar_month),
                  title: Text(
                    seriesEnd == null
                        ? fmtHijri(e.hijri, ur)
                        : '${fmtHijri(e.hijri, ur)} → ${fmtHijri(seriesEnd, ur)}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    seriesEnd == null
                        ? fmtGreg(greg, ur) +
                            (e.gregOverride != null
                                ? ' (${tr(context, 'adjusted')})'
                                : '')
                        : '${fmtGreg(greg, ur)} → '
                            '${fmtGreg(store.gregOfHijri(seriesEnd), ur)}',
                  ),
                  trailing: const Icon(Icons.edit),
                  onTap: _pickDate,
                ),
                if (seriesLen == 1)
                  SwitchListTile(
                    secondary: const Icon(Icons.edit_calendar),
                    title: Text(tr(context, 'adjust_greg')),
                    value: e.gregOverride != null,
                    onChanged: _toggleOverride,
                  ),
              ]),
            ),
            section('time'),
            Row(children: [
              Expanded(
                child: _TimeTile(
                  label: tr(context, 'start_time'),
                  value: fmtTime(e.startMin),
                  onTap: () => _pickTime(true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _TimeTile(
                  label: tr(context, 'end_time'),
                  value: fmtTime(e.endMin),
                  onTap: () => _pickTime(false),
                ),
              ),
            ]),
            section('host_optional'),
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(host?.name ?? tr(context, 'select_host')),
                subtitle: host == null ? null : Text(host!.phone),
                trailing: host == null
                    ? const Icon(Icons.chevron_right)
                    : IconButton(
                        tooltip: tr(context, 'remove_host'),
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => host = null),
                      ),
                onTap: _pickHost,
              ),
            ),
            const SizedBox(height: 12),
            field(venue, 'venue', required: true, maxLines: 3),
            field(topic, 'topic', maxLines: 2),
            DropdownButtonFormField<EventStatus>(
              initialValue: e.status,
              decoration: InputDecoration(
                labelText: tr(context, 'status'),
              ),
              items: [
                for (final s in EventStatus.values)
                  DropdownMenuItem(value: s, child: Text(statusLabel(s, ur))),
              ],
              onChanged: (v) => setState(() => e.status = v ?? e.status),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            icon: const Icon(Icons.check),
            label: Text(tr(context, 'save')),
            onPressed: _save,
          ),
        ),
      ),
    );
  }
}

class _TimeTile extends StatelessWidget {
  final String label, value;
  final VoidCallback onTap;
  const _TimeTile({required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 4),
              Text(value,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium!
                      .copyWith(fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      );
}

/// Formatted plain-text summary for WhatsApp / SMS.
String shareText(Event e, bool ur) {
  final host = store.hostOf(e);
  String l(String key) => trL(ur, key);
  return [
    '*${eventTitle(e, ur)}*',
    '${l('date')}: ${fmtHijri(e.hijri, ur)} (${fmtGreg(store.gregOf(e), ur)})',
    '${l('time')}: ${fmtTimeRange(e)}',
    if (e.venue.isNotEmpty) '${l('venue')}: ${e.venue}',
    if (host != null) '${l('host')}: ${host.name} (${host.phone})',
    if (seriesBadge(e, ur).isNotEmpty) seriesBadge(e, ur),
  ].join('\n');
}
