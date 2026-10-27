import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/strings.dart';
import '../data/models.dart';
import '../data/store.dart';
import '../services/backup.dart';
import '../services/sync.dart';
import 'hosts_screen.dart';

const durationOptions = [30, 45, 60, 75, 90, 105, 120, 150, 180, 240];
const leadOptions = [10080, 2880, 1440, 360, 180, 120, 60, 30];

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _update(void Function(AppSettings s) change) async {
    final s = store.settings.copy();
    change(s);
    await store.updateSettings(s);
  }

  Future<void> _pickDuration(BuildContext context, EventType t) async {
    final ur = isUr(context);
    final v = await showDialog<int>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text(typeLabel(t, ur)),
        children: [
          RadioGroup<int>(
            groupValue: store.settings.durations[t],
            onChanged: (v) => Navigator.pop(c, v),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final d in durationOptions)
                RadioListTile<int>(
                  value: d,
                  title: Text(durationLabel(d, ur)),
                ),
            ]),
          ),
        ],
      ),
    );
    if (v != null) await _update((s) => s.durations[t] = v);
  }

  Future<void> _pickLeads(BuildContext context) async {
    final ur = isUr(context);
    final chosen = {...store.settings.reminderLeads};
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(tr(c, 'reminders')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final l in leadOptions)
                CheckboxListTile(
                  value: chosen.contains(l),
                  title: Text('${leadLabel(l, ur)} ${tr(c, 'reminders_before')}'),
                  onChanged: (v) =>
                      set(() => v == true ? chosen.add(l) : chosen.remove(l)),
                ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: Text(tr(c, 'cancel'))),
            FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: Text(tr(c, 'save'))),
          ],
        ),
      ),
    );
    if (ok == true) {
      await _update((s) => s.reminderLeads = chosen.toList()
        ..sort((a, b) => b.compareTo(a)));
    }
  }

  Future<void> _export(BuildContext context) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.save_alt),
            title: Text(tr(c, 'save_to_phone')),
            onTap: () => Navigator.pop(c, 'save'),
          ),
          ListTile(
            leading: const Icon(Icons.share),
            title: Text(tr(c, 'share_file')),
            onTap: () => Navigator.pop(c, 'share'),
          ),
        ]),
      ),
    );
    if (choice == 'save') {
      final saved = await Backup.saveToPhone();
      if (saved && context.mounted) _toast(context, tr(context, 'export_ok'));
    } else if (choice == 'share') {
      await Backup.share();
    }
  }

  Future<void> _import(BuildContext context) async {
    final res = await Backup.pickAndImport(() async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(tr(c, 'import_q')),
          content: Text(tr(c, 'import_body')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: Text(tr(c, 'cancel'))),
            FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: Text(tr(c, 'import_backup'))),
          ],
        ),
      );
      return ok == true;
    });
    if (res == null || !context.mounted) return;
    _toast(context, tr(context, res ? 'import_ok' : 'import_bad'));
  }

  Future<void> _signIn(BuildContext context) async {
    final ok = await showDialog<bool>(
        context: context, builder: (_) => const _SignInDialog());
    if (ok == true && context.mounted) {
      _toast(context, sync.email ?? '');
    }
  }

  Future<void> _signOut(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr(c, 'sign_out_q')),
        content: Text(tr(c, 'sign_out_body')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(tr(c, 'cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(tr(c, 'sign_out'))),
        ],
      ),
    );
    if (ok == true) await sync.signOut();
  }

  String _syncLine(BuildContext context, bool ur) {
    if (sync.syncing) return tr(context, 'syncing');
    final t = sync.lastSynced;
    var line = tr(context, 'never_synced');
    if (t != null) {
      final now = DateTime.now();
      final today =
          t.year == now.year && t.month == now.month && t.day == now.day;
      final time = fmtTime(t.hour * 60 + t.minute);
      line = '${tr(context, 'synced_at')}: '
          '${today ? time : '${fmtGreg(t, ur, weekday: false)}, $time'}';
    }
    return sync.error == null ? line : '$line · ${tr(context, 'sync_waiting')}';
  }

  List<Widget> _syncTiles(BuildContext context, bool ur) {
    if (!sync.signedIn) {
      return [
        ListTile(
          leading: const Icon(Icons.cloud_off_outlined),
          title: Text(tr(context, 'sync_sign_in')),
          subtitle: Text(tr(context, 'sync_sign_in_sub')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _signIn(context),
        ),
      ];
    }
    return [
      ListTile(
        leading: Icon(sync.error == null
            ? Icons.cloud_done_outlined
            : Icons.cloud_queue_outlined),
        title: Text(sync.email ?? ''),
        subtitle: Text(_syncLine(context, ur)),
        trailing: sync.syncing
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))
            : IconButton(
                tooltip: tr(context, 'sync_now'),
                icon: const Icon(Icons.sync),
                onPressed: sync.syncNow,
              ),
      ),
      ListTile(
        leading: const Icon(Icons.logout),
        title: Text(tr(context, 'sign_out')),
        onTap: () => _signOut(context),
      ),
    ];
  }

  void _toast(BuildContext context, String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([store, sync]),
      builder: (context, _) {
        final ur = isUr(context);
        final s = store.settings;
        final theme = Theme.of(context);
        Widget header(String key) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
              child: Text(tr(context, key),
                  style: theme.textTheme.titleSmall!
                      .copyWith(color: theme.colorScheme.primary)),
            );

        return Scaffold(
          appBar: AppBar(title: Text(tr(context, 'settings'))),
          body: ListView(children: [
            header('language'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'en', label: Text('English')),
                  ButtonSegment(value: 'ur', label: Text('اردو')),
                ],
                selected: {s.lang},
                onSelectionChanged: (v) => _update((x) => x.lang = v.first),
              ),
            ),
            header('moon_offset'),
            ListTile(
              title: Text(tr(context, 'moon_offset_sub')),
              subtitle: Text(
                  '${tr(context, 'today_is')}: ${fmtHijri(store.todayHijri, ur)}'),
            ),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton.filledTonal(
                onPressed: s.offset > -2 ? () => _update((x) => x.offset--) : null,
                icon: const Icon(Icons.remove),
              ),
              SizedBox(
                width: 110,
                child: Text(
                  '${s.offset > 0 ? '+' : ''}${s.offset} ${tr(context, 'days')}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              IconButton.filledTonal(
                onPressed: s.offset < 2 ? () => _update((x) => x.offset++) : null,
                icon: const Icon(Icons.add),
              ),
            ]),
            header('default_durations'),
            for (final t in EventType.values)
              ListTile(
                leading: Icon(Icons.circle, size: 14, color: typeColor(t)),
                title: Text(typeLabel(t, ur)),
                trailing: Text(durationLabel(s.durations[t]!, ur)),
                onTap: () => _pickDuration(context, t),
              ),
            header('reminders'),
            ListTile(
              leading: const Icon(Icons.notifications_active_outlined),
              title: Text(s.reminderLeads.isEmpty
                  ? tr(context, 'reminders_none')
                  : s.reminderLeads
                      .map((l) => '${leadLabel(l, ur)} ${tr(context, 'reminders_before')}')
                      .join(' · ')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _pickLeads(context),
            ),
            header('hosts'),
            ListTile(
              leading: const Icon(Icons.people_outline),
              title: Text(tr(context, 'hosts')),
              trailing: Text('${store.hosts.length}'),
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const HostsScreen())),
            ),
            if (sync.configured) ...[
              header('cloud_sync'),
              ..._syncTiles(context, ur),
            ],
            header('backup'),
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: Text(tr(context, 'export_backup')),
              subtitle: Text(tr(context, 'export_sub')),
              onTap: () => _export(context),
            ),
            ListTile(
              leading: const Icon(Icons.restore),
              title: Text(tr(context, 'import_backup')),
              subtitle: Text(tr(context, 'import_sub')),
              onTap: () => _import(context),
            ),
            const SizedBox(height: 32),
          ]),
        );
      },
    );
  }
}

class _SignInDialog extends StatefulWidget {
  const _SignInDialog();

  @override
  State<_SignInDialog> createState() => _SignInDialogState();
}

class _SignInDialogState extends State<_SignInDialog> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool busy = false;
  String? error;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (email.text.trim().isEmpty || password.text.isEmpty) return;
    setState(() {
      busy = true;
      error = null;
    });
    final err = await sync.signIn(email.text, password.text);
    if (!mounted) return;
    if (err == null) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        busy = false;
        error = '${tr(context, 'sign_in_failed')}: $err';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr(context, 'cloud_sync')),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: email,
          enabled: !busy,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(labelText: tr(context, 'email')),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: password,
          enabled: !busy,
          obscureText: true,
          autofillHints: const [AutofillHints.password],
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(labelText: tr(context, 'password')),
          onSubmitted: (_) => _submit(),
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      ]),
      actions: [
        TextButton(
            onPressed: busy ? null : () => Navigator.pop(context, false),
            child: Text(tr(context, 'cancel'))),
        FilledButton(
          onPressed: busy ? null : _submit,
          child: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Text(tr(context, 'sign_in')),
        ),
      ],
    );
  }
}
