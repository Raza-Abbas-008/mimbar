import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/db.dart';

/// Flier images on this phone, in one folder, named by the value stored in
/// the event's `flier` column. Sync uploads them to Supabase Storage.
class Fliers {
  static late Directory dir;

  static Future<void> init() async {
    final base = await getApplicationSupportDirectory();
    dir = Directory(p.join(base.path, 'fliers'));
    await dir.create(recursive: true);
  }

  static File file(String name) => File(p.join(dir.path, name));

  static bool has(String name) => file(name).existsSync();

  /// Copies an image into the flier folder as a JPEG of at most about
  /// 1600 px (a few hundred KB). Returns the new flier's name.
  static Future<String> add(String sourcePath) async {
    final name = '${newUid()}.jpg';
    final out = file(name);
    XFile? small;
    try {
      small = await FlutterImageCompress.compressAndGetFile(
        sourcePath,
        out.path,
        minWidth: 1600,
        minHeight: 1600,
        quality: 82,
      );
    } catch (_) {
      small = null;
    }
    // Formats the compressor can't read are kept as they are.
    if (small == null) await File(sourcePath).copy(out.path);
    return name;
  }

  /// Deletes files no event uses and no upload is waiting for.
  static Future<void> clean(Set<String> keep) async {
    await for (final f in dir.list()) {
      if (f is File && !keep.contains(p.basename(f.path))) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
  }
}
