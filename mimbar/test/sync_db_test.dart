import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimbar/core/hijri.dart';
import 'package:mimbar/data/db.dart';
import 'package:mimbar/data/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Mimics the Supabase tables and the last-write-wins trigger.
class FakeCloud {
  final tables = <String, Map<String, Map<String, dynamic>>>{
    'hosts': {},
    'events': {},
  };
  Map<String, dynamic>? settings;

  void upsert(String t, List<Map<String, Object?>> rows) {
    for (final r in rows) {
      final old = tables[t]![r['uid']];
      if (old != null && (r['updated_at'] as int) < old['updated_at']) continue;
      tables[t]![r['uid'] as String] = {...?old, ...r};
    }
  }

  List<Map<String, dynamic>> all(String t) =>
      [for (final r in tables[t]!.values) Map.of(r)];
}

/// Same steps as SyncService, against the fake cloud.
Future<void> syncPhone(AppDb db, FakeCloud c) async {
  final dels = await db.pendingDeletions();
  for (final d in dels) {
    c.upsert(d['tbl'] as String, [
      {'uid': d['uid'], 'deleted': true, 'updated_at': d['updated_at']}
    ]);
  }
  await db.clearDeletions(dels);
  final hosts = await db.dirtyHosts();
  c.upsert('hosts', [for (final h in hosts) {...h, 'deleted': false}]);
  await db.markClean('hosts', hosts);
  final events = await db.dirtyEvents();
  c.upsert('events', [for (final e in events) {...e, 'deleted': false}]);
  await db.markClean('events', events);
  final s = await db.dirtySettings();
  if (s != null) {
    final (kv, at) = s;
    if (c.settings == null || at >= c.settings!['updated_at']) {
      c.settings = {'data': kv, 'updated_at': at};
    }
    await db.markSettingsClean(at);
  }
  await db.applyHosts(c.all('hosts'));
  await db.applyEvents(c.all('events'));
  if (c.settings != null) {
    await db.applySettings(Map<String, String>.from(c.settings!['data']),
        c.settings!['updated_at'] as int);
  }
}

Event ev({int? hostId, String topic = ''}) => Event(
    type: EventType.majlis,
    hijri: const HDate(1447, 1, 1),
    startMin: 600,
    endMin: 690,
    hostId: hostId,
    topic: topic);

void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfiNoIsolate;
  final opened = <AppDb>[];
  var n = 0;

  Future<AppDb> phone() async {
    final db = AppDb();
    // A distinct in-memory database per phone.
    await db.open(path: 'file:phone${n++}?mode=memory', factory: factory);
    opened.add(db);
    return db;
  }

  tearDown(() async {
    for (final db in opened) {
      await db.close();
    }
    opened.clear();
  });

  test('a booking and its host reach the other phone', () async {
    final cloud = FakeCloud();
    final a = await phone(), b = await phone();
    final h = await a.saveHost(Host(name: 'Abbas', phone: '03001234567'));
    await a.saveEvents([ev(hostId: h, topic: 'Ashura')]);
    await syncPhone(a, cloud);
    await syncPhone(b, cloud);

    final hosts = await b.loadHosts();
    final events = await b.loadEvents();
    expect(hosts.single.name, 'Abbas');
    expect(events.single.topic, 'Ashura');
    expect(events.single.hostId, hosts.single.id);
    expect(await b.dirtyEvents(), isEmpty);
  });

  test('edits and deletes travel both ways', () async {
    final cloud = FakeCloud();
    final a = await phone(), b = await phone();
    await a.saveEvents([ev(topic: 'one'), ev(topic: 'two')]);
    await syncPhone(a, cloud);
    await syncPhone(b, cloud);

    final onB = await b.loadEvents();
    final one = onB.firstWhere((e) => e.topic == 'one')..topic = 'one!';
    await b.saveEvents([one]);
    await b.deleteEvent(onB.firstWhere((e) => e.topic == 'two').id!);
    await syncPhone(b, cloud);
    await syncPhone(a, cloud);

    expect((await a.loadEvents()).map((e) => e.topic), ['one!']);
  });

  test('the later of two offline edits wins on both phones', () async {
    final cloud = FakeCloud();
    final a = await phone(), b = await phone();
    await a.saveEvents([ev(topic: 'x')]);
    await syncPhone(a, cloud);
    await syncPhone(b, cloud);

    await a.saveEvents([(await a.loadEvents()).single..topic = 'from A']);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await b.saveEvents([(await b.loadEvents()).single..topic = 'from B']);
    await syncPhone(b, cloud);
    await syncPhone(a, cloud);
    await syncPhone(b, cloud);

    expect((await a.loadEvents()).single.topic, 'from B');
    expect((await b.loadEvents()).single.topic, 'from B');
  });

  test('an edit beats an older delete from the other phone', () async {
    final cloud = FakeCloud();
    final a = await phone(), b = await phone();
    await a.saveEvents([ev(topic: 'x')]);
    await syncPhone(a, cloud);
    await syncPhone(b, cloud);

    await a.deleteEvent((await a.loadEvents()).single.id!);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await b.saveEvents([(await b.loadEvents()).single..topic = 'kept']);
    await syncPhone(a, cloud);
    await syncPhone(b, cloud);
    await syncPhone(a, cloud);

    expect((await a.loadEvents()).single.topic, 'kept');
    expect((await b.loadEvents()).single.topic, 'kept');
  });

  test('the same number saved on both phones becomes one host', () async {
    final cloud = FakeCloud();
    final a = await phone(), b = await phone();
    final ha = await a.saveHost(Host(name: 'Abbas A', phone: '03001234567'));
    await a.saveEvents([ev(hostId: ha, topic: 'from A')]);
    final hb = await b.saveHost(Host(name: 'Abbas B', phone: '03001234567'));
    await b.saveEvents([ev(hostId: hb, topic: 'from B')]);

    for (var i = 0; i < 3; i++) {
      await syncPhone(a, cloud);
      await syncPhone(b, cloud);
    }

    for (final db in [a, b]) {
      final hosts = await db.loadHosts();
      expect(hosts, hasLength(1));
      final events = await db.loadEvents();
      expect(events, hasLength(2));
      expect(events.every((e) => e.hostId == hosts.single.id), isTrue);
    }
    expect((await a.loadHosts()).single.name,
        (await b.loadHosts()).single.name);
    expect(cloud.all('hosts').where((h) => h['deleted'] != true),
        hasLength(1));
  });

  test("a fresh install's default settings never overwrite", () async {
    final cloud = FakeCloud();
    final a = await phone();
    await a.saveSettings((AppSettings.defaults()..offset = 1).toKv());
    await syncPhone(a, cloud);
    final b = await phone();
    await syncPhone(b, cloud);
    expect(AppSettings.fromKv(await b.loadSettings()).offset, 1);
  });

  test('importing a backup deletes rows missing from it everywhere', () async {
    final cloud = FakeCloud();
    final a = await phone(), b = await phone();
    await a.saveEvents([ev(topic: 'keep'), ev(topic: 'drop')]);
    final backup = (await a.rawRows('events'))
        .where((r) => r['topic'] == 'keep')
        .toList();
    await syncPhone(a, cloud);
    await syncPhone(b, cloud);

    await a.replaceAll(settings: {}, hosts: [], events: backup);
    await syncPhone(a, cloud);
    await syncPhone(b, cloud);
    expect((await b.loadEvents()).map((e) => e.topic), ['keep']);
  });

  test('upgrading a v1 database keeps its data and queues it for upload',
      () async {
    final dir = await Directory.systemTemp.createTemp('mimbar');
    final path = '${dir.path}/v1.db';
    final v1 = await factory.openDatabase(path,
        options: OpenDatabaseOptions(
            version: 1, onCreate: (db, _) => AppDb.createV1(db)));
    final hostId = await v1.insert(
        'hosts', {'name': 'Old', 'phone': '03001234567', 'venue': ''});
    await v1.insert('events', {
      ...ev(hostId: hostId, topic: 'old').toMap()
        ..remove('id')
        ..remove('flier'), // not a v1 column
    });
    await v1.insert('settings', {'key': 'offset', 'value': '-1'});

    await v1.close();
    final db = AppDb();
    await db.open(path: path, factory: factory);
    addTearDown(() async {
      await db.close();
      await dir.delete(recursive: true);
    });

    expect((await db.loadEvents()).single.topic, 'old');
    expect(await db.dirtyHosts(), hasLength(1));
    final events = await db.dirtyEvents();
    expect(events.single['uid'], isNotNull);
    expect(events.single['host_uid'], (await db.dirtyHosts()).single['uid']);
    expect(await db.dirtySettings(), isNotNull);
  });

  group('fliers', () {
    test('adding queues an upload; replacing queues the old one to delete',
        () async {
      final a = await phone();
      await a.saveEvents([ev(topic: 'x')]);
      final id = (await a.loadEvents()).single.id!;
      await a.setFlier(id, 'one.jpg');
      expect(await a.pendingUploads(), ['one.jpg']);
      await a.clearUpload('one.jpg');
      await a.setFlier(id, 'two.jpg');
      expect(await a.pendingUploads(), ['two.jpg']);
      expect(await a.pendingTrash(), ['one.jpg']);
    });

    test('a flier shared by series days is kept until no day uses it',
        () async {
      final a = await phone();
      await a.saveEvents([ev()..flier = 's.jpg', ev()..flier = 's.jpg']);
      final ids = [for (final e in await a.loadEvents()) e.id!];
      await a.setFlier(ids[0], null);
      expect(await a.pendingTrash(), isEmpty);
      await a.deleteEvent(ids[1]);
      expect(await a.pendingTrash(), ['s.jpg']);
    });

    test('the flier name syncs to the other phone', () async {
      final cloud = FakeCloud();
      final a = await phone(), b = await phone();
      await a.saveEvents([ev()..flier = 'f.jpg']);
      await syncPhone(a, cloud);
      await syncPhone(b, cloud);
      expect((await b.loadEvents()).single.flier, 'f.jpg');
      expect(await b.pendingUploads(), isEmpty);
    });

    test('an older cloud row without the flier column keeps the local one',
        () async {
      final a = await phone();
      await a.saveEvents([ev()..flier = 'f.jpg']);
      final row = Map<String, dynamic>.from((await a.dirtyEvents()).single)
        ..remove('flier')
        ..['updated_at'] = DateTime.now().millisecondsSinceEpoch + 1000
        ..['deleted'] = false;
      await a.applyEvents([row]);
      expect((await a.loadEvents()).single.flier, 'f.jpg');
    });
  });

  group('bulk actions', () {
    test('deleting a host keeps its events, on both phones', () async {
      final cloud = FakeCloud();
      final a = await phone(), b = await phone();
      final h = await a.saveHost(Host(name: 'Abbas', phone: '03001234567'));
      await a.saveEvents([ev(hostId: h, topic: 'kept')]);
      await syncPhone(a, cloud);
      await syncPhone(b, cloud);

      await a.deleteHosts([h]);
      await syncPhone(a, cloud);
      await syncPhone(b, cloud);
      for (final db in [a, b]) {
        expect(await db.loadHosts(), isEmpty);
        final e = (await db.loadEvents()).single;
        expect(e.topic, 'kept');
        expect(e.hostId, isNull);
      }
    });

    test('several events delete and change status together', () async {
      final cloud = FakeCloud();
      final a = await phone(), b = await phone();
      await a.saveEvents([ev(topic: '1'), ev(topic: '2'), ev(topic: '3')]);
      final ids = [for (final e in await a.loadEvents()) e.id!];
      await a.setStatus(ids.sublist(0, 2), EventStatus.cancelled);
      await a.deleteEvents([ids[2]]);
      await syncPhone(a, cloud);
      await syncPhone(b, cloud);
      final onB = await b.loadEvents();
      expect(onB.map((e) => e.topic), unorderedEquals(['1', '2']));
      expect(onB.every((e) => e.status == EventStatus.cancelled), isTrue);
    });
  });
}
