import 'dart:math';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';

final _rnd = Random.secure();

/// Random v4 UUID: the id a row keeps on every phone and in the cloud.
String newUid() {
  final b = List<int>.generate(16, (_) => _rnd.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}

int _now() => DateTime.now().millisecondsSinceEpoch;

/// Columns that sync to the cloud (everything but local ids and sync state).
const hostSyncCols = ['name', 'phone', 'venue'];
const eventSyncCols = [
  'type', 'h_year', 'h_month', 'h_day', 'greg_override', 'start_min',
  'end_min', 'venue', 'topic', 'status', 'series_id', 'series_index',
  'series_total', 'flier',
];

/// Local SQLite store. Every row has a `uid` shared across phones, an
/// `updated_at` (ms) that decides which edit wins, and a `dirty` flag that
/// means "not yet uploaded". Deletes are remembered in `deletions` until
/// they have been uploaded.
class AppDb {
  late Database _db;

  Future<void> open({String? path, DatabaseFactory? factory}) async {
    path ??= p.join(await getDatabasesPath(), 'mimbar.db');
    _db = await (factory ?? databaseFactory).openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 3,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) async {
          await createV1(db);
          await _upgradeTo2(db, fresh: true);
          await _upgradeTo3(db);
        },
        onUpgrade: (db, from, _) async {
          if (from < 2) await _upgradeTo2(db, fresh: false);
          if (from < 3) await _upgradeTo3(db);
        },
      ),
    );
  }

  Future<void> close() => _db.close();

  @visibleForTesting
  static Future<void> createV1(Database db) async {
    await db.execute('''
      CREATE TABLE hosts(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT NOT NULL UNIQUE,
        venue TEXT NOT NULL DEFAULT '')''');
    await db.execute('''
      CREATE TABLE events(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        h_year INTEGER NOT NULL,
        h_month INTEGER NOT NULL,
        h_day INTEGER NOT NULL,
        greg_override TEXT,
        start_min INTEGER NOT NULL,
        end_min INTEGER NOT NULL,
        venue TEXT NOT NULL DEFAULT '',
        host_id INTEGER REFERENCES hosts(id),
        topic TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL,
        series_id TEXT,
        series_index INTEGER,
        series_total INTEGER,
        -- Former Nikkah party fields: unused, kept so older backups import.
        groom TEXT, groom_father TEXT, bride TEXT, bride_father TEXT,
        groom_wakeel TEXT, bride_wakeel TEXT, witness1 TEXT, witness2 TEXT)''');
    await db.execute(
        'CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)');
  }

  /// v2: cloud sync columns and tables.
  static Future<void> _upgradeTo2(Database db, {required bool fresh}) async {
    final now = _now();
    for (final t in ['hosts', 'events']) {
      await db.execute('ALTER TABLE $t ADD COLUMN uid TEXT');
      await db.execute(
          'ALTER TABLE $t ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0');
      await db.execute(
          'ALTER TABLE $t ADD COLUMN dirty INTEGER NOT NULL DEFAULT 1');
      for (final r in await db.query(t, columns: ['id'])) {
        await db.update(t, {'uid': newUid(), 'updated_at': now},
            where: 'id = ?', whereArgs: [r['id']]);
      }
      await db.execute('CREATE UNIQUE INDEX ${t}_uid ON $t(uid)');
    }
    await db.execute('''
      CREATE TABLE deletions(
        tbl TEXT NOT NULL,
        uid TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY(tbl, uid))''');
    await db.execute(
        'CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL)');
    // When two phones save the same number as separate hosts, the loser's
    // uid points at the surviving host.
    await db.execute(
        'CREATE TABLE host_alias(from_uid TEXT PRIMARY KEY, to_uid TEXT NOT NULL)');
    // Settings the user actually changed should upload; a fresh install's
    // defaults must never overwrite the other phone's.
    final customised =
        !fresh && (await db.query('settings', limit: 1)).isNotEmpty;
    await db.insert('meta',
        {'key': 'settings_updated_at', 'value': customised ? '$now' : '0'});
    await db.insert(
        'meta', {'key': 'settings_dirty', 'value': customised ? '1' : '0'});
  }

  /// v3: fliers. The image files live in their own folder; these queues
  /// remember which still need uploading, and which old ones to delete
  /// from the cloud once nothing refers to them.
  static Future<void> _upgradeTo3(Database db) async {
    await db.execute('ALTER TABLE events ADD COLUMN flier TEXT');
    await db.execute('CREATE TABLE flier_uploads(name TEXT PRIMARY KEY)');
    await db.execute('CREATE TABLE flier_trash(name TEXT PRIMARY KEY)');
  }

  // ----------------------------------------------------------------- meta

  Future<String?> getMeta(String key, [DatabaseExecutor? ex]) async {
    final rows = await (ex ?? _db)
        .query('meta', where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> setMeta(String key, String value, [DatabaseExecutor? ex]) =>
      (ex ?? _db).insert('meta', {'key': key, 'value': value},
          conflictAlgorithm: ConflictAlgorithm.replace);

  Future<int> _metaInt(String key, [DatabaseExecutor? ex]) async =>
      int.tryParse(await getMeta(key, ex) ?? '') ?? 0;

  // ------------------------------------------------------------- app reads

  Future<Map<String, String>> loadSettings() async {
    final rows = await _db.query('settings');
    return {for (final r in rows) r['key'] as String: r['value'] as String};
  }

  Future<List<Host>> loadHosts() async =>
      (await _db.query('hosts', orderBy: 'name COLLATE NOCASE'))
          .map(Host.fromMap)
          .toList();

  Future<List<Event>> loadEvents() async =>
      (await _db.query('events')).map(Event.fromMap).toList();

  Future<List<Map<String, Object?>>> rawRows(String table) => _db.query(table);

  // ------------------------------------------------------------ app writes

  /// Marks a row as edited now. Never moves `updated_at` backwards, so an
  /// edit made after pulling a newer one still wins on a slow clock.
  static Future<void> _touch(DatabaseExecutor ex, String table, int id) =>
      ex.rawUpdate(
          'UPDATE $table SET updated_at = MAX(?, updated_at + 1), dirty = 1 '
          'WHERE id = ?',
          [_now(), id]);

  static Future<void> _tombstone(
          DatabaseExecutor ex, String table, String uid, int at) =>
      ex.insert('deletions', {'tbl': table, 'uid': uid, 'updated_at': at},
          conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> saveSettings(Map<String, String> kv) async {
    await _db.transaction((txn) async {
      for (final e in kv.entries) {
        await txn.insert('settings', {'key': e.key, 'value': e.value},
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      final at = max(_now(), await _metaInt('settings_updated_at', txn) + 1);
      await setMeta('settings_updated_at', '$at', txn);
      await setMeta('settings_dirty', '1', txn);
    });
  }

  Future<int> saveHost(Host h) => _db.transaction((txn) async {
        final map = h.toMap()..remove('id');
        if (h.id == null) {
          return txn.insert('hosts',
              {...map, 'uid': newUid(), 'updated_at': _now(), 'dirty': 1});
        }
        await txn.update('hosts', map, where: 'id = ?', whereArgs: [h.id]);
        await _touch(txn, 'hosts', h.id!);
        return h.id!;
      });

  Future<void> saveEvents(List<Event> events) async {
    await _db.transaction((txn) async {
      for (final e in events) {
        final map = e.toMap()..remove('id');
        if (e.id == null) {
          e.id = await txn.insert('events',
              {...map, 'uid': newUid(), 'updated_at': _now(), 'dirty': 1});
          await _flierChanged(txn, null, e.flier);
        } else {
          final old = await _flierOf(txn, e.id!);
          await txn.update('events', map, where: 'id = ?', whereArgs: [e.id]);
          await _touch(txn, 'events', e.id!);
          await _flierChanged(txn, old, e.flier);
        }
      }
    });
  }

  /// Attaches, replaces (or with null removes) an event's flier.
  Future<void> setFlier(int id, String? name) => _db.transaction((txn) async {
        final old = await _flierOf(txn, id);
        await txn.update('events', {'flier': name},
            where: 'id = ?', whereArgs: [id]);
        await _touch(txn, 'events', id);
        await _flierChanged(txn, old, name);
      });

  static Future<String?> _flierOf(DatabaseExecutor ex, int id) async =>
      (await ex.query('events',
              columns: ['flier'], where: 'id = ?', whereArgs: [id]))
          .firstOrNull?['flier'] as String?;

  /// Queues a new flier for upload and an old one for deletion. Deletion
  /// only happens once no event uses it (series days share one flier).
  static Future<void> _flierChanged(
      DatabaseExecutor ex, String? old, String? now) async {
    if (old == now) return;
    if (now != null) {
      await ex.insert('flier_uploads', {'name': now},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    if (old != null) {
      await ex.insert('flier_trash', {'name': old},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<void> deleteEvent(int id) => _db.transaction((txn) async {
        final row = await txn.query('events',
            columns: ['uid', 'flier'], where: 'id = ?', whereArgs: [id]);
        if (row.isEmpty) return;
        await txn.delete('events', where: 'id = ?', whereArgs: [id]);
        await _tombstone(txn, 'events', row.first['uid'] as String, _now());
        await _flierChanged(txn, row.first['flier'] as String?, null);
      });

  Future<void> deleteEvents(List<int> ids) => _db.transaction((txn) async {
        for (final id in ids) {
          final row = await txn.query('events',
              columns: ['uid', 'flier'], where: 'id = ?', whereArgs: [id]);
          if (row.isEmpty) continue;
          await txn.delete('events', where: 'id = ?', whereArgs: [id]);
          await _tombstone(txn, 'events', row.first['uid'] as String, _now());
          await _flierChanged(txn, row.first['flier'] as String?, null);
        }
      });

  Future<void> setStatus(List<int> ids, EventStatus status) =>
      _db.transaction((txn) async {
        for (final id in ids) {
          await txn.update('events', {'status': status.name},
              where: 'id = ?', whereArgs: [id]);
          await _touch(txn, 'events', id);
        }
      });

  /// Deletes hosts. Their events stay, without a host.
  Future<void> deleteHosts(List<int> ids) => _db.transaction((txn) async {
        final now = _now();
        for (final id in ids) {
          final row = await txn.query('hosts',
              columns: ['uid'], where: 'id = ?', whereArgs: [id]);
          if (row.isEmpty) continue;
          await txn.rawUpdate(
              'UPDATE events SET host_id = NULL, '
              'updated_at = MAX(?, updated_at + 1), dirty = 1 WHERE host_id = ?',
              [now, id]);
          await txn.delete('hosts', where: 'id = ?', whereArgs: [id]);
          await _tombstone(txn, 'hosts', row.first['uid'] as String, now);
        }
      });

  /// Every flier name some event still uses.
  Future<Set<String>> referencedFliers() async => {
        for (final r in await _db.rawQuery(
            'SELECT DISTINCT flier FROM events WHERE flier IS NOT NULL'))
          r['flier'] as String
      };

  /// Fliers waiting to upload that an event still uses. Queue entries no
  /// event uses any more are dropped.
  Future<List<String>> pendingUploads() => _db.transaction((txn) async {
        await txn.rawDelete('DELETE FROM flier_uploads WHERE name NOT IN '
            '(SELECT flier FROM events WHERE flier IS NOT NULL)');
        return [
          for (final r in await txn.query('flier_uploads'))
            r['name'] as String
        ];
      });

  Future<Set<String>> uploadQueue() async =>
      {for (final r in await _db.query('flier_uploads')) r['name'] as String};

  Future<void> clearUpload(String name) =>
      _db.delete('flier_uploads', where: 'name = ?', whereArgs: [name]);

  /// Old fliers no event uses any more. Ones in use again are dropped from
  /// the queue.
  Future<List<String>> pendingTrash() => _db.transaction((txn) async {
        await txn.rawDelete('DELETE FROM flier_trash WHERE name IN '
            '(SELECT flier FROM events WHERE flier IS NOT NULL)');
        return [
          for (final r in await txn.query('flier_trash')) r['name'] as String
        ];
      });

  Future<void> clearTrash(List<String> names) async {
    final b = _db.batch();
    for (final n in names) {
      b.delete('flier_trash', where: 'name = ?', whereArgs: [n]);
    }
    await b.commit(noResult: true);
  }

  Future<void> markDone(List<int> ids) async {
    if (ids.isEmpty) return;
    await _db.transaction((txn) async {
      for (final id in ids) {
        await txn.update('events', {'status': EventStatus.done.name},
            where: 'id = ?', whereArgs: [id]);
        await _touch(txn, 'events', id);
      }
    });
  }

  /// Replaces every table's contents in one transaction (backup import).
  /// Rows missing from the backup are deleted on the other phones too.
  Future<void> replaceAll({
    required Map<String, String> settings,
    required List<Map<String, Object?>> hosts,
    required List<Map<String, Object?>> events,
  }) async {
    final now = _now();
    await _db.transaction((txn) async {
      for (final (table, rows) in [('events', events), ('hosts', hosts)]) {
        final keep = {for (final r in rows) r['uid']};
        for (final r in await txn.query(table, columns: ['uid'])) {
          if (!keep.contains(r['uid'])) {
            await _tombstone(txn, table, r['uid'] as String, now);
          }
        }
        await txn.delete(table);
      }
      for (final (table, rows) in [('hosts', hosts), ('events', events)]) {
        final cols = await _columns(txn, table);
        for (final r in rows) {
          final uid = (r['uid'] as String?) ?? newUid();
          await txn.delete('deletions',
              where: 'tbl = ? AND uid = ?', whereArgs: [table, uid]);
          await txn.insert(table, {
            for (final e in r.entries)
              if (cols.contains(e.key)) e.key: e.value,
            'uid': uid,
            'updated_at': now,
            'dirty': 1,
          });
        }
      }
      await txn.delete('settings');
      for (final kv in settings.entries) {
        await txn.insert('settings', {'key': kv.key, 'value': kv.value});
      }
      await setMeta('settings_updated_at', '$now', txn);
      await setMeta('settings_dirty', '1', txn);
    });
  }

  static Future<Set<String>> _columns(DatabaseExecutor ex, String table) async =>
      {for (final r in await ex.rawQuery('PRAGMA table_info($table)')) r['name'] as String};

  // ------------------------------------------------------------- sync: push

  Future<List<Map<String, Object?>>> dirtyHosts() => _db.query('hosts',
      columns: ['uid', ...hostSyncCols, 'updated_at'], where: 'dirty = 1');

  Future<List<Map<String, Object?>>> dirtyEvents() => _db.rawQuery(
      'SELECT e.uid, ${eventSyncCols.map((c) => 'e.$c').join(', ')}, '
      'e.updated_at, h.uid AS host_uid '
      'FROM events e LEFT JOIN hosts h ON h.id = e.host_id WHERE e.dirty = 1');

  /// Clears `dirty` on uploaded rows, unless they were edited meanwhile.
  Future<void> markClean(String table, List<Map<String, Object?>> rows) async {
    final b = _db.batch();
    for (final r in rows) {
      b.update(table, {'dirty': 0},
          where: 'uid = ? AND updated_at = ?',
          whereArgs: [r['uid'], r['updated_at']]);
    }
    await b.commit(noResult: true);
  }

  Future<List<Map<String, Object?>>> pendingDeletions() =>
      _db.query('deletions');

  Future<void> clearDeletions(List<Map<String, Object?>> rows) async {
    final b = _db.batch();
    for (final r in rows) {
      b.delete('deletions',
          where: 'tbl = ? AND uid = ? AND updated_at = ?',
          whereArgs: [r['tbl'], r['uid'], r['updated_at']]);
    }
    await b.commit(noResult: true);
  }

  /// Settings waiting to upload, with their edit time; null if none.
  Future<(Map<String, String>, int)?> dirtySettings() async {
    if (await getMeta('settings_dirty') != '1') return null;
    return (await loadSettings(), await _metaInt('settings_updated_at'));
  }

  Future<void> markSettingsClean(int at) => _db.transaction((txn) async {
        if (await _metaInt('settings_updated_at', txn) == at) {
          await setMeta('settings_dirty', '0', txn);
        }
      });

  /// After signing in: upload everything once and pull everything.
  Future<void> resetSync() => _db.transaction((txn) async {
        await txn.rawUpdate('UPDATE hosts SET dirty = 1');
        await txn.rawUpdate('UPDATE events SET dirty = 1');
        await txn.rawInsert('INSERT OR IGNORE INTO flier_uploads(name) '
            'SELECT DISTINCT flier FROM events WHERE flier IS NOT NULL');
        if (await _metaInt('settings_updated_at', txn) > 0) {
          await setMeta('settings_dirty', '1', txn);
        }
        await txn.delete('meta', where: "key LIKE 'pull_%'");
      });

  // ------------------------------------------------------------- sync: pull

  static int _ms(Object? v) => (v as num).toInt();

  Future<Map<String, Object?>?> _byUid(
          DatabaseExecutor ex, String table, String uid) async =>
      (await ex.query(table, where: 'uid = ?', whereArgs: [uid], limit: 1))
          .firstOrNull;

  /// True if this phone deleted the row after the given edit time.
  Future<bool> _deletedSince(
      DatabaseExecutor ex, String table, String uid, int at) async {
    final r = await ex.query('deletions',
        where: 'tbl = ? AND uid = ? AND updated_at >= ?',
        whereArgs: [table, uid, at],
        limit: 1);
    return r.isNotEmpty;
  }

  /// Merges the [loser] host into the winner: its events move over, it is
  /// deleted here and in the cloud, and its uid is remembered as an alias.
  static Future<void> _retireHost(DatabaseExecutor ex,
      Map<String, Object?> loser, int winnerId, String winnerUid) async {
    final now = _now();
    await ex.rawUpdate(
        'UPDATE events SET host_id = ?, updated_at = MAX(?, updated_at + 1), '
        'dirty = 1 WHERE host_id = ?',
        [winnerId, now, loser['id']]);
    await ex.delete('hosts', where: 'id = ?', whereArgs: [loser['id']]);
    await _alias(ex, loser['uid'] as String, winnerUid);
    await _tombstone(ex, 'hosts', loser['uid'] as String, now);
  }

  static Future<void> _alias(DatabaseExecutor ex, String from, String to) =>
      ex.insert('host_alias', {'from_uid': from, 'to_uid': to},
          conflictAlgorithm: ConflictAlgorithm.replace);

  static Future<String> _resolveAlias(DatabaseExecutor ex, String uid) async {
    for (var i = 0; i < 8; i++) {
      final r = await ex.query('host_alias',
          where: 'from_uid = ?', whereArgs: [uid], limit: 1);
      if (r.isEmpty) break;
      uid = r.first['to_uid'] as String;
    }
    return uid;
  }

  /// Applies hosts downloaded from the cloud. Returns true if anything changed.
  Future<bool> applyHosts(List<Map<String, dynamic>> rows) =>
      _db.transaction((txn) async {
        var changed = false;
        for (final r in rows) {
          final uid = r['uid'] as String;
          final at = _ms(r['updated_at']);
          if (await _deletedSince(txn, 'hosts', uid, at)) continue;
          final local = await _byUid(txn, 'hosts', uid);
          if (local != null && at <= (local['updated_at'] as int)) continue;

          if (r['deleted'] == true) {
            if (local != null) {
              await txn.update('events', {'host_id': null},
                  where: 'host_id = ?', whereArgs: [local['id']]);
              await txn.delete('hosts',
                  where: 'id = ?', whereArgs: [local['id']]);
              changed = true;
            }
            continue;
          }

          final phone = r['phone'] as String;
          final twin = (await txn.query('hosts',
                  where: 'phone = ? AND uid != ?',
                  whereArgs: [phone, uid],
                  limit: 1))
              .firstOrNull;
          // Both phones saved this number as a new host while offline. Every
          // phone keeps the host with the smaller uid, so they all agree.
          if (twin != null && (twin['uid'] as String).compareTo(uid) < 0) {
            final twinUid = twin['uid'] as String;
            if (local != null) {
              await _retireHost(txn, local, twin['id'] as int, twinUid);
            } else {
              await _alias(txn, uid, twinUid);
              await _tombstone(txn, 'hosts', uid, _now());
            }
            changed = true;
            continue;
          }

          // Written with a placeholder number first, so a twin still holding
          // the real one doesn't hit the UNIQUE constraint.
          final values = {
            for (final c in hostSyncCols) c: r[c] ?? '',
            'phone': '~$uid',
            'uid': uid,
            'updated_at': at,
            'dirty': 0,
          };
          final int id;
          if (local == null) {
            id = await txn.insert('hosts', values);
          } else {
            id = local['id'] as int;
            await txn.update('hosts', values, where: 'id = ?', whereArgs: [id]);
          }
          if (twin != null) await _retireHost(txn, twin, id, uid);
          await txn.update('hosts', {'phone': phone},
              where: 'id = ?', whereArgs: [id]);
          changed = true;
        }
        return changed;
      });

  /// Applies events downloaded from the cloud. Returns true if anything changed.
  Future<bool> applyEvents(List<Map<String, dynamic>> rows) =>
      _db.transaction((txn) async {
        var changed = false;
        for (final r in rows) {
          final uid = r['uid'] as String;
          final at = _ms(r['updated_at']);
          if (await _deletedSince(txn, 'events', uid, at)) continue;
          final local = await _byUid(txn, 'events', uid);
          if (local != null && at <= (local['updated_at'] as int)) continue;

          if (r['deleted'] == true) {
            if (local != null) {
              await txn.delete('events',
                  where: 'id = ?', whereArgs: [local['id']]);
              changed = true;
            }
            continue;
          }

          int? hostId;
          var repointed = false;
          final hostUid = r['host_uid'] as String?;
          if (hostUid != null) {
            final resolved = await _resolveAlias(txn, hostUid);
            hostId = (await _byUid(txn, 'hosts', resolved))?['id'] as int?;
            repointed = hostId != null && resolved != hostUid;
          }
          final values = {
            // Only columns the cloud sent, so an older schema can't blank
            // a newer column here.
            for (final c in eventSyncCols)
              if (r.containsKey(c)) c: r[c],
            'host_id': hostId,
            'uid': uid,
            // A host merged on this phone: upload the corrected link.
            'updated_at': repointed ? at + 1 : at,
            'dirty': repointed ? 1 : 0,
          };
          if (local == null) {
            await txn.insert('events', values);
          } else {
            await txn.update('events', values,
                where: 'id = ?', whereArgs: [local['id']]);
          }
          changed = true;
        }
        return changed;
      });

  /// Applies the cloud's settings if they are newer than this phone's.
  Future<bool> applySettings(Map<String, String> kv, int at) =>
      _db.transaction((txn) async {
        if (at <= await _metaInt('settings_updated_at', txn)) return false;
        await txn.delete('settings');
        for (final e in kv.entries) {
          await txn.insert('settings', {'key': e.key, 'value': e.value});
        }
        await setMeta('settings_updated_at', '$at', txn);
        await setMeta('settings_dirty', '0', txn);
        return true;
      });
}
