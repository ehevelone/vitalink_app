import UIKit
import Flutter
import Firebase
import FirebaseMessaging
import EventKit
import EventKitUI
import Security
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, MessagingDelegate, EKEventEditViewDelegate {
  private let eventStore = EKEventStore()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    FirebaseApp.configure()
    migrateVitaLinkKeychainToDeviceOnly()
    excludeVitaLinkDataFromBackup()

    UNUserNotificationCenter.current().delegate = self
    Messaging.messaging().delegate = self

    // 🔥 Request system notification permission at native level
    UNUserNotificationCenter.current().requestAuthorization(
      options: [.alert, .badge, .sound]
    ) { granted, error in
      _ = granted
      _ = error
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
    _ = error
  }

  func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
    _ = fcmToken
  }
  private func excludeVitaLinkDataFromBackup() {
    let fileManager = FileManager.default
    let directories: [FileManager.SearchPathDirectory] = [
      .documentDirectory,
      .libraryDirectory,
      .applicationSupportDirectory
    ]

    for directory in directories {
      guard let url = fileManager.urls(for: directory, in: .userDomainMask).first else {
        continue
      }
      if !fileManager.fileExists(atPath: url.path) {
        try? fileManager.createDirectory(
          at: url,
          withIntermediateDirectories: true,
          attributes: nil
        )
      }
      var excludedUrl = url
      try? excludedUrl.setResourceValue(true, forKey: .isExcludedFromBackupKey)
    }
  }

  private func migrateVitaLinkKeychainToDeviceOnly() {
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: "flutter_secure_storage_service",
      kSecAttrAccessible: kSecAttrAccessibleWhenUnlocked
    ]
    let update: [CFString: Any] = [
      kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    ]
    _ = SecItemUpdate(query as CFDictionary, update as CFDictionary)
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
