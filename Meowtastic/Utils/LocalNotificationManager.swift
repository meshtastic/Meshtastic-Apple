import Foundation
import OSLog
import SwiftUI

final class LocalNotificationManager {
	var notifications = [Notification]()

	func schedule() {
		UNUserNotificationCenter.current().getNotificationSettings { settings in
			switch settings.authorizationStatus {
			case .notDetermined:
				self.requestAuthorization()

			case .authorized, .provisional:
				self.scheduleNotifications()

			default:
				break // Do nothing
			}
		}
	}

	private func requestAuthorization() {
		UNUserNotificationCenter.current().requestAuthorization(
			options: [.alert, .badge, .sound]
		) { granted, error in
			guard granted, error == nil else {
				return
			}

			self.scheduleNotifications()
		}
	}

	private func scheduleNotifications() {
		for notification in notifications {
			let content = UNMutableNotificationContent()
			content.subtitle = notification.subtitle
			content.title = notification.title
			content.body = notification.content
			content.sound = .default
			content.interruptionLevel = .timeSensitive

			if let target = notification.target {
				content.userInfo["target"] = target
			}
			if let path = notification.path {
				content.userInfo["path"] = path
			}

			let trigger = UNTimeIntervalNotificationTrigger(
				timeInterval: 1,
				repeats: false
			)
			let request = UNNotificationRequest(
				identifier: notification.id,
				content: content,
				trigger: trigger
			)

			UNUserNotificationCenter.current().add(request)
		}
	}
}
