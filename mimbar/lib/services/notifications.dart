import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class Reminder {
  final int id;
  final int eventId;
  final DateTime when;
  final String title;
  final String body;

  Reminder({
    required this.id,
    required this.eventId,
    required this.when,
    required this.title,
    required this.body,
  });
}

/// Offline local notifications. Alarms are held by Android, so they fire with
/// the app closed, and the plugin's boot receiver restores them after reboot.
class Notifs {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'event_reminders',
      'Event reminders',
      channelDescription: 'Reminders before majalis, milad and nikkah',
      importance: Importance.high,
      priority: Priority.high,
      // Full-colour minbar inside the notification card; the status bar
      // uses the single-colour outline (ic_stat_mimbar).
      largeIcon: DrawableResourceAndroidBitmap('notif_large'),
    ),
  );

  static Future<void> init({required void Function(int eventId) onTap}) async {
    tzdata.initializeTimeZones();
    try {
      final name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Asia/Karachi'));
    }

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_stat_mimbar'),
      ),
      onDidReceiveNotificationResponse: (r) {
        final id = int.tryParse(r.payload ?? '');
        if (id != null) onTap(id);
      },
    );
    _ready = true;
  }

  /// Android 13+ asks the user once; later calls return immediately.
  static Future<void> requestPermission() async {
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  /// Event id of the notification that cold-started the app, if any.
  static Future<int?> launchEventId() async {
    final d = await _plugin.getNotificationAppLaunchDetails();
    if (d == null || !d.didNotificationLaunchApp) return null;
    return int.tryParse(d.notificationResponse?.payload ?? '');
  }

  static Future<void> reschedule(List<Reminder> items) async {
    if (!_ready) return;
    await _plugin.cancelAll();
    for (final r in items) {
      await _plugin.zonedSchedule(
        id: r.id,
        title: r.title,
        body: r.body,
        scheduledDate: tz.TZDateTime.from(r.when, tz.local),
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: '${r.eventId}',
      );
    }
  }
}
