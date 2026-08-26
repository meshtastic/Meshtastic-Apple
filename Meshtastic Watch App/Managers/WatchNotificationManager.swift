//
//  WatchNotificationManager.swift
//  Meshtastic Watch App
//
//  Copyright(c) Meshtastic 2025.
//

import Foundation
import UserNotifications
import os

/// Declares this target as a notification-capable watchOS app.
///
/// The Watch app posts no notifications of its own. Every Meshtastic alert felt on the
/// wrist is an iPhone notification that watchOS mirrored, and no API opts a notification
/// out of that mirroring — so the user's only control is the per-app entry under
/// Watch → Notifications (Custom → Notifications Off).
///
/// Earning that entry is the whole point of this type. Watch → Notifications lists apps in
/// two sections: apps with a watchOS app, and "Mirror iPhone Alerts From" for iPhone-only
/// apps. Shipping a companion Watch app excludes Meshtastic from the second section, and
/// while this target requested no notification authorization it earned no place in the
/// first — leaving alerts arriving on the wrist with no switch in either section to stop
/// them, and removing the Watch app no help because mirroring does not depend on it.
///
/// Deliberately narrow: authorization and foreground presentation only. No
/// `UNNotificationCategory` is registered here. The categories and actions belong to the
/// iOS app (`LocalNotificationManager`), which is also what handles a tapback or reply
/// chosen from a mirrored notification; registering the same identifier on this side
/// risks shadowing that.
@MainActor
final class WatchNotificationManager: NSObject, ObservableObject {

	/// Authorization status surfaced to the UI, mirroring `WatchLocationManager`.
	@Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

	private let logger = Logger(subsystem: "gvh.MeshtasticClient.watchkitapp", category: "🔔 Notifications")

	// MARK: - Lifecycle

	override init() {
		super.init()
		UNUserNotificationCenter.current().delegate = self
	}

	// MARK: - Public API

	/// Ask for notification authorization, but only when the user has not already been
	/// asked. Same shape as the iOS app's `LocalNotificationManager.schedule()`: read the
	/// current settings first and prompt only on `.notDetermined`, so an existing decision
	/// — in either direction — is never re-prompted.
	func requestAuthorizationIfNeeded() async {
		let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
		authorizationStatus = status

		guard status == .notDetermined else {
			logger.info("Notification authorization already decided (status=\(status.rawValue))")
			return
		}

		do {
			let granted = try await UNUserNotificationCenter.current()
				.requestAuthorization(options: [.alert, .badge, .sound])
			authorizationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
			logger.info("Notification authorization granted: \(granted)")
		} catch {
			logger.error("Error requesting notification authorization: \(error.localizedDescription, privacy: .public)")
		}
	}
}

// MARK: - UNUserNotificationCenterDelegate
extension WatchNotificationManager: UNUserNotificationCenterDelegate {

	/// Show mirrored alerts while the Watch app itself is frontmost. Without this the
	/// system suppresses them, so a message arriving while the user is on the foxhunt
	/// compass would be silently dropped rather than banner-ed.
	nonisolated func userNotificationCenter(
		_ center: UNUserNotificationCenter,
		willPresent notification: UNNotification
	) async -> UNNotificationPresentationOptions {
		[.banner, .sound, .list]
	}
}
