import 'package:flutter/material.dart';

import '../core/strings.dart';
import '../data/models.dart';
import '../data/store.dart';
import 'host_picker.dart';
import 'widgets/event_card.dart';

class HostsScreen extends StatelessWidget {
  const HostsScreen({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) => Scaffold(
          appBar: AppBar(title: Text(tr(context, 'hosts'))),
          floatingActionButton: FloatingActionButton(
            onPressed: () => showHostDialog(context),
            child: const Icon(Icons.person_add_alt),
          ),
          body: store.hosts.isEmpty
              ? Center(child: Text(tr(context, 'no_hosts')))
              : ListView.builder(
                  itemCount: store.hosts.length,
                  itemBuilder: (_, i) {
                    final h = store.hosts[i];
                    final n = store.eventsOfHost(h.id!).length;
                    return ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: Text(h.name),
                      subtitle: Text(
                          [h.phone, if (h.venue.isNotEmpty) h.venue].join(' · ')),
                      trailing: Text('$n ${tr(context, 'events_count')}'),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => HostDetailScreen(hostId: h.id!))),
                    );
                  },
                ),
        ),
      );
}

class HostDetailScreen extends StatelessWidget {
  final int hostId;
  const HostDetailScreen({super.key, required this.hostId});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final host = store.hosts.firstWhere((h) => h.id == hostId);
          final now = DateTime.now();
          final all = store.eventsOfHost(hostId);
          final upcoming =
              all.where((e) => !store.endOf(e).isBefore(now)).toList();
          final past =
              all.where((e) => store.endOf(e).isBefore(now)).toList().reversed.toList();
          final theme = Theme.of(context);

          Widget heading(String key) => Padding(
                padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                child: Text(tr(context, key),
                    style: theme.textTheme.titleMedium!
                        .copyWith(fontWeight: FontWeight.w700)),
              );
          List<Widget> cards(List<Event> list) => [
                for (final e in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: EventGroupCard([e]),
                  ),
              ];

          return Scaffold(
            appBar: AppBar(
              title: Text(host.name),
              actions: [
                IconButton(
                  icon: const Icon(Icons.edit),
                  tooltip: tr(context, 'edit_host'),
                  onPressed: () => showHostDialog(context, editing: host),
                ),
              ],
            ),
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.phone),
                  title: Text(host.phone),
                ),
                if (host.venue.isNotEmpty)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.place_outlined),
                    title: Text(host.venue),
                  ),
                heading('upcoming'),
                if (upcoming.isEmpty) Text(tr(context, 'no_upcoming')),
                ...cards(upcoming),
                heading('past'),
                if (past.isEmpty) Text(tr(context, 'no_events')),
                ...cards(past),
              ],
            ),
          );
        },
      );
}
