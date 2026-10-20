import Flutter
import UIKit
import UserNotifications
import flutter_local_notifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var notificationDiagnosticsChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: "daily_thesis/notification_diagnostics",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "logNotificationState" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.logNotificationState()
      result(nil)
    }
    notificationDiagnosticsChannel = channel
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    logNotificationState()
  }

  private func logNotificationState() {
    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { settings in
      NSLog(
        "[DailyReminderDiag] SETTINGS authorization=%ld alert=%ld sound=%ld badge=%ld",
        settings.authorizationStatus.rawValue,
        settings.alertSetting.rawValue,
        settings.soundSetting.rawValue,
        settings.badgeSetting.rawValue
      )
    }

    center.getPendingNotificationRequests { requests in
      for request in requests {
        if let trigger = request.trigger as? UNCalendarNotificationTrigger {
          NSLog(
            "[DailyReminderDiag] PENDING id=%@ repeats=%d components=%@ next=%@",
            request.identifier,
            trigger.repeats ? 1 : 0,
            String(describing: trigger.dateComponents),
            String(describing: trigger.nextTriggerDate())
          )
        } else {
          NSLog(
            "[DailyReminderDiag] PENDING id=%@ trigger=%@",
            request.identifier,
            String(describing: request.trigger)
          )
        }
      }
    }

    center.getDeliveredNotifications { notifications in
      let identifiers = notifications.map { $0.request.identifier }.joined(separator: ",")
      NSLog("[DailyReminderDiag] DELIVERED ids=%@", identifiers)
    }
  }
}
