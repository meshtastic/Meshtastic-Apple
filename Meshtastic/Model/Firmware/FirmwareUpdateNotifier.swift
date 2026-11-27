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
			return String(localized: "\(currentVersion) is behind stable \(latestStableVersion).",
						  comment: "Connect screen firmware notice: the radio's firmware version, then the latest stable version")
		case .flasher:
			return String(localized: "\(currentVersion) is behind stable \(latestStableVersion). Use Meshtastic Flasher for this hardware.",
						  comment: "Connect screen firmware notice for radios the app can't update: the radio's firmware version, then the latest stable version")
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
			return String(localized: "Opens Firmware Updates", comment: "VoiceOver hint: tapping this notice opens the Firmware Updates screen")
		case .flasher:
			return String(localized: "Opens Meshtastic Flasher", comment: "VoiceOver hint: tapping this notice opens the Meshtastic Flasher site")
		}
	}
}

/// Everything the Connect screen needs to update the radio itself: the newest stable file
/// for the phone's own update path (Bluetooth DFU zip on nRF52, OTA bin on ESP32) and what
/// the update screen shows about the radio.
struct FirmwareUpdatePlan: Identifiable {
	/// The radio the file was chosen for.
	let nodeNum: Int64
	let file: FirmwareFile
	let hardware: DeviceHardwareEntity
	/// The radio's own PlatformIO target, which may be a flavor of the catalog's target.
	let firmwareTarget: String
	let pioEnv: String
	let radioName: String
	let bootloaderAdvice: BootloaderAdvice?

	var id: URL { file.localUrl }

	var radio: FirmwareUpdateRadio {
		FirmwareUpdateRadio(
			hardware: hardware,
			pioEnv: pioEnv,
			name: radioName,
			firmwareVersion: FirmwareFileVersion.version(in: file.localUrl.lastPathComponent),
			firmwareBuild: FirmwareFileVersion.build(in: file.localUrl.lastPathComponent)
		)
	}

	/// The file type the phone installs for an architecture; nil when it can't update it.
	static func phoneUpdateFileType(for architecture: Architecture) -> FirmwareFile.FirmwareType? {
		switch architecture {
		case .nrf52840:
			return .otaZip
		case .esp32, .esp32C3, .esp32S3, .esp32C6:
			return .bin
		case .rp2040:
			return nil
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

	/// The newest stable file for the connected radio, for starting the update from the
	/// Connect screen. Nil when the phone can't update this radio or no stable build is listed.
	@MainActor
	static func updatePlan(accessoryManager: AccessoryManager) -> FirmwareUpdatePlan? {
		guard let nodeNum = accessoryManager.activeDeviceNum,
		      let node = getNodeInfo(id: nodeNum, context: accessoryManager.context),
		      let pioEnv = node.myInfo?.pioEnv?.trimmingCharacters(in: .whitespacesAndNewlines),
		      !pioEnv.isEmpty,
		      let hardware = hardware(
				platformioTarget: pioEnv,
				hwModel: node.user.map { Int64($0.hwModelId) },
				context: accessoryManager.context
		      ),
		      let architecture = hardware.architecture.flatMap({ Architecture(rawValue: $0) }),
		      let fileType = FirmwareUpdatePlan.phoneUpdateFileType(for: architecture) else {
			return nil
		}

		let region = node.loRaConfig.flatMap { RegionCodes(rawValue: Int($0.regionCode)) } ?? .unset
		let firmwareList = FirmwareViewModel(
			forHardware: hardware,
			platformioTarget: pioEnv,
			preferredRegion: region,
			automaticallyRefresh: false
		)
		firmwareList.refresh()
		guard let file = firmwareList.mostRecentFirmware(forReleaseType: .stable)
			.first(where: { $0.firmwareType == fileType }) else {
			return nil
		}

		let bootloaderAdvice: BootloaderAdvice? = architecture == .nrf52840
			? BootloaderAdvice.forNRF52(
				packed: node.metadata?.bootloaderVersion,
				upgradeAvailable: OTAFIXBootloader.supportsTarget(pioEnv)
			)
			: nil
		let longName = node.user?.longName ?? ""
		return FirmwareUpdatePlan(
			nodeNum: node.num,
			file: file,
			hardware: hardware,
			firmwareTarget: pioEnv,
			pioEnv: pioEnv,
			radioName: longName.isEmpty ? (hardware.displayName ?? "") : longName,
			bootloaderAdvice: bootloaderAdvice
		)
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
		      let rawPlatformioTarget = node.myInfo?.pioEnv else {
			return nil
		}
		let platformioTarget = rawPlatformioTarget.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !platformioTarget.isEmpty,
		      let hardware = hardware(
				platformioTarget: platformioTarget,
				hwModel: node.user.map { Int64($0.hwModelId) },
				context: accessoryManager.context
		      ) else {
			return nil
		}

		return candidate(from: FirmwareUpdateNotificationSource(
			nodeNum: node.num,
			deviceName: node.user?.localLongName ?? accessoryManager.activeConnection?.device.longName ?? accessoryManager.activeConnection?.device.name,
			platformioTarget: platformioTarget,
			architecture: hardware.architecture,
			metadataVersion: node.metadata?.firmwareVersion,
			connectedVersion: accessoryManager.connectedVersion,
			latestStableVersion: latestStableFirmwareVersion(context: accessoryManager.context)
		))
	}

	@MainActor
	private static func hardware(
		platformioTarget: String,
		hwModel: Int64?,
		context: ModelContext
	) -> DeviceHardwareEntity? {
		do {
			let hardware = try context.fetch(FetchDescriptor<DeviceHardwareEntity>())
			let records = hardware.map(HardwareCatalogRecord.init)
			guard let resolution = FirmwareHardwareResolver.resolve(
				pioEnv: platformioTarget,
				hwModel: hwModel,
				in: records
			) else { return nil }
			return hardware.first { $0.platformioTarget == resolution.metadataTarget }
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
