import UIKit
import Flutter
import Firebase
import FirebaseMessaging
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    FirebaseApp.configure()

    // 🔥 REQUIRED FOR iOS PUSH
    UNUserNotificationCenter.current().delegate = self
    Messaging.messaging().delegate = self

    application.registerForRemoteNotifications()

    GeneratedPluginRegistrant.register(with: self)

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {

    // 🔥 REQUIRED
    Messaging.messaging().setAPNSToken(deviceToken, type: .unknown)

    super.application(application,
                      didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
    print("🔥 FCM TOKEN: \(String(describing: fcmToken))")
  }
}