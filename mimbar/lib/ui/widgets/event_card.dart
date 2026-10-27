import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/strings.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../event_form_screen.dart';
import 'pressable.dart';

void openEvent(BuildContext context, Event e) => Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => EventFormScreen(existing: e)));

/// Renders one display group: a single event card, or a yellow-striped
/// "A + B (Clashing)" card holding every event in the clash.
class EventGroupCard extends StatelessWidget {
  final List<Event> group;
  const EventGroupCard(this.group, {super.key});

  @override
  Widget build(BuildContext context) {
    if (group.length == 1) {
      final e = group.first;
      return _Strip(
        color: store.isClashing(e) ? clashColor : typeColor(e.type),
        child: InkWell(
          onTap: () => openEvent(context, e),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: EventBody(e),
          ),
        ),
      );
    }

    final ur = isUr(context);
    final header = group.map((e) {
      final h = store.hostOf(e);
      return h == null ? typeLabel(e.type, ur) : '${typeLabel(e.type, ur)} (${h.name})';
    }).join(' + ');
    return _Strip(
      color: clashColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded,
                  size: 18, color: Color(0xFFB28704)),
              const SizedBox(width: 6),
              Expanded(
                child: Text('$header (${tr(context, 'clashing')})',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
          for (final e in group) ...[
            const Divider(height: 1),
            InkWell(
              onTap: () => openEvent(context, e),
              child: Container(
                margin: const EdgeInsetsDirectional.fromSTEB(8, 8, 8, 8),
                padding: const EdgeInsetsDirectional.only(start: 8),
                decoration: BoxDecoration(
                  border: BorderDirectional(
                      start: BorderSide(color: typeColor(e.type), width: 4)),
                ),
                child: EventBody(e),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Strip extends StatelessWidget {
  final Color color;
  final Widget child;
  const _Strip({required this.color, required this.child});

  @override
  Widget build(BuildContext context) => Pressable(
        child: Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(height: 6, color: color),
              child,
            ],
          ),
        ),
      );
}

class EventBody extends StatelessWidget {
  final Event e;
  const EventBody(this.e, {super.key});

  @override
  Widget build(BuildContext context) {
    final ur = isUr(context);
    final theme = Theme.of(context);
    final host = store.hostOf(e);
    final cancelled = e.status == EventStatus.cancelled;
    final muted = theme.colorScheme.onSurfaceVariant;
    final small = theme.textTheme.bodySmall!.copyWith(color: muted);
    final badge = seriesBadge(e, ur);
    final subtitle = e.topic;

    Widget line(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 14, color: muted),
            const SizedBox(width: 4),
            Expanded(child: Text(text, style: small)),
          ]),
        );

    return Opacity(
      opacity: cancelled ? 0.5 : 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Expanded(
              child: Text(
                typeLabel(e.type, ur),
                style: theme.textTheme.titleSmall!.copyWith(
                  fontWeight: FontWeight.w700,
                  decoration: cancelled ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            StatusChip(e.status),
          ]),
          if (subtitle.isNotEmpty)
            Text(subtitle,
                style: theme.textTheme.bodyMedium!.copyWith(
                    decoration: cancelled ? TextDecoration.lineThrough : null)),
          const SizedBox(height: 4),
          Text(fmtHijri(e.hijri, ur),
              style: theme.textTheme.bodyMedium!
                  .copyWith(fontWeight: FontWeight.w600)),
          Row(children: [
            Flexible(child: Text(fmtGreg(store.gregOf(e), ur), style: small)),
            if (e.gregOverride != null) ...[
              const SizedBox(width: 4),
              Icon(Icons.edit_calendar, size: 13, color: muted),
              Text(' ${tr(context, 'adjusted')}', style: small),
            ],
          ]),
          line(Icons.schedule, fmtTimeRange(e)),
          if (host != null) line(Icons.person_outline, host.name),
          if (e.venue.isNotEmpty) line(Icons.place_outlined, e.venue),
          if (badge.isNotEmpty) line(Icons.repeat, badge),
        ],
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  final EventStatus s;
  const StatusChip(this.s, {super.key});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (s) {
      EventStatus.tentative => (const Color(0xFFFFF3E0), const Color(0xFFE65100)),
      EventStatus.confirmed => (const Color(0xFFE8F5E9), const Color(0xFF1B5E20)),
      EventStatus.cancelled => (const Color(0xFFEEEEEE), const Color(0xFF616161)),
      EventStatus.done => (const Color(0xFFE3F2FD), const Color(0xFF0D47A1)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(statusLabel(s, isUr(context)),
          style: TextStyle(fontSize: 11, color: fg, fontWeight: FontWeight.w600)),
    );
  }
}
