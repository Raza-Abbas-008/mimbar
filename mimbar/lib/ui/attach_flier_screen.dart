import 'dart:io';

import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/strings.dart';
import '../data/models.dart';
import '../data/store.dart';
import '../services/fliers.dart';

/// Opened when an image is shared into Mimbar (e.g. from WhatsApp): pick
/// the Majlis or Milad it belongs to. Upcoming events first, then recent
/// past ones.
class AttachFlierScreen extends StatelessWidget {
  final String imagePath;
  const AttachFlierScreen({super.key, required this.imagePath});

  Future<void> _attach(BuildContext context, Event e) async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    if (e.flier != null) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(tr(c, 'replace_flier_q')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: Text(tr(c, 'cancel'))),
            FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: Text(tr(c, 'replace'))),
          ],
        ),
      );
      if (ok != true) return;
    }
    final name = await Fliers.add(imagePath);
    await store.setFlier(e, name);
    final ur = store.ur;
    messenger.showSnackBar(SnackBar(
        content: Text('${trL(ur, 'flier_added')} · ${eventTitle(e, ur)}')));
    nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final ur = isUr(context);
    final theme = Theme.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final candidates = store.events.where((e) => e.takesFlier).toList();
    final upcoming =
        candidates.where((e) => !store.endOf(e).isBefore(today)).toList();
    final past = candidates
        .where((e) => store.endOf(e).isBefore(today))
        .toList()
        .reversed
        .take(30)
        .toList();

    Widget tile(Event e) {
      final host = store.hostOf(e);
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: Icon(Icons.circle, size: 14, color: typeColor(e.type)),
          title: Text(eventTitle(e, ur)),
          subtitle: Text([
            '${fmtHijri(e.hijri, ur)} · ${fmtGreg(store.gregOf(e), ur)}',
            [fmtTime(e.startMin), if (e.venue.isNotEmpty) e.venue, ?host?.name]
                .join(' · '),
          ].join('\n')),
          isThreeLine: true,
          trailing: e.flier == null
              ? const Icon(Icons.add_photo_alternate_outlined)
              : const Icon(Icons.image_outlined),
          onTap: () => _attach(context, e),
        ),
      );
    }

    Widget header(String key) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
          child: Text(tr(context, key), style: theme.textTheme.titleSmall),
        );

    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'attach_flier_to'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        children: [
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(File(imagePath),
                  height: 180, fit: BoxFit.contain, cacheHeight: 540),
            ),
          ),
          if (candidates.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(tr(context, 'no_flier_events'),
                  textAlign: TextAlign.center),
            ),
          if (upcoming.isNotEmpty) ...[
            header('upcoming_events'),
            ...upcoming.map(tile),
          ],
          if (past.isNotEmpty) ...[
            header('past_events'),
            ...past.map(tile),
          ],
        ],
      ),
    );
  }
}
