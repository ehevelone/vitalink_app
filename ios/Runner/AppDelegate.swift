import UIKit
import Flutter
import Firebase
import FirebaseMessaging
import EventKit
import EventKitUI
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, MessagingDelegate, EKEventEditViewDelegate {
  private let eventStore = EKEventStore()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    FirebaseApp.configure()

    UNUserNotificationCenter.current().delegate = self
    Messaging.messaging().delegate = self

    // 🔥 Request system notification permission at native level
    UNUserNotificationCenter.current().requestAuthorization(
      options: [.alert, .badge, .sound]
    ) { granted, error in
      print("🔔 Permission granted: \(granted)")
      if let error = error {
        print("❌ Permission error: \(error)")
      }
    }

    application.registerForRemoteNotifications()

    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let calendarChannel = FlutterMethodChannel(
        name: "com.etnaturals.vitalinkapp/calendar",
        binaryMessenger: controller.binaryMessenger
      )

      calendarChannel.setMethodCallHandler { [weak self] call, result in
        guard call.method == "insertEvent" else {
          result(FlutterMethodNotImplemented)
          return
        }

        self?.openCalendarEvent(arguments: call.arguments, result: result)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {

    print("🔥 APNs DEVICE TOKEN RECEIVED")

    Messaging.messaging().setAPNSToken(deviceToken, type: .unknown)

    super.application(
      application,
      didRegisterForRemoteNotificationsWithDeviceToken: deviceToken
    )
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    print("❌ FAILED TO REGISTER FOR APNs: \(error)")
  }

  func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
    print("🔥 FCM TOKEN: \(String(describing: fcmToken))")
  }
  private func openCalendarEvent(arguments: Any?, result: @escaping FlutterResult) {
    guard
      let args = arguments as? [String: Any],
      let startMillis = args["startMillis"] as? NSNumber,
      let endMillis = args["endMillis"] as? NSNumber
    else {
      result(false)
      return
    }

    let presentEditor = {
      DispatchQueue.main.async {
        let event = EKEvent(eventStore: self.eventStore)
        event.title = args["title"] as? String ?? "VitaLink Appointment"
        event.notes = args["description"] as? String ?? ""
        event.startDate = Date(timeIntervalSince1970: startMillis.doubleValue / 1000.0)
        event.endDate = Date(timeIntervalSince1970: endMillis.doubleValue / 1000.0)
        event.calendar = self.eventStore.defaultCalendarForNewEvents

        let editor = EKEventEditViewController()
        editor.eventStore = self.eventStore
        editor.event = event
        editor.editViewDelegate = self

        self.window?.rootViewController?.present(editor, animated: true)
        result(true)
      }
    }

    if #available(iOS 17.0, *) {
      eventStore.requestFullAccessToEvents { granted, _ in
        granted ? presentEditor() : result(false)
      }
    } else {
      eventStore.requestAccess(to: .event) { granted, _ in
        granted ? presentEditor() : result(false)
      }
    }
  }

  func eventEditViewController(
    _ controller: EKEventEditViewController,
    didCompleteWith action: EKEventEditViewAction
  ) {
    controller.dismiss(animated: true)
  }
}
