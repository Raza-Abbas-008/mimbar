import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/store.dart';

final sync = SyncService();

/// Two-way sync between this phone's SQLite and Supabase. The app always
/// reads and writes locally; this uploads dirty rows and downloads newer
/// ones whenever there is a connection. Off entirely when the build has no
/// Supabase keys or nobody is signed in.
class SyncService extends ChangeNotifier {
  static const _url = String.fromEnvironment('SUPABASE_URL');
  static const _key = String.fromEnvironment('SUPABASE_KEY');

  bool get configured => _url.isNotEmpty && _key.isNotEmpty;
  SupabaseClient get _c => Supabase.instance.client;

  bool _ready = false;
  bool get signedIn => _ready && _c.auth.currentUser != null;
  String? get email => signedIn ? _c.auth.currentUser!.email : null;

  bool syncing = false;
  DateTime? lastSynced;

  /// Last failure, cleared on the next successful sync.
  String? error;

  Timer? _debounce, _retry;
  bool _again = false;
  RealtimeChannel? _channel;

  Future<void> init() async {
    if (!configured) return;
    try {
      await Supabase.initialize(url: _url, publishableKey: _key);
    } catch (e) {
      error = '$e';
      return;
    }
    _ready = true;
    final last = int.tryParse(await store.db.getMeta('last_synced') ?? '');
    if (last != null) lastSynced = DateTime.fromMillisecondsSinceEpoch(last);
    Connectivity().onConnectivityChanged.listen((r) {
      if (!r.contains(ConnectivityResult.none)) request();
    });
    if (signedIn) {
      _listen();
      request();
    }
  }

  /// Returns null on success, or the reason sign-in failed.
  Future<String?> signIn(String email, String password) async {
    try {
      await _c.auth.signInWithPassword(email: email.trim(), password: password);
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      return '$e';
    }
    await store.db.resetSync();
    _listen();
    notifyListeners();
    await syncNow();
    return null;
  }

  /// Stops syncing. The data stays on this phone.
  Future<void> signOut() async {
    await _channel?.unsubscribe();
    _channel = null;
    _retry?.cancel();
    try {
      await _c.auth.signOut();
    } catch (_) {
      // Offline: the local session is cleared regardless.
    }
    error = null;
    notifyListeners();
  }

  /// Asks the other phone's changes to arrive as soon as they are saved.
  void _listen() {
    _channel?.unsubscribe();
    var ch = _c.channel('mimbar-changes');
    for (final t in ['hosts', 'events', 'settings']) {
      ch = ch.onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: t,
          callback: (_) => request());
    }
    _channel = ch..subscribe();
  }

  /// Schedules a sync shortly, folding bursts of edits into one.
  void request({Duration delay = const Duration(milliseconds: 1500)}) {
    if (!signedIn) return;
    _debounce?.cancel();
    _debounce = Timer(delay, syncNow);
  }

  Future<void> syncNow() async {
    if (!signedIn) return;
    if (syncing) {
      _again = true;
      return;
    }
    syncing = true;
    _retry?.cancel();
    notifyListeners();
    try {
      await _push();
      if (await _pull()) await store.reloadAll();
      lastSynced = DateTime.now();
      await store.db
          .setMeta('last_synced', '${lastSynced!.millisecondsSinceEpoch}');
      error = null;
    } catch (e) {
      error = '$e';
      // Usually offline; connectivity changes also trigger a retry.
      _retry = Timer(const Duration(minutes: 2), syncNow);
    } finally {
      syncing = false;
      notifyListeners();
    }
    if (_again) {
      _again = false;
      request(delay: Duration.zero);
    }
  }

  Future<void> _push() async {
    final db = store.db;

    final dels = await db.pendingDeletions();
    for (final t in ['hosts', 'events']) {
      final rows = [
        for (final d in dels)
          if (d['tbl'] == t)
            {'uid': d['uid'], 'deleted': true, 'updated_at': d['updated_at']}
      ];
      // missing=default lets a tombstone for a never-uploaded row insert.
      if (rows.isNotEmpty) {
        await _c.from(t).upsert(rows, onConflict: 'uid', defaultToNull: false);
      }
    }
    await db.clearDeletions(dels);

    final hosts = await db.dirtyHosts();
    if (hosts.isNotEmpty) {
      await _c.from('hosts').upsert(
          [for (final h in hosts) {...h, 'deleted': false}],
          onConflict: 'uid');
      await db.markClean('hosts', hosts);
    }

    final events = await db.dirtyEvents();
    if (events.isNotEmpty) {
      await _c.from('events').upsert(
          [for (final e in events) {...e, 'deleted': false}],
          onConflict: 'uid');
      await db.markClean('events', events);
    }

    final s = await db.dirtySettings();
    if (s != null) {
      final (kv, at) = s;
      await _c.from('settings').upsert({
        'user_id': _c.auth.currentUser!.id,
        'data': kv,
        'updated_at': at,
      }, onConflict: 'user_id');
      await db.markSettingsClean(at);
    }
  }

  /// Downloads rows changed since the last pull. Returns true if anything
  /// on this phone changed.
  Future<bool> _pull() async {
    final db = store.db;
    var changed = false;
    for (final t in ['hosts', 'events']) {
      var since = await db.getMeta('pull_$t') ?? '1970-01-01T00:00:00Z';
      String? latest;
      while (true) {
        final rows = await _c
            .from(t)
            .select()
            .gt('server_ts', since)
            .order('server_ts')
            .limit(500);
        if (rows.isEmpty) break;
        if (t == 'hosts') {
          changed |= await db.applyHosts(rows);
        } else {
          changed |= await db.applyEvents(rows);
        }
        since = latest = rows.last['server_ts'] as String;
        if (rows.length < 500) break;
      }
      // Re-read the last minute next time: a write that started earlier but
      // committed later can carry a slightly older timestamp.
      if (latest != null) {
        final back =
            DateTime.parse(latest).subtract(const Duration(minutes: 1));
        await db.setMeta('pull_$t', back.toUtc().toIso8601String());
      }
    }

    final s = await _c.from('settings').select().maybeSingle();
    if (s != null) {
      final kv = (s['data'] as Map).map((k, v) => MapEntry('$k', '$v'));
      changed |= await db.applySettings(kv, (s['updated_at'] as num).toInt());
    }
    return changed;
  }
}
