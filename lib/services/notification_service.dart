import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

/// Must be a top-level function (not a class method) — FCM calls this
/// in a separate isolate when a push arrives while the app is fully
/// terminated (not just backgrounded).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('Background push received: ${message.messageId}');
}

/// Centralizes push notification setup: permission request, FCM token
/// retrieval, registering that token (plus the user's subject
/// interests) with the Worker under this install's device ID, and
/// displaying a banner when a push arrives while the app is open (FCM
/// doesn't do this automatically on Android).
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  // Same Worker used by PaperService — kept as its own constant here so
  // this file doesn't take on a dependency on paper_service.dart.
  static const String _workerUrl =
      'https://quiet-bread-7971.li231sdyt.workers.dev/';

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  String? _fcmToken;
  String? get fcmToken => _fcmToken;

  String? _userId;
  List<String> _subjects = const [];

  static const _channel = AndroidNotificationChannel(
    'daily_thesis_default',
    'Daily Thesis Notifications',
    description: 'New paper recommendations and app updates',
    importance: Importance.high,
  );

  /// [userId] should be a stable per-install identifier (see
  /// DeviceIdService.getOrCreate). [subjects] should be the user's
  /// current `UserProfile.matchedSubjects` — pass an empty list if
  /// onboarding hasn't completed yet, the Worker falls back to a
  /// generic subject in that case.
  Future<void> initialize(
    String userId, {
    List<String> subjects = const [],
  }) async {
    _userId = userId;
    _subjects = subjects;
    try {
      // iOS/Android 13+ requires explicit permission.
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      debugPrint('Notification permission: ${settings.authorizationStatus}');

      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await _messaging.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      }

      await _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(_channel);

      await _localNotifications.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        ),
      );

      _fcmToken = await _messaging.getToken();
      debugPrint('FCM token: $_fcmToken');
      await _registerToken();

      // Token can rotate (e.g. app reinstall, token expiry) — re-sync
      // to the Worker whenever that happens.
      _messaging.onTokenRefresh.listen((newToken) {
        _fcmToken = newToken;
        debugPrint('FCM token refreshed: $newToken');
        _registerToken();
      });

      // Foreground messages don't show a system banner on Android by
      // default — display one manually via flutter_local_notifications.
      FirebaseMessaging.onMessage.listen(_showForegroundNotification);
    } catch (e) {
      debugPrint('Notification init failed: $e');
    }
  }

  /// Call whenever the user's subject interests change (onboarding
  /// finishing, or Settings being saved) so the Worker's next daily
  /// push reflects the update. Safe to call even if [initialize]
  /// already registered a token — this just re-registers with the new
  /// subject list.
  Future<void> updateSubjects(List<String> subjects) async {
    _subjects = subjects;
    await _registerToken();
  }

  /// POSTs the current userId + FCM token + subjects to the Worker's
  /// /register-token endpoint. Safe to call repeatedly — the Worker
  /// overwrites the stored record for this userId each time.
  Future<void> _registerToken() async {
    final userId = _userId;
    final token = _fcmToken;
    if (userId == null || token == null) return;

    try {
      final response = await http
          .post(
            Uri.parse('${_workerUrl}register-token'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'userId': userId,
              'fcmToken': token,
              'subjects': _subjects,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        debugPrint('Push token registered for $userId (subjects: $_subjects)');
      } else {
        debugPrint(
          'register-token failed: ${response.statusCode} ${response.body}',
        );
      }
    } catch (e) {
      // Non-fatal — push just won't work until the next successful
      // registration attempt (next app open or token refresh).
      debugPrint('register-token error: $e');
    }
  }

  void _showForegroundNotification(RemoteMessage message) {
    // iOS displays foreground alerts through the presentation options set
    // during initialization. The Android local notification path below would
    // otherwise duplicate the alert on iPhone.
    if (defaultTargetPlatform == TargetPlatform.iOS) return;

    final notification = message.notification;
    if (notification == null) return;

    _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
  }
}
