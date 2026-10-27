import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';

import '../core/strings.dart';
import '../services/fliers.dart';
import '../services/native.dart';
import '../services/sync.dart';
import 'share_sheet.dart';

/// Lets the user pick an image from the phone's gallery app and stores it
/// as a flier. Returns the new flier's name, or null if they backed out.
Future<String?> pickFlier() async {
  String? path;
  try {
    path = await NativeBridge.pickImage();
  } on GalleryUnavailable {
    path = (await ImagePicker().pickImage(source: ImageSource.gallery))?.path;
  }
  if (path == null) return null;
  return Fliers.add(path);
}

/// Full-screen flier with pinch-to-zoom. [onChanged] gets the replacement
/// flier's name, or null when it is removed.
class FlierScreen extends StatefulWidget {
  final String name;
  final Future<void> Function(String? name) onChanged;
  const FlierScreen({super.key, required this.name, required this.onChanged});

  @override
  State<FlierScreen> createState() => _FlierScreenState();
}

class _FlierScreenState extends State<FlierScreen> {
  late String name = widget.name;
  late Future<File?> file = sync.flierFile(name);

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _replace() async {
    final n = await pickFlier();
    if (n == null) return;
    await widget.onChanged(n);
    setState(() {
      name = n;
      file = sync.flierFile(n);
    });
  }

  Future<void> _remove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr(c, 'remove_flier_q')),
        content: Text(tr(c, 'remove_flier_body')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(tr(c, 'cancel'))),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(c, true),
              child: Text(tr(c, 'remove'))),
        ],
      ),
    );
    if (ok != true) return;
    await widget.onChanged(null);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _save(File f) async {
    try {
      if (!await Gal.hasAccess()) await Gal.requestAccess();
      await Gal.putImage(f.path, album: 'Mimbar');
      if (mounted) _toast(tr(context, 'flier_saved'));
    } catch (e) {
      if (mounted) _toast('$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget action(IconData icon, String key, VoidCallback? onTap,
            {Color color = Colors.white}) =>
        Expanded(
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, color: onTap == null ? Colors.white38 : color),
                const SizedBox(height: 6),
                Text(tr(context, key),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: onTap == null ? Colors.white38 : color,
                        fontSize: 12)),
              ]),
            ),
          ),
        );

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(tr(context, 'flier'),
            style: const TextStyle(color: Colors.white)),
      ),
      body: FutureBuilder<File?>(
        future: file,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(
                child: CircularProgressIndicator(color: Colors.white));
          }
          final f = snap.data;
          return Column(children: [
            Expanded(
              child: f == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(tr(context, 'flier_missing'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white70)),
                      ),
                    )
                  : InteractiveViewer(
                      maxScale: 5,
                      child: Center(child: Image.file(f, key: ValueKey(name))),
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                child: Row(children: [
                  action(Icons.share_outlined, 'share',
                      f == null ? null : () => showFlierShare(context, f)),
                  action(Icons.autorenew, 'replace', _replace),
                  action(Icons.download_outlined, 'save_to_gallery',
                      f == null ? null : () => _save(f)),
                  action(Icons.delete_outline, 'remove', _remove,
                      color: const Color(0xFFFF6B6B)),
                ]),
              ),
            ),
          ]);
        },
      ),
    );
  }
}
