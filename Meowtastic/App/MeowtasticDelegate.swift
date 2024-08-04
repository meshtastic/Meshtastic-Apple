import FirebaseCore
import OSLog
import SwiftUI

final class MeowtasticDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate, ObservableObject {
	func application(
		_ application: UIApplication,
		didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
	) -> Bool {
		Logger.services.info("🚀 [App] Meshtstic Apple App launched!")

		// Default User Default Values
		UserDefaults.standard.register(defaults: ["meshMapRecentering": true])
		UserDefaults.standard.register(defaults: ["meshMapShowNodeHistory": true])

		UNUserNotificationCenter.current().delegate = self

		FirebaseApp.configure()

		return true
	}

	func userNotificationCenter(
		_ center: UNUserNotificationCenter,
		willPresent notification: UNNotification,
		withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
	) {
		completionHandler([.list, .banner, .sound])
	}

	func userNotificationCenter(
		_ center: UNUserNotificationCenter,
		didReceive response: UNNotificationResponse,
		withCompletionHandler completionHandler: @escaping () -> Void
	) {
		let userInfo = response.notification.request.content.userInfo
		let targetValue = userInfo["target"] as? String
		let deepLink = userInfo["path"] as? String

		AppState.shared.navigationPath = deepLink

		if targetValue == "map" {
			AppState.shared.tabSelection = TabTag.map
		}
		else if targetValue == "messages" {
			AppState.shared.tabSelection = TabTag.messages
		}
		else if targetValue == "nodes" {
			AppState.shared.tabSelection = TabTag.nodes
		}

		completionHandler()
	}
}
