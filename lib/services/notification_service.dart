import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

class DailyReminderSettings {
  final bool enabled;
  final int hour;
  final int minute;

  const DailyReminderSettings({
    required this.enabled,
    required this.hour,
    required this.minute,
  });

  DateTime get time => DateTime(2000, 1, 1, hour, minute);
}

/// Manages an optional daily local reminder. Local scheduling keeps the
/// reminder in the device's timezone and does not depend on the Worker cron.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const _enabledKey = 'daily_reminder_enabled_v1';
  static const _hourKey = 'daily_reminder_hour_v1';
  static const _minuteKey = 'daily_reminder_minute_v1';
  static const _notificationId = 7301;
  static const _channel = AndroidNotificationChannel(
    'daily_thesis_reminder',
    'Daily paper reminder',
    description: 'A reminder to read your daily research paper',
    importance: Importance.defaultImportance,
  );

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<DailyReminderSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return DailyReminderSettings(
      enabled: prefs.getBool(_enabledKey) ?? false,
      hour: prefs.getInt(_hourKey) ?? 9,
      minute: prefs.getInt(_minuteKey) ?? 0,
    );
  }

  Future<bool> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    if (!enabled) {
      if (!kIsWeb) {
        await _initialize();
        await _notifications.cancel(_notificationId);
      }
      await prefs.setBool(_enabledKey, false);
      return true;
    }

    if (kIsWeb ||
        !(defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      return false;
    }

    try {
      await _initialize();
      final granted = await _requestPermission();
      if (!granted) return false;

      final settings = await loadSettings();
      await _schedule(settings.hour, settings.minute);
      await prefs.setBool(_enabledKey, true);
      return true;
    } catch (error) {
      debugPrint('Could not schedule daily reminder: $error');
      return false;
    }
  }

  Future<void> setTime(int hour, int minute) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_hourKey, hour);
    await prefs.setInt(_minuteKey, minute);
    if (prefs.getBool(_enabledKey) ?? false) {
      await _initialize();
      await _schedule(hour, minute);
    }
  }

  Future<void> _initialize() async {
    if (_initialized) return;
    await _notifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
    );
    await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_channel);
    tz_data.initializeTimeZones();
    final timezoneInfo = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timezoneInfo.identifier));
    _initialized = true;
  }

  Future<bool> _requestPermission() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (await android?.areNotificationsEnabled() ?? false) return true;
      return await android?.requestNotificationsPermission() ?? true;
    }
    final ios = _notifications
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    final status = await ios?.checkPermissions();
    if (status?.isEnabled ?? false) return true;
    return await ios?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        ) ??
        true;
  }

  Future<void> _schedule(int hour, int minute) async {
    final now = tz.TZDateTime.now(tz.local);
    var next = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (!next.isAfter(now)) {
      next = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day + 1,
        hour,
        minute,
      );
    }

    await _notifications.zonedSchedule(
      _notificationId,
      'Your daily paper is ready',
      'Take a few minutes to explore today’s research recommendation.',
      next,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_thesis_reminder',
          'Daily paper reminder',
          channelDescription: 'A reminder to read your daily research paper',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBanner: true,
          presentList: true,
          presentSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.wallClockTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }
}
