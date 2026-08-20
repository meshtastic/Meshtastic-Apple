// MARK: UF2MaintenanceIO.swift

import CryptoKit
import Foundation

enum UF2MaintenanceBoardCatalog {
	private static let boardIDsByTarget: [String: Set<String>] = [
		"heltec-mesh-node-t114": ["HT-n5262"],
		"seeed_wio_tracker_L1": ["TRACKER L1"],
		"seeed_wio_tracker_L1_eink": ["TRACKER L1"],
		"rak4631": ["WisBlock-RAK4631-Board"],
		"rak_wismeshtag": ["WisMesh-Tag"],
		"seeed_solar_node": ["nRF52840-SeeedSenseCAPSolarP1-v1"],
		"seeed_xiao_nrf52840_kit": ["nRF52840-SeeedXiao-v1", "nRF52840-SeeedXiaoSense-v1"],
		"tracker-t1000-e": ["nRF52840-T1000-E-v1"],
		"t-echo": ["nRF52840-TEcho-v1"],
		"thinknode_m1": ["nRF52840-ThinkNodeM1-v1"],
		"thinknode_m3": ["nRF52840-ThinkNode-M3-v1"],
		"thinknode_m6": ["nRF52840-ThinkNodeM6-v1"],
		"nrf52_promicro_diy_tcxo": ["nRF52840-promicro"]
	]

	static func supports(boardID: String, target: String) -> Bool {
		boardIDsByTarget[target]?.contains(boardID) == true
	}
}

enum UF2MaintenanceApplicationInspector {
	private static let nRF52840FamilyID: UInt32 = 0xADA5_2840

	static func inspect(
		fileURL: URL,
		descriptor: UF2MaintenanceApplicationDescriptor
	) throws -> (Data, UF2FirmwareArtifactIdentity) {
		guard descriptor.architecture == Architecture.nrf52840.rawValue else {
			throw UF2FirmwareValidationError.unsupportedArchitecture(descriptor.architecture)
		}
		guard descriptor.fileName.hasPrefix("firmware-\(descriptor.platformioTarget)-") else {
			throw UF2FirmwareValidationError.malformedUF2(
				String(localized: "The filename does not match the selected firmware target.")
			)
		}
		let data: Data
		do {
			data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
		} catch {
			throw UF2FirmwareValidationError.unreadableFirmware(error.localizedDescription)
		}
		let identity = try UF2MaintenanceArtifactInspector.inspect(data: data)
		guard identity.familyID == nRF52840FamilyID else {
			throw UF2FirmwareValidationError.malformedUF2(
				String(localized: "The application has the wrong UF2 family ID.")
			)
		}
		guard [0x0002_6000, 0x0002_7000].contains(identity.firstTargetAddress),
			identity.minimumTargetAddress >= identity.firstTargetAddress,
			identity.maximumTargetEnd <= 0x000F_4000 else {
			throw UF2FirmwareValidationError.malformedUF2(
				String(localized: "The application writes outside the supported nRF52840 application region.")
			)
		}
		return (data, identity)
	}
}

enum UF2MaintenanceDestinationValidator {
	static func validate(
		volume: UF2VolumeIdentity,
		artifact: UF2FirmwareArtifactIdentity,
		descriptor: UF2MaintenanceApplicationDescriptor
	) throws {
		guard UF2MaintenanceBoardCatalog.supports(
			boardID: volume.boardID,
			target: descriptor.platformioTarget
		) else {
			throw UF2FirmwareValidationError.unsupportedBoardIdentity(
				target: descriptor.platformioTarget,
				boardID: volume.boardID
			)
		}
		guard let expectedAddress = UF2MaintenanceCatalog.applicationStart(for: volume.softDevice) else {
			throw UF2FirmwareValidationError.unknownSoftDevice(volume.softDevice)
		}
		guard expectedAddress == artifact.firstTargetAddress else {
			throw UF2FirmwareValidationError.softDeviceMismatch(
				softDevice: volume.softDevice,
				firstTargetAddress: artifact.firstTargetAddress
			)
		}
	}
}

enum UF2MaintenanceVolumeIO {
	static func inspect(folderURL: URL) async throws -> UF2VolumeIdentity {
		try await Task.detached(priority: .userInitiated) {
			let didStartAccess = folderURL.startAccessingSecurityScopedResource()
			defer {
				if didStartAccess { folderURL.stopAccessingSecurityScopedResource() }
			}
			return try inspectAccessibleFolder(folderURL)
		}.value
	}

	static func writeValidated(
		_ data: Data,
		to folderURL: URL,
		expectedVolume: UF2VolumeIdentity
	) async throws -> UF2WriteAttempt {
		try await Task.detached(priority: .userInitiated) {
			let didStartAccess = folderURL.startAccessingSecurityScopedResource()
			defer {
				if didStartAccess { folderURL.stopAccessingSecurityScopedResource() }
			}
			let volume = try inspectAccessibleFolder(folderURL)
			guard volume == expectedVolume else {
				throw UF2FirmwareValidationError.volumeChanged
			}
			let destinationName = "\(UUID().uuidString).uf2"
			let destinationURL = folderURL.appendingPathComponent(destinationName, isDirectory: false)
			let copyError = coordinatedWrite(data, to: destinationURL)
			return UF2WriteAttempt(volume: volume, destinationName: destinationName, copyError: copyError)
		}.value
	}

	static func value(for key: String, in text: String) -> String? {
		let prefix = key.lowercased() + ":"
		return text
			.split(whereSeparator: \Character.isNewline)
			.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
			.first { $0.lowercased().hasPrefix(prefix) }
			.map { String($0.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces) }
			.flatMap { $0.isEmpty ? nil : $0 }
	}

	private static func inspectAccessibleFolder(_ folderURL: URL) throws -> UF2VolumeIdentity {
		let contents: [URL] = try coordinatedRead(at: folderURL) {
			try FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)
		}
		guard let infoURL = contents.first(where: {
			$0.lastPathComponent.caseInsensitiveCompare("INFO_UF2.TXT") == .orderedSame
		}) else {
			throw UF2FirmwareValidationError.missingInfoFile(
				folder: folderURL.lastPathComponent,
				entries: contents.map(\.lastPathComponent).sorted()
			)
		}
		let infoText: String = try coordinatedRead(at: infoURL) {
			try String(contentsOf: $0, encoding: .utf8)
		}
		guard let firstLine = infoText.split(whereSeparator: \Character.isNewline).first,
			firstLine.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("uf2 bootloader ") else {
			throw UF2FirmwareValidationError.invalidInfoFile
		}
		guard let boardID = value(for: "Board-ID", in: infoText) else {
			throw UF2FirmwareValidationError.missingBoardID
		}
		return UF2VolumeIdentity(
			bootloaderVersion: String(firstLine).trimmingCharacters(in: .whitespacesAndNewlines),
			boardID: boardID.trimmingCharacters(in: .whitespacesAndNewlines),
			softDevice: value(for: "SoftDevice", in: infoText)
		)
	}

	private static func coordinatedRead<T>(at url: URL, _ read: (URL) throws -> T) throws -> T {
		let coordinator = NSFileCoordinator()
		var coordinationError: NSError?
		var result: Result<T, Error>?
		coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { coordinatedURL in
			result = Result { try read(coordinatedURL) }
		}
		if let coordinationError {
			throw UF2FirmwareValidationError.unreadableVolume(coordinationError.localizedDescription)
		}
		guard let result else {
			throw UF2FirmwareValidationError.unreadableVolume(
				String(localized: "No coordinated read result was returned.")
			)
		}
		do {
			return try result.get()
		} catch let error as UF2FirmwareValidationError {
			throw error
		} catch {
			throw UF2FirmwareValidationError.unreadableVolume(error.localizedDescription)
		}
	}

	private static func coordinatedWrite(_ data: Data, to destinationURL: URL) -> String? {
		let coordinator = NSFileCoordinator()
		var coordinationError: NSError?
		var writeError: Error?
		coordinator.coordinate(writingItemAt: destinationURL, options: [], error: &coordinationError) { url in
			do {
				try data.write(to: url, options: [])
			} catch {
				writeError = error
			}
		}
		return coordinationError?.localizedDescription ?? writeError?.localizedDescription
	}
}
