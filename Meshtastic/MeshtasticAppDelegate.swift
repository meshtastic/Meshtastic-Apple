//
//  MeshtasticAppDelegate.swift
//  Meshtastic
//
//  Created by Ben on 8/20/23.
//

import SwiftUI

class MeshtasticAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
	
	func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
		print("App launched!")
		UNUserNotificationCenter.current().delegate = self
		return true
	}
	
	func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
	}
		
	// This method is called when user clicked on the notification
	func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void)
	{
		let userInfo = response.notification.request.content.userInfo
		if let targetValue = userInfo["target"] as? String, targetValue == "waypoint"
		{
			openWaypoint()
		}
		
		completionHandler()
	}

	private func openWaypoint()
	{
		AppState.shared.tabSelection = Tab.map
	}
}
