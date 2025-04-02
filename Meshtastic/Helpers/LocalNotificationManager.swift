import Foundation
import SwiftUI
import OSLog

class LocalNotificationManager {

    var notifications = [Notification]()
	let thumbsUpAction = UNNotificationAction(identifier: "messageNotification.thumbsUpAction", title: "👍 \(Tapbacks.thumbsUp.description)", options: [])
	let thumbsDownAction = UNNotificationAction(identifier: "messageNotification.thumbsDownAction", title: "👎  \(Tapbacks.thumbsDown.description)", options: [])
	let replyInputAction =  UNTextInputNotificationAction(identifier: "messageNotification.replyInputAction", title: "Reply".localized, options: [])

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
		let messageNotificationCategory = UNNotificationCategory(
				 identifier: "messageNotificationCategory",
				 actions: [thumbsUpAction, thumbsDownAction, replyInputAction],
				 intentIdentifiers: [],
				 options: .customDismissAction
				)

				UNUserNotificationCenter.current().setNotificationCategories([messageNotificationCategory])

        for notification in notifications {
            let content = UNMutableNotificationContent()
            content.subtitle = notification.subtitle
            content.title = notification.title
            content.body = notification.content
            content.sound = .default
            content.interruptionLevel = .timeSensitive

			if notification.target != nil {
				content.userInfo["target"] = notification.target
			}
			if notification.path != nil {
				content.userInfo["path"] = notification.path
			}
			if notification.messageId != nil {
				content.categoryIdentifier = "messageNotificationCategory"
				content.userInfo["messageId"] = notification.messageId
			}
			if notification.channel != nil {
				content.userInfo["channel"] = notification.channel
			}
			if notification.userNum != nil {
				content.userInfo["userNum"] = notification.userNum
			}
			if notification.critical {
				content.sound = UNNotificationSound.defaultCritical
			}

            let request = UNNotificationRequest(identifier: notification.id, content: content, trigger: nil)

            UNUserNotificationCenter.current().add(request) { error in
				if let error {
					Logger.services.error("Error Scheduling Notification: \(error.localizedDescription, privacy: .public)")
				}
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
	var messageId: Int64?
	var channel: Int32?
	var userNum: Int64?
	var critical: Bool = false
}
