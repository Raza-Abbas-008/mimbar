import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/strings.dart';
import '../data/models.dart';
import '../data/store.dart';
import 'host_actions.dart';
import 'host_picker.dart';
import 'widgets/event_card.dart';

/// Asks before deleting hosts; their events keep everything but the host.
Future<bool> confirmDeleteHosts(BuildContext context, int count) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(tr(c, count == 1 ? 'delete_host_q' : 'delete_hosts_q')),
      content: Text(tr(c, 'delete_hosts_body')),
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
  return ok == true;
}

/// The host directory. Long-press starts Gmail-style multi-select.
class HostsScreen extends StatefulWidget {
  const HostsScreen({super.key});

  @override
  State<HostsScreen> createState() => _HostsScreenState();
}

class _HostsScreenState extends State<HostsScreen> {
  final selected = <int>{};

  void _toggle(int id) {
    HapticFeedback.selectionClick();
    setState(() => selected.contains(id) ? selected.remove(id) : selected.add(id));
  }

  Future<void> _delete() async {
    if (!await confirmDeleteHosts(context, selected.length)) return;
    await store.deleteHosts(selected.toList());
    setState(selected.clear);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final theme = Theme.of(context);
          // Hosts deleted elsewhere (e.g. by sync) drop out of the selection.
          selected.removeWhere((id) => store.hosts.every((h) => h.id != id));
          final selecting = selected.isNotEmpty;
          final one = selected.length == 1
              ? store.hosts.firstWhere((h) => h.id == selected.first)
              : null;
          IconButton act(IconData icon, String key, VoidCallback onTap) =>
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: tr(context, key),
                icon: Icon(icon),
                onPressed: onTap,
              );
          return PopScope(
            canPop: !selecting,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) setState(selected.clear);
            },
            child: Scaffold(
              appBar: selecting
                  ? AppBar(
                      leading: IconButton(
                        tooltip: tr(context, 'cancel'),
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(selected.clear),
                      ),
                      title: Text('${selected.length} ${tr(context, 'selected')}'),
                      actions: [
                        // With one host: reach them straight from here.
                        if (one != null) ...[
                          act(Icons.copy_outlined, 'copy_number',
                              () => copyHostNumber(context, one)),
                          act(Icons.call_outlined, 'call',
                              () => callHost(context, one)),
                          act(Icons.chat_outlined, 'whatsapp',
                              () => whatsappHost(context, one)),
                        ],
                        act(Icons.select_all, 'select_all', () => setState(() =>
                            selected.addAll([for (final h in store.hosts) h.id!]))),
                        act(Icons.delete_outline, 'delete', _delete),
                      ],
                    )
                  : AppBar(title: Text(tr(context, 'hosts'))),
              floatingActionButton: selecting
                  ? null
                  : FloatingActionButton(
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
                        final on = selected.contains(h.id);
                        return ListTile(
                          selected: on,
                          selectedTileColor: const Color(0xFFE8E8ED),
                          selectedColor: theme.colorScheme.onSurface,
                          leading: CircleAvatar(
                            backgroundColor:
                                on ? theme.colorScheme.primary : null,
                            foregroundColor:
                                on ? theme.colorScheme.onPrimary : null,
                            child: Icon(on ? Icons.check : Icons.person),
                          ),
                          title: Text(h.name),
                          subtitle: Text([h.phone, if (h.venue.isNotEmpty) h.venue]
                              .join(' · ')),
                          trailing: Text('$n ${tr(context, 'events_count')}'),
                          onLongPress: () => _toggle(h.id!),
                          onTap: selecting
                              ? () => _toggle(h.id!)
                              : () => Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) => HostDetailScreen(hostId: h.id!))),
                        );
                      },
                    ),
            ),
          );
        },
      );
}

class HostDetailScreen extends StatelessWidget {
  final int hostId;
  const HostDetailScreen({super.key, required this.hostId});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final host =
              store.hosts.where((h) => h.id == hostId).firstOrNull;
          // Deleted (here or on the other phone): nothing left to show.
          if (host == null) return const Scaffold();
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
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: tr(context, 'delete_host'),
                  onPressed: () async {
                    final nav = Navigator.of(context);
                    if (!await confirmDeleteHosts(context, 1)) return;
                    await store.deleteHosts([hostId]);
                    nav.pop();
                  },
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
                  onLongPress: () => copyHostNumber(context, host),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      tooltip: tr(context, 'copy_number'),
                      icon: const Icon(Icons.copy_outlined),
                      onPressed: () => copyHostNumber(context, host),
                    ),
                    IconButton(
                      tooltip: tr(context, 'call'),
                      icon: const Icon(Icons.call_outlined),
                      onPressed: () => callHost(context, host),
                    ),
                    IconButton(
                      tooltip: tr(context, 'whatsapp'),
                      icon: const Icon(Icons.chat_outlined),
                      onPressed: () => whatsappHost(context, host),
                    ),
                  ]),
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
