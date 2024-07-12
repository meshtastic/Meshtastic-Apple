import Foundation
import SwiftUI
import OSLog

class LocalNotificationManager {

    var notifications = [Notification]()

    // Step 1 Request Permissions for notifications
    private func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in

            if granted == true && error == nil {
				self.scheduleNotifications()
            }
        }
    }

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

    // This function iterates over the Notification objects in the notifications array and schedules them for delivery in the future
    private func scheduleNotifications() {
        for notification in notifications {
            let content = UNMutableNotificationContent()
            content.subtitle = notification.subtitle
            content.title = notification.title
            content.body = notification.content
            content.sound = .default
            content.interruptionLevel = .timeSensitive

			if notification.target != nil {
				content.userInfo["target"]  = notification.target
			}
			if notification.path != nil {
				content.userInfo["path"]  = notification.path
			}

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            let request = UNNotificationRequest(identifier: notification.id, content: content, trigger: trigger)

            UNUserNotificationCenter.current().add(request) { error in

                guard error == nil else { return }
            }
        }
    }

    // Check and debug what local notifications have been scheduled
    func listScheduledNotifications() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { notifications in

            for notification in notifications {
				Logger.services.debug("\(notification, privacy: .public)")
            }
        }
    }

}

struct Notification {
    var id: String
    var title: String
    var subtitle: String
    var content: String
	var target: String?
	var path: String?
}
