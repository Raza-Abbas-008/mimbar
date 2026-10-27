import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../core/strings.dart';
import '../data/models.dart';
import '../main.dart' show fieldFill;
import '../services/native.dart';
import '../services/sync.dart';
import 'event_form_screen.dart' show shareText;

enum _What { text, flier, both }

enum _Target { facebook, whatsapp, more }

/// Share an event: choose Text / Flier / Both (the flier options only when
/// the event has one), then Facebook, WhatsApp or the Android share sheet.
Future<void> showEventShare(BuildContext context, Event e) async {
  final ur = isUr(context);
  final text = shareText(e, ur);
  final name = e.shownFlier;
  final image = name == null ? null : await sync.flierFile(name);
  if (!context.mounted) return;
  if (name != null && image == null) _toast(context, tr(context, 'flier_missing'));
  await _sheet(context, text: text, image: image);
}

/// Share just a flier image (from the flier viewer).
Future<void> showFlierShare(BuildContext context, File image) =>
    _sheet(context, image: image, choose: false);

Future<void> _sheet(BuildContext context,
    {String? text, File? image, bool choose = true}) async {
  final messenger = ScaffoldMessenger.of(context);
  var what = image == null
      ? _What.text
      : text == null
          ? _What.flier
          : _What.both;
  final picked = await showModalBottomSheet<(_What, _Target)>(
    context: context,
    builder: (c) => StatefulBuilder(builder: (c, set) {
      final theme = Theme.of(c);
      final withText = what != _What.flier;
      final withImage = what != _What.text;
      Widget target(_Target t, String label, IconData icon, Color bg) =>
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: bg,
                  foregroundColor: bg == Colors.white ? Colors.black : Colors.white,
                  side: bg == Colors.white
                      ? const BorderSide(color: Color(0x33000000))
                      : null,
                  minimumSize: const Size.fromHeight(72),
                  padding: EdgeInsets.zero,
                ),
                onPressed: () => Navigator.pop(c, (what, t)),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, size: 22),
                  const SizedBox(height: 4),
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
            ),
          );
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(tr(c, 'share'), style: theme.textTheme.titleLarge),
              const SizedBox(height: 14),
              if (choose && image != null && text != null) ...[
                SegmentedButton<_What>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                        value: _What.text, label: Text(tr(c, 'share_text'))),
                    ButtonSegment(
                        value: _What.flier, label: Text(tr(c, 'flier'))),
                    ButtonSegment(
                        value: _What.both, label: Text(tr(c, 'share_both'))),
                  ],
                  selected: {what},
                  onSelectionChanged: (s) => set(() => what = s.first),
                ),
                const SizedBox(height: 14),
              ],
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: fieldFill, borderRadius: BorderRadius.circular(14)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (withImage && image != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.file(image,
                          width: 64, height: 80, fit: BoxFit.cover, cacheWidth: 200),
                    ),
                  if (withImage && image != null && withText && text != null)
                    const SizedBox(width: 12),
                  if (withText && text != null)
                    Expanded(
                      child: Text(text.replaceAll('*', ''),
                          maxLines: 5,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall),
                    ),
                ]),
              ),
              const SizedBox(height: 16),
              Row(children: [
                target(_Target.facebook, tr(c, 'facebook'), Icons.facebook,
                    const Color(0xFF1877F2)),
                target(_Target.whatsapp, tr(c, 'whatsapp'), Icons.chat_outlined,
                    const Color(0xFF1F8A4C)),
                target(_Target.more, tr(c, 'share_more'), Icons.more_horiz,
                    Colors.white),
              ]),
            ],
          ),
        ),
      );
    }),
  );
  if (picked == null || !context.mounted) return;
  final (w, t) = picked;
  final sendText = w == _What.flier ? null : text;
  final sendImage = w == _What.text ? null : image;
  final ur = isUr(context);
  await _send(t, sendText, sendImage?.path, messenger, ur);
}

Future<void> _send(_Target t, String? text, String? path,
    ScaffoldMessengerState messenger, bool ur) async {
  Future<void> sheet() => SharePlus.instance.share(ShareParams(
        text: text,
        files: path == null ? null : [XFile(path, mimeType: 'image/jpeg')],
      ));

  switch (t) {
    case _Target.more:
      await sheet();
    case _Target.facebook:
      // Facebook ignores text from other apps, so put it on the clipboard
      // for pasting as the caption.
      if (text != null) await Clipboard.setData(ClipboardData(text: text));
      final ok =
          await NativeBridge.shareTo(NativeBridge.facebook, text: text, path: path);
      if (!ok) {
        _show(messenger, '${trL(ur, 'facebook')} ${trL(ur, 'not_installed')}');
        await sheet();
      } else if (text != null) {
        _show(messenger, trL(ur, 'fb_text_copied'));
      }
    case _Target.whatsapp:
      var ok = false;
      for (final pkg in NativeBridge.whatsapp) {
        ok = await NativeBridge.shareTo(pkg, text: text, path: path);
        if (ok) break;
      }
      if (!ok) {
        _show(messenger, '${trL(ur, 'whatsapp')} ${trL(ur, 'not_installed')}');
        await sheet();
      }
  }
}

void _show(ScaffoldMessengerState m, String msg) => m.showSnackBar(
    SnackBar(content: Text(msg), duration: const Duration(seconds: 6)));

void _toast(BuildContext context, String msg) =>
    _show(ScaffoldMessenger.of(context), msg);
