import 'package:flutter/material.dart';

import '../core/strings.dart';
import '../data/models.dart';
import '../data/store.dart';
import '../services/native.dart';

/// Bottom sheet to pick an existing host or create a new one.
Future<Host?> pickHost(BuildContext context) => showModalBottomSheet<Host>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _HostPickerSheet(),
    );

class _HostPickerSheet extends StatefulWidget {
  const _HostPickerSheet();

  @override
  State<_HostPickerSheet> createState() => _HostPickerSheetState();
}

class _HostPickerSheetState extends State<_HostPickerSheet> {
  String q = '';

  @override
  Widget build(BuildContext context) {
    final query = q.trim().toLowerCase();
    final digits = normalizePhone(q);
    final list = store.hosts
        .where((h) =>
            query.isEmpty ||
            h.name.toLowerCase().contains(query) ||
            (digits.isNotEmpty && h.phone.contains(digits)))
        .toList();
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  autofocus: store.hosts.isNotEmpty,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: '${tr(context, 'host_name')} / ${tr(context, 'phone')}',
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => q = v),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                icon: const Icon(Icons.person_add_alt),
                label: Text(tr(context, 'new_host')),
                onPressed: () async {
                  final h = await showHostDialog(context);
                  if (h != null && context.mounted) Navigator.pop(context, h);
                },
              ),
            ]),
          ),
          Expanded(
            child: list.isEmpty
                ? Center(child: Text(tr(context, 'no_hosts')))
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final h = list[i];
                      return ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.person)),
                        title: Text(h.name),
                        subtitle: Text([h.phone, if (h.venue.isNotEmpty) h.venue]
                            .join(' · ')),
                        onTap: () => Navigator.pop(context, h),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}

/// Create (no [editing]) or edit a host. Phone numbers are unique: creating
/// with a known number offers the existing host instead.
Future<Host?> showHostDialog(BuildContext context, {Host? editing}) =>
    showDialog<Host>(
        context: context, builder: (_) => _HostDialog(editing: editing));

class _HostDialog extends StatefulWidget {
  final Host? editing;
  const _HostDialog({this.editing});

  @override
  State<_HostDialog> createState() => _HostDialogState();
}

class _HostDialogState extends State<_HostDialog> {
  final _form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.editing?.name);
  late final phone = TextEditingController(text: widget.editing?.phone);
  late final venue = TextEditingController(text: widget.editing?.venue);

  /// Numbers of the imported contact, default/latest first.
  List<String> numbers = [];
  bool imported = false;
  String? importError;

  Future<void> _import() async {
    final PickedContact? c;
    try {
      c = await NativeBridge.pickContact();
    } on ContactsDenied {
      setState(() => importError = tr(context, 'contacts_denied'));
      return;
    }
    if (c == null || !mounted) return;
    // The same number saved twice in a contact shows once.
    final seen = <String>{};
    final nums = [
      for (final n in c.phones)
        if (seen.add(normalizePhone(n))) n.trim()
    ];
    setState(() {
      importError = nums.isEmpty ? tr(context, 'contact_no_phone') : null;
      if (c!.name.isNotEmpty) name.text = c.name;
      if (nums.isNotEmpty) phone.text = nums.first;
      numbers = nums;
      imported = true;
    });
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final norm = normalizePhone(phone.text);
    final clash = store.hostByPhone(norm);
    if (clash != null && clash.id != widget.editing?.id) {
      if (widget.editing != null) {
        await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(tr(c, 'phone_exists_title')),
            content: Text('${tr(c, 'phone_exists_edit')}\n${clash.name}'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(c), child: Text(tr(c, 'ok'))),
            ],
          ),
        );
        return;
      }
      final use = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(tr(c, 'phone_exists_title')),
          content: Text(
              '${tr(c, 'phone_exists_use')}\n\n${clash.name}\n${clash.phone}'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: Text(tr(c, 'cancel'))),
            FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: Text(tr(c, 'use_existing'))),
          ],
        ),
      );
      if (use == true && mounted) Navigator.pop(context, clash);
      return;
    }
    final h = Host(
      id: widget.editing?.id,
      name: name.text.trim(),
      phone: norm,
      venue: venue.text.trim(),
    );
    await store.saveHost(h);
    if (mounted) Navigator.pop(context, h);
  }

  @override
  Widget build(BuildContext context) {
    String? req(String? v) =>
        (v == null || v.trim().isEmpty) ? tr(context, 'required') : null;
    return AlertDialog(
      title: Text(tr(context, widget.editing == null ? 'new_host' : 'edit_host')),
      content: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            imported
                ? OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48)),
                    icon: const Icon(Icons.check, color: Color(0xFF1B5E20)),
                    label: Text(tr(context, 'imported_pick_another')),
                    onPressed: _import,
                  )
                : FilledButton.icon(
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48)),
                    icon: const Icon(Icons.contacts_outlined),
                    label: Text(tr(context, 'import_contacts')),
                    onPressed: _import,
                  ),
            if (importError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(importError!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(tr(context, 'or_type'),
                      style: Theme.of(context).textTheme.labelSmall),
                ),
                const Expanded(child: Divider()),
              ]),
            ),
            TextFormField(
              controller: name,
              decoration: InputDecoration(labelText: tr(context, 'host_name')),
              validator: req,
              textCapitalization: TextCapitalization.words,
            ),
            TextFormField(
              controller: phone,
              decoration: InputDecoration(labelText: tr(context, 'phone')),
              keyboardType: TextInputType.phone,
              validator: (v) {
                final d = (v ?? '').replaceAll(RegExp(r'[^0-9]'), '');
                return d.length < 7 ? tr(context, 'invalid_phone') : null;
              },
            ),
            if (numbers.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr(context, 'contact_numbers'),
                        style: Theme.of(context).textTheme.labelSmall),
                    const SizedBox(height: 6),
                    Wrap(spacing: 8, runSpacing: 6, children: [
                      for (final (i, n) in numbers.indexed)
                        ChoiceChip(
                          label: Text(i == 0
                              ? '$n · ${tr(context, 'latest')}'
                              : n),
                          selected:
                              normalizePhone(phone.text) == normalizePhone(n),
                          onSelected: (_) => setState(() => phone.text = n),
                        ),
                    ]),
                  ],
                ),
              ),
            TextFormField(
              controller: venue,
              decoration: InputDecoration(labelText: tr(context, 'saved_venue')),
              maxLines: 2,
              minLines: 1,
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr(context, 'cancel'))),
        FilledButton(onPressed: _save, child: Text(tr(context, 'save'))),
      ],
    );
  }
}
