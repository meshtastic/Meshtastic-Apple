// MARK: - FirmwareUpdateNotificationPolicy

import Foundation

enum FirmwareUpdateInstallMethod: Equatable {
	case appOTA
	case flasher
}

enum FirmwareUpdateNotificationPolicy {
	static func installMethod(architecture: String?) -> FirmwareUpdateInstallMethod {
		guard let architecture = architecture.flatMap({ Architecture(rawValue: $0) }) else {
			return .flasher
		}

		switch architecture {
		case .esp32, .esp32C3, .esp32S3, .esp32C6, .nrf52840:
			return .appOTA
		case .rp2040:
			return .flasher
		}
	}

	static func normalizedVersion(_ version: String) -> String {
		let trimmedVersion = version.trimmingCharacters(in: .whitespacesAndNewlines)
		let cleanVersion = trimmedVersion.hasPrefix("v") ? String(trimmedVersion.dropFirst()) : trimmedVersion
		let parts = cleanVersion.split(separator: ".")
		guard parts.count >= 3 else { return cleanVersion }
		return parts.prefix(3).joined(separator: ".")
	}

	static func isUpdateAvailable(current: String, latestStable: String) -> Bool {
		let currentVersion = normalizedVersion(current)
		let latestStableVersion = normalizedVersion(latestStable)
		return currentVersion.compare(latestStableVersion, options: .numeric) == .orderedAscending
	}

	static func notificationKey(
		nodeNum: Int64,
		platformioTarget: String,
		latestStableVersion: String
	) -> String {
		"firmware-update-notified:\(nodeNum):\(platformioTarget):\(normalizedVersion(latestStableVersion))"
	}

	static func shouldNotify(
		nodeNum: Int64,
		platformioTarget: String,
		currentVersion: String,
		latestStableVersion: String,
		alreadyNotified: Set<String>
	) -> Bool {
		guard isUpdateAvailable(current: currentVersion, latestStable: latestStableVersion) else {
			return false
		}

		let key = notificationKey(
			nodeNum: nodeNum,
			platformioTarget: platformioTarget,
			latestStableVersion: latestStableVersion
		)
		return !alreadyNotified.contains(key)
	}
}
