//
//  MeshtasticAppDelegate.swift
//  Meshtastic
//
//  Created by Ben on 8/20/23.
//

import SwiftUI
import OSLog

class MeowtasticAppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate, ObservableObject {
	func application(
		_ application: UIApplication,
		didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
	) -> Bool {
		Logger.services.info("🚀 [App] Meshtstic Apple App launched!")

		// Default User Default Values
		UserDefaults.standard.register(defaults: ["meshMapRecentering": true])
		UserDefaults.standard.register(defaults: ["meshMapShowNodeHistory": true])
		UserDefaults.standard.register(defaults: ["meshMapShowRouteLines": true])

		UNUserNotificationCenter.current().delegate = self

		let locationsHandler = LocationsHandler.shared
		locationsHandler.startLocationUpdates()

		// If a background activity session was previously active, reinstantiate it after the background launch.
		if locationsHandler.backgroundActivity {
			locationsHandler.backgroundActivity = true
		}

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
			AppState.shared.tabSelection = Tab.map
		} else if targetValue == "messages" {
			AppState.shared.tabSelection = Tab.messages
		} else if targetValue == "nodes" {
			AppState.shared.tabSelection = Tab.nodes
		}

		completionHandler()
	}
}
