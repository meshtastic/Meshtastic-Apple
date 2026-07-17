// MARK: - FirmwareUpdateNotifier

import Foundation
import OSLog
import SwiftData

struct FirmwareUpdateNotificationCandidate {
	let nodeNum: Int64
	let deviceName: String?
	let platformioTarget: String?
	let installMethod: FirmwareUpdateInstallMethod
	let currentVersion: String?
	let latestStableVersion: String?
}

struct FirmwareUpdateNotificationSource {
	let nodeNum: Int64
	let deviceName: String?
	let platformioTarget: String?
	let architecture: String?
	let metadataVersion: String?
	let connectedVersion: String?
	let latestStableVersion: String?
}

struct FirmwareUpdateNotice: Equatable {
	static let symbolName = "arrow.triangle.2.circlepath"

	let notificationKey: String
	let deviceName: String
	let currentVersion: String
	let latestStableVersion: String
	let installMethod: FirmwareUpdateInstallMethod

	var notificationContent: String {
		switch installMethod {
		case .appOTA:
			return "\(deviceName) is running \(currentVersion). Stable \(latestStableVersion) is available in Firmware Updates."
		case .flasher:
			return "\(deviceName) is running \(currentVersion). Stable \(latestStableVersion) is available. Use Meshtastic Flasher to update this hardware."
		}
	}

	var connectMessage: String {
		switch installMethod {
		case .appOTA:
			return "\(currentVersion) is behind stable \(latestStableVersion). Open Firmware Updates when you're ready."
		case .flasher:
			return "\(currentVersion) is behind stable \(latestStableVersion). Use Meshtastic Flasher for this hardware."
		}
	}

	var actionTarget: String {
		switch installMethod {
		case .appOTA:
			return FirmwareUpdateNotifier.target
		case .flasher:
			return FirmwareUpdateNotifier.flasherTarget
		}
	}

	var actionPath: String {
		switch installMethod {
		case .appOTA:
			return FirmwareUpdateNotifier.path
		case .flasher:
			return FirmwareUpdateNotifier.flasherPath
		}
	}

	var actionURL: URL? {
		URL(string: actionPath)
	}

	var accessibilityHint: String {
		switch installMethod {
		case .appOTA:
			return "Opens Firmware Updates"
		case .flasher:
			return "Opens Meshtastic Flasher"
		}
	}
}

enum FirmwareUpdateNotifier {
	static let target = "firmwareUpdates"
	static let path = "meshtastic:///settings/firmwareUpdates"
	static let flasherTarget = "flasher"
	static let flasherPath = "https://flasher.meshtastic.org"
	private static let staleFirmwareAPIInterval: TimeInterval = 24 * 60 * 60
	private static let refreshTimeoutSeconds: TimeInterval = 15

	static func candidate(from source: FirmwareUpdateNotificationSource) -> FirmwareUpdateNotificationCandidate {
		FirmwareUpdateNotificationCandidate(
			nodeNum: source.nodeNum,
			deviceName: source.deviceName,
			platformioTarget: source.platformioTarget,
			installMethod: FirmwareUpdateNotificationPolicy.installMethod(architecture: source.architecture),
			currentVersion: source.metadataVersion?.isEmpty == false ? source.metadataVersion : source.connectedVersion,
			latestStableVersion: source.latestStableVersion
		)
	}

	static func notice(for candidate: FirmwareUpdateNotificationCandidate) -> FirmwareUpdateNotice? {
		guard let platformioTarget = candidate.platformioTarget,
		      let currentVersion = candidate.currentVersion,
		      let latestStableVersion = candidate.latestStableVersion,
		      FirmwareUpdateNotificationPolicy.isUpdateAvailable(current: currentVersion, latestStable: latestStableVersion) else {
			return nil
		}

		let key = FirmwareUpdateNotificationPolicy.notificationKey(
			nodeNum: candidate.nodeNum,
			platformioTarget: platformioTarget,
			latestStableVersion: latestStableVersion
		)
		let displayName: String
		if let trimmedName = candidate.deviceName?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmedName.isEmpty {
			displayName = trimmedName
		} else {
			displayName = "Connected node"
		}
		let current = FirmwareUpdateNotificationPolicy.normalizedVersion(currentVersion)
		let latest = FirmwareUpdateNotificationPolicy.normalizedVersion(latestStableVersion)

		return FirmwareUpdateNotice(
			notificationKey: key,
			deviceName: displayName,
			currentVersion: current,
			latestStableVersion: latest,
			installMethod: candidate.installMethod
		)
	}

	static func notification(
		for candidate: FirmwareUpdateNotificationCandidate,
		alreadyNotified: Set<String>
	) -> Notification? {
		guard let notice = notice(for: candidate),
		      !alreadyNotified.contains(notice.notificationKey) else {
			return nil
		}

		return Notification(
			id: notice.notificationKey,
			title: "Firmware update available",
			subtitle: notice.deviceName,
			content: notice.notificationContent,
			target: notice.actionTarget,
			path: notice.actionPath
		)
	}

	@MainActor
	static func notifyIfNeeded(accessoryManager: AccessoryManager) async {
		await refreshFirmwareDataIfStale()
		guard !Task.isCancelled else { return }

		guard let candidate = candidate(accessoryManager: accessoryManager),
		      let notification = notification(
			      for: candidate,
			      alreadyNotified: UserDefaults.firmwareUpdateNotificationKeySet
		) else {
			return
		}
		guard !Task.isCancelled else { return }

		let localNotificationManager = LocalNotificationManager()
		localNotificationManager.notifications = [notification]
		localNotificationManager.schedule()
		UserDefaults.recordFirmwareUpdateNotificationKey(notification.id)
	}

	@MainActor
	static func notice(accessoryManager: AccessoryManager) -> FirmwareUpdateNotice? {
		guard let candidate = candidate(accessoryManager: accessoryManager) else { return nil }
		return notice(for: candidate)
	}

	@MainActor
	private static func refreshFirmwareDataIfStale() async {
		guard UserDefaults.lastFirmwareAPIUpdate == .distantPast
			|| abs(UserDefaults.lastFirmwareAPIUpdate.timeIntervalSinceNow) > staleFirmwareAPIInterval else {
			return
		}

		let timeoutSeconds = Self.refreshTimeoutSeconds
		do {
			try await withThrowingTaskGroup(of: Void.self) { group in
				group.addTask {
					try await MeshtasticAPI.shared.refreshFirmwareAPIData()
				}
				group.addTask {
					try await Task.sleep(for: .seconds(timeoutSeconds))
					throw MeshtasticAPI.MeshtasticAPIError.timedOut(timeoutSeconds)
				}

				defer { group.cancelAll() }
				try await group.next()
			}
		} catch is CancellationError {
			Logger.services.debug("Cancelled firmware data refresh before update notification check")
		} catch {
			Logger.services.warning("Failed to refresh firmware data before update notification check: \(error.localizedDescription, privacy: .public)")
		}
	}

	@MainActor
	private static func candidate(accessoryManager: AccessoryManager) -> FirmwareUpdateNotificationCandidate? {
		guard let nodeNum = accessoryManager.activeDeviceNum,
		      let node = getNodeInfo(id: nodeNum, context: accessoryManager.context),
		      let platformioTarget = node.myInfo?.pioEnv,
		      let hardware = hardware(platformioTarget: platformioTarget, context: accessoryManager.context) else {
			return nil
		}

		return candidate(from: FirmwareUpdateNotificationSource(
			nodeNum: node.num,
			deviceName: node.user?.longName ?? accessoryManager.activeConnection?.device.longName ?? accessoryManager.activeConnection?.device.name,
			platformioTarget: platformioTarget,
			architecture: hardware.architecture,
			metadataVersion: node.metadata?.firmwareVersion,
			connectedVersion: accessoryManager.connectedVersion,
			latestStableVersion: latestStableFirmwareVersion(context: accessoryManager.context)
		))
	}

	@MainActor
	private static func hardware(platformioTarget: String, context: ModelContext) -> DeviceHardwareEntity? {
		var descriptor = FetchDescriptor<DeviceHardwareEntity>(
			predicate: #Predicate { $0.platformioTarget == platformioTarget }
		)
		descriptor.fetchLimit = 1
		do {
			return try context.fetch(descriptor).first
		} catch {
			Logger.services.warning("Failed to fetch hardware for firmware update notification target \(platformioTarget, privacy: .public): \(error.localizedDescription, privacy: .public)")
			return nil
		}
	}

	@MainActor
	private static func latestStableFirmwareVersion(context: ModelContext) -> String? {
		let stableRawValue = ReleaseType.stable.rawValue
		var descriptor = FetchDescriptor<FirmwareReleaseEntity>(
			predicate: #Predicate { $0.releaseType == stableRawValue },
			sortBy: [
				SortDescriptor(\.versionMajor, order: .reverse),
				SortDescriptor(\.versionMinor, order: .reverse),
				SortDescriptor(\.versionPatch, order: .reverse)
			]
		)
		descriptor.fetchLimit = 1
		do {
			return try context.fetch(descriptor).first?.versionId
		} catch {
			Logger.services.warning("Failed to fetch latest stable firmware release for update notification: \(error.localizedDescription, privacy: .public)")
			return nil
		}
	}
}
