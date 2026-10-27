import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/models.dart';
import '../data/store.dart';
import 'sync.dart';

class Backup {
  static const _app = 'mimbar';
  static const _version = 2;

  static String _fileName() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'mimbar-backup-${n.year}${two(n.month)}${two(n.day)}-'
        '${two(n.hour)}${two(n.minute)}.json';
  }

  static Future<Uint8List> _bytes() async {
    final data = {
      'app': _app,
      'version': _version,
      'exportedAt': DateTime.now().toIso8601String(),
      'settings': await store.db.loadSettings(),
      'hosts': await store.db.rawRows('hosts'),
      'events': await store.db.rawRows('events'),
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(data)));
  }

  /// Lets the user choose a folder/file name on the phone. Returns false if
  /// they backed out of the picker.
  static Future<bool> saveToPhone() async {
    final uri = await FilePicker.saveFile(
      fileName: _fileName(),
      bytes: await _bytes(),
      mimeType: 'application/json',
    );
    return uri != null;
  }

  /// Opens the share sheet (WhatsApp, Drive, Bluetooth, ...) with the file.
  static Future<void> share() async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${_fileName()}');
    await file.writeAsBytes(await _bytes());
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'application/json')],
      subject: 'Mimbar backup',
    ));
  }

  /// Returns null if the user cancelled, true on success, false if the file
  /// was invalid (in which case nothing was changed).
  static Future<bool?> pickAndImport(
      Future<bool> Function() confirmReplace) async {
    final f = await FilePicker.pickFile(type: FileType.any);
    if (f == null) return null;
    final Uint8List bytes;
    try {
      bytes = await f.readAsBytes();
    } catch (_) {
      return false;
    }

    final Map<String, String> settings;
    final List<Map<String, Object?>> hosts, events;
    try {
      final m = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      if (m['app'] != _app) return false;
      settings = (m['settings'] as Map).map((k, v) => MapEntry('$k', '$v'));
      hosts = [
        for (final h in m['hosts'] as List) Map<String, Object?>.from(h as Map)
      ];
      events = [
        for (final e in m['events'] as List) Map<String, Object?>.from(e as Map)
      ];
      // Parse everything up front so a bad file never touches the database.
      hosts.forEach(Host.fromMap);
      events.forEach(Event.fromMap);
    } catch (_) {
      return false;
    }

    if (!await confirmReplace()) return null;
    await store.db.replaceAll(settings: settings, hosts: hosts, events: events);
    await store.reloadAll();
    sync.request();
    return true;
  }
}
