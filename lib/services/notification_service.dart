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
  static const _reminderNotificationCount = 60;
  static const _testNotificationId = 7399;
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
        await _cancelReminderNotifications();
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

  Future<void> refreshScheduleIfNeeded() async {
    final settings = await loadSettings();
    if (!settings.enabled || kIsWeb) return;

    try {
      await _initialize();
      final pending = await _notifications.pendingNotificationRequests();
      final pendingReminderCount = pending
          .where(
            (request) =>
                request.id >= _notificationId &&
                request.id < _notificationId + _reminderNotificationCount,
          )
          .length;
      if (pendingReminderCount >= _reminderNotificationCount ~/ 2) return;
      await _schedule(settings.hour, settings.minute);
    } catch (error) {
      debugPrint('Could not refresh daily reminders: $error');
    }
  }

  Future<void> sendTestNotification() async {
    await _initialize();
    final scheduledAt = tz.TZDateTime.now(
      tz.local,
    ).add(const Duration(seconds: 10));
    await _notifications.zonedSchedule(
      _testNotificationId,
      'Daily Thesis test notification',
      'Notifications are working on this device.',
      scheduledAt,
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
    );

    final pending = await _notifications.pendingNotificationRequests();
    if (!pending.any((request) => request.id == _testNotificationId)) {
      throw StateError(
        'The operating system did not retain the test notification.',
      );
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
    await _cancelReminderNotifications();

    final now = tz.TZDateTime.now(tz.local);
    final today = DateTime(now.year, now.month, now.day);
    final todayAtReminderTime = tz.TZDateTime(
      tz.local,
      today.year,
      today.month,
      today.day,
      hour,
      minute,
    );
    final firstDayOffset = todayAtReminderTime.isAfter(now) ? 0 : 1;
    final firstCalendarDate = DateTime(
      today.year,
      today.month,
      today.day + firstDayOffset,
    );
    final firstScheduledDate = tz.TZDateTime(
      tz.local,
      firstCalendarDate.year,
      firstCalendarDate.month,
      firstCalendarDate.day,
      hour,
      minute,
    );

    for (var day = 0; day < _reminderNotificationCount; day++) {
      final calendarDate = DateTime(
        firstCalendarDate.year,
        firstCalendarDate.month,
        firstCalendarDate.day + day,
      );
      final scheduledDate = tz.TZDateTime(
        tz.local,
        calendarDate.year,
        calendarDate.month,
        calendarDate.day,
        hour,
        minute,
      );

      await _notifications.zonedSchedule(
        _notificationId + day,
        'Your daily paper is ready',
        'Take a few minutes to explore today’s research recommendation.',
        scheduledDate,
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
      );
    }

    final pending = await _notifications.pendingNotificationRequests();
    final pendingReminderCount = pending
        .where(
          (request) =>
              request.id >= _notificationId &&
              request.id < _notificationId + _reminderNotificationCount,
        )
        .length;
    if (pendingReminderCount != _reminderNotificationCount) {
      throw StateError(
        'The operating system retained $pendingReminderCount of '
        '$_reminderNotificationCount daily reminders.',
      );
    }
    debugPrint(
      'Daily reminders scheduled from ${firstScheduledDate.toLocal()} '
      '(${tz.local.name}); pending daily reminders: $pendingReminderCount',
    );
  }

  Future<void> _cancelReminderNotifications() async {
    for (var day = 0; day < _reminderNotificationCount; day++) {
      await _notifications.cancel(_notificationId + day);
    }
  }
}
