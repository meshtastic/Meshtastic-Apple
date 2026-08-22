// MARK: UF2Maintenance.swift

import CryptoKit
import Foundation

struct UF2MaintenanceApplicationDescriptor: Codable, Equatable {
	let localURL: URL
	let fileName: String
	let version: String
	let platformioTarget: String
	let architecture: String

	init(
		localURL: URL,
		fileName: String,
		version: String,
		platformioTarget: String,
		architecture: String
	) {
		self.localURL = localURL
		self.fileName = fileName
		self.version = version
		self.platformioTarget = platformioTarget
		self.architecture = architecture
	}

	init(firmwareFile: FirmwareFile) {
		localURL = firmwareFile.localUrl
		fileName = firmwareFile.localUrl.lastPathComponent
		version = firmwareFile.versionId
		platformioTarget = firmwareFile.platformioTarget
		architecture = firmwareFile.architecture.rawValue
	}
}

struct UF2FirmwareArtifactIdentity: Codable, Equatable {
	let sha256: String
	let byteCount: Int
	let blockCount: Int
	let firstTargetAddress: UInt32
	let minimumTargetAddress: UInt32
	let maximumTargetEnd: UInt32
	let familyID: UInt32
}

struct UF2VolumeIdentity: Codable, Equatable {
	let bootloaderVersion: String?
	let boardID: String
	let softDevice: String?
}

struct UF2WriteAttempt: Equatable {
	let volume: UF2VolumeIdentity
	let destinationName: String
	let copyError: String?
}

enum UF2FirmwareValidationError: LocalizedError, Equatable {
	case unreadableFirmware(String)
	case malformedUF2(String)
	case unsupportedArchitecture(String)
	case missingInfoFile(folder: String, entries: [String])
	case unreadableVolume(String)
	case invalidInfoFile
	case missingBoardID
	case unsupportedBoardIdentity(target: String, boardID: String)
	case unknownSoftDevice(String?)
	case softDeviceMismatch(softDevice: String?, firstTargetAddress: UInt32)
	case firmwareChanged(expected: String, actual: String)
	case volumeChanged

	var errorDescription: String? {
		switch self {
		case .unreadableFirmware(let message):
			String(localized: "The firmware file could not be read: \(message)")
		case .malformedUF2(let message):
			String(localized: "The file is not a valid UF2 image: \(message)")
		case .unsupportedArchitecture(let architecture):
			String(localized: "Firmware maintenance does not support architecture \(architecture).")
		case .missingInfoFile(let folder, let entries):
			String(
				localized: "\(folder) is not a UF2 bootloader volume because INFO_UF2.TXT is missing. Found: \(entries.joined(separator: ", "))."
			)
		case .unreadableVolume(let message):
			String(localized: "The selected volume could not be read: \(message)")
		case .invalidInfoFile:
			String(localized: "INFO_UF2.TXT does not identify a UF2 bootloader.")
		case .missingBoardID:
			String(localized: "INFO_UF2.TXT does not contain a Board-ID.")
		case .unsupportedBoardIdentity(let target, let boardID):
			String(localized: "Board-ID \(boardID) is not approved for firmware target \(target).")
		case .unknownSoftDevice(let softDevice):
			String(localized: "The bootloader reported an unsupported SoftDevice: \(softDevice ?? String(localized: "Unknown")).")
		case .softDeviceMismatch(let softDevice, let address):
			String(
				localized: "The application starts at \(String(format: "0x%08X", address)), which does not match SoftDevice \(softDevice ?? String(localized: "Unknown"))."
			)
		case .firmwareChanged(let expected, let actual):
			String(localized: "The firmware changed after preparation. Expected SHA-256 \(expected), found \(actual).")
		case .volumeChanged:
			String(localized: "The UF2 volume changed between validation and writing.")
		}
	}
}

enum UF2MaintenanceRequest: String, Codable, Equatable {
	case bootloaderUpgrade
	case factoryErase

	var displayName: String {
		switch self {
		case .bootloaderUpgrade: String(localized: "Upgrade Bootloader")
		case .factoryErase: String(localized: "Erase and Reinstall")
		}
	}
}

struct UF2MaintenanceArtifact: Equatable {
	enum Source: Equatable {
		case remote(URL)
		case bundled(resource: String)
	}

	let source: Source
	let fileName: String
	let sha256: String
	let expectedFirstTargetAddress: UInt32?
	let expectedFamilyID: UInt32?
}

struct UF2MaintenanceArtifactIdentity: Codable, Equatable {
	let request: UF2MaintenanceRequest
	let fileName: String
	let sourceURL: URL?
	let sha256: String
	let byteCount: Int
	let blockCount: Int
	let firstTargetAddress: UInt32
	let maximumTargetEnd: UInt32
	let familyID: UInt32
}

enum UF2MaintenanceError: LocalizedError, Equatable {
	case unknownBoardID(String)
	case unknownSoftDevice(String?)
	case unavailableBundledImage(String)
	case downloadFailed(String)
	case hashMismatch(expected: String, actual: String)
	case firstTargetMismatch(expected: UInt32, actual: UInt32)
	case familyMismatch(expected: UInt32, actual: UInt32)

	var errorDescription: String? {
		switch self {
		case .unknownBoardID(let boardID):
			String(localized: "No verified OTAFIX bootloader is available for Board-ID \(boardID).")
		case .unknownSoftDevice(let softDevice):
			String(localized: "No safe factory-erase image is available for SoftDevice \(softDevice ?? String(localized: "Unknown")).")
		case .unavailableBundledImage(let name):
			String(localized: "The bundled factory-erase image \(name) is unavailable.")
		case .downloadFailed(let message):
			String(localized: "The maintenance image could not be downloaded: \(message)")
		case .hashMismatch(let expected, let actual):
			String(localized: "The maintenance image failed SHA-256 verification. Expected \(expected), found \(actual).")
		case .firstTargetMismatch(let expected, let actual):
			String(
				localized: "The maintenance image starts at \(Self.hex(actual)); expected \(Self.hex(expected))."
			)
		case .familyMismatch(let expected, let actual):
			String(
				localized: "The maintenance image has UF2 family \(Self.hex(actual)); expected \(Self.hex(expected))."
			)
		}
	}

	private static func hex(_ value: UInt32) -> String {
		String(format: "0x%08X", value)
	}
}

enum UF2MaintenanceCatalog {
	static let expectedOTAFIXVersion = "0.9.2-OTAFIX2.2-BP1.4"
	private static let otafixRelease = expectedOTAFIXVersion
	private static let otafixBase = URL(
		string: "https://github.com/meshtastic/Adafruit_nRF52_Bootloader_OTAFIX/releases/download/\(expectedOTAFIXVersion)"
	)!
	private static let nRF52840FamilyID: UInt32 = 0xADA5_2840

	// Keep this UX gate aligned with Android's OTAFIX_SUPPORTED_TARGETS.
	private static let supportedTargets: Set<String> = [
		"rak4631",
		"rak_wismeshtag",
		"t-echo",
		"heltec-mesh-node-t114",
		"nrf52_promicro_diy_tcxo",
		"thinknode_m1",
		"thinknode_m3",
		"thinknode_m6",
		"tracker-t1000-e",
		"seeed_wio_tracker_L1",
		"seeed_wio_tracker_L1_eink",
		"seeed_solar_node",
		"seeed_xiao_nrf52840_kit"
	]

	private static let otafixByBoardID: [String: UF2MaintenanceArtifact] = [
		"HT-n5262": otafix(board: "heltec_t114", sha256: "c1ce07c1e66dbf42faea03df88f1e4bac6d66f1177600f41c280059e1653cba2"),
		"MinewSemi-MX25LE01": otafix(board: "minewsemi_mx25le01", sha256: "b50a9bd0381155074ccc0a211942365ebd9cd108697c8f2e9d9da947e10265a1"),
		"TRACKER L1": otafix(board: "wio_tracker_l1", sha256: "29e11b45d43d0d2ffc49a780c6299bbef86992465a568d74c533d0d0dd5d5e30"),
		"WisBlock-RAK4631-Board": otafix(board: "wiscore_rak4631_board", sha256: "910806d0aedfcacf317fc4b9f2469593d6ec0d855568ff69c70faec3a4b06c4a"),
		"WisMesh-Tag": otafix(board: "wismesh_tag", sha256: "b9e92b4ec1a74d176f75473be00804ee9902a4816bd94e098ad153ecd60a34c1"),
		"nRF52840-SeeedSenseCAPSolarP1-v1": otafix(board: "sensecap_solar_p1", sha256: "f0fad2cfa98867504085fe524a0af65916aa13c781cc5e1ff3025f04cea5db0b"),
		"nRF52840-SeeedXiao-v1": otafix(board: "xiao_nrf52840_ble", sha256: "6c7d6c6226c4b425a473f689bb25687baa9cdc79d9a350fd5201762bf7819cba"),
		"nRF52840-SeeedXiaoSense-v1": otafix(board: "xiao_nrf52840_ble_sense", sha256: "4857ae18d2f3145534515da3c6e6e2a813722069f0bc415a7fe43d9de8a0be62"),
		"nRF52840-T1000-E-v1": otafix(board: "t1000_e", sha256: "1b02fb4e8083a85930f615d95adcc29e983f2795a9c7755674d6a380b00410e5"),
		"nRF52840-TEcho-v1": otafix(board: "lilygo_techo", sha256: "b254aa092b312238a857e68db5beffda922410092e63044410e4c25f25498b2e"),
		"nRF52840-ThinkNode-M3-v1": otafix(board: "thinknode_m3", sha256: "b04f020c7f4f0b7bd99548efbd5db33ebc9e09ef42e5dd874ef69433c363798d"),
		"nRF52840-ThinkNodeM1-v1": otafix(board: "thinknode_m1", sha256: "991114392f6b731860f05a932e1c6529f0c97a5e4c054ff51e081d81f2e7d3f1"),
		"nRF52840-ThinkNodeM6-v1": otafix(board: "thinknode_m6", sha256: "aea8e4ce5d9f9ff7adc68e794ff735fe94bace7a6d391c3606df4c0ae6f45547"),
		"nRF52840-promicro": otafix(board: "promicro_nrf52840", sha256: "bd9cc4de26fd162b6600eafc2634a1e8c6e81ade84c141f8eb44350506321e8b")
	]

	static func supports(target: String) -> Bool {
		supportedTargets.contains(target)
	}

	static func applicationStart(for softDevice: String?) -> UInt32? {
		let normalized = softDevice?.lowercased() ?? ""
		guard normalized.contains("s140") else { return nil }
		if normalized.contains("7.3.0") { return 0x0002_7000 }
		if normalized.contains("6.1.1") { return 0x0002_6000 }
		return nil
	}

	static func artifact(
		for request: UF2MaintenanceRequest,
		volume: UF2VolumeIdentity
	) throws -> UF2MaintenanceArtifact {
		switch request {
		case .bootloaderUpgrade:
			guard let artifact = otafixByBoardID[volume.boardID] else {
				throw UF2MaintenanceError.unknownBoardID(volume.boardID)
			}
			return artifact
		case .factoryErase:
			if applicationStart(for: volume.softDevice) == 0x0002_7000 {
				return UF2MaintenanceArtifact(
					source: .bundled(resource: "nrf52-factory-erase-s140-7.3.0-ios"),
					fileName: "nrf52-factory-erase-s140-7.3.0-ios.uf2",
					sha256: "919721f1129c9b79edaa631a2eb0e00d0274ba2478af2563233e744613ec4c00",
					expectedFirstTargetAddress: 0x0002_7000,
					expectedFamilyID: nRF52840FamilyID
				)
			}
			if applicationStart(for: volume.softDevice) == 0x0002_6000 {
				return UF2MaintenanceArtifact(
					source: .bundled(resource: "nrf52-factory-erase-s140-6.1.1-ios"),
					fileName: "nrf52-factory-erase-s140-6.1.1-ios.uf2",
					sha256: "30abd2d05a5c0aeb737f3018539813a31371f919abc6a5dba5e62cddac1fdbc8",
					expectedFirstTargetAddress: 0x0002_6000,
					expectedFamilyID: nRF52840FamilyID
				)
			}
			throw UF2MaintenanceError.unknownSoftDevice(volume.softDevice)
		}
	}

	private static func otafix(board: String, sha256: String) -> UF2MaintenanceArtifact {
		let fileName = "update-\(board)_bootloader-\(otafixRelease)_nosd.uf2"
		return UF2MaintenanceArtifact(
			source: .remote(otafixBase.appendingPathComponent(fileName)),
			fileName: fileName,
			sha256: sha256,
			expectedFirstTargetAddress: nil,
			expectedFamilyID: nil
		)
	}
}

enum UF2MaintenanceArtifactLoader {
	static func load(
		_ artifact: UF2MaintenanceArtifact,
		request: UF2MaintenanceRequest,
		bundle: Bundle = .main,
		session: URLSession = .shared
	) async throws -> (Data, UF2MaintenanceArtifactIdentity) {
		let data: Data
		let sourceURL: URL?
		switch artifact.source {
		case .remote(let url):
			do {
				var request = URLRequest(url: url)
				request.timeoutInterval = 60
				let (temporaryURL, response) = try await session.download(for: request)
				defer { try? FileManager.default.removeItem(at: temporaryURL) }
				guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
					throw URLError(.badServerResponse)
				}
				guard let byteCount = try temporaryURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
					byteCount <= UF2MaintenanceArtifactInspector.maximumByteCount else {
					throw UF2FirmwareValidationError.malformedUF2(
						String(localized: "The maintenance image is larger than 32 MB.")
					)
				}
				data = try Data(contentsOf: temporaryURL, options: .mappedIfSafe)
				sourceURL = url
			} catch let error as UF2FirmwareValidationError {
				throw error
			} catch {
				throw UF2MaintenanceError.downloadFailed(error.localizedDescription)
			}
		case .bundled(let resource):
			guard let url = bundle.url(forResource: resource, withExtension: "uf2") else {
				throw UF2MaintenanceError.unavailableBundledImage(resource)
			}
			data = try Data(contentsOf: url, options: .mappedIfSafe)
			sourceURL = nil
		}

		let parsed = try UF2MaintenanceArtifactInspector.inspect(data: data)
		guard parsed.sha256 == artifact.sha256 else {
			throw UF2MaintenanceError.hashMismatch(expected: artifact.sha256, actual: parsed.sha256)
		}
		if let expected = artifact.expectedFirstTargetAddress,
			parsed.firstTargetAddress != expected {
			throw UF2MaintenanceError.firstTargetMismatch(expected: expected, actual: parsed.firstTargetAddress)
		}
		if let expected = artifact.expectedFamilyID, parsed.familyID != expected {
			throw UF2MaintenanceError.familyMismatch(expected: expected, actual: parsed.familyID)
		}
		return (
			data,
			UF2MaintenanceArtifactIdentity(
				request: request,
				fileName: artifact.fileName,
				sourceURL: sourceURL,
				sha256: parsed.sha256,
				byteCount: parsed.byteCount,
				blockCount: parsed.blockCount,
				firstTargetAddress: parsed.firstTargetAddress,
				maximumTargetEnd: parsed.maximumTargetEnd,
				familyID: parsed.familyID
			)
		)
	}
}

enum UF2MaintenanceArtifactInspector {
	static let maximumByteCount = 32 * 1024 * 1024
	private static let blockSize = 512
	private static let maximumPayloadSize: UInt32 = 476
	private static let magicStart0: UInt32 = 0x0A32_4655
	private static let magicStart1: UInt32 = 0x9E5D_5157
	private static let magicEnd: UInt32 = 0x0AB1_6F30
	private static let familyIDPresentFlag: UInt32 = 0x0000_2000

	static func inspect(data: Data) throws -> UF2FirmwareArtifactIdentity {
		guard data.count >= blockSize, data.count.isMultiple(of: blockSize) else {
			throw UF2FirmwareValidationError.malformedUF2(
				String(localized: "The maintenance file size is not a whole number of 512-byte UF2 blocks.")
			)
		}
		guard data.count <= maximumByteCount else {
			throw UF2FirmwareValidationError.malformedUF2(String(localized: "The maintenance image is larger than 32 MB."))
		}

		let count = data.count / blockSize
		var firstTargetAddress: UInt32?
		var minimumTargetAddress = UInt32.max
		var maximumTargetEnd: UInt32 = 0
		var expectedFamilyID: UInt32?
		for blockIndex in 0..<count {
			let offset = blockIndex * blockSize
			guard uint32(in: data, at: offset) == magicStart0,
				uint32(in: data, at: offset + 4) == magicStart1,
				uint32(in: data, at: offset + 508) == magicEnd else {
				throw UF2FirmwareValidationError.malformedUF2(
					String(localized: "Maintenance block \(blockIndex) has invalid magic values.")
				)
			}
			guard uint32(in: data, at: offset + 8) == familyIDPresentFlag else {
				throw UF2FirmwareValidationError.malformedUF2(
					String(localized: "Maintenance block \(blockIndex) has unsupported UF2 flags.")
				)
			}
			let targetAddress = uint32(in: data, at: offset + 12)
			let payloadSize = uint32(in: data, at: offset + 16)
			let blockNumber = uint32(in: data, at: offset + 20)
			let totalBlocks = uint32(in: data, at: offset + 24)
			let familyID = uint32(in: data, at: offset + 28)
			guard payloadSize > 0, payloadSize <= maximumPayloadSize else {
				throw UF2FirmwareValidationError.malformedUF2(
					String(localized: "Maintenance block \(blockIndex) has invalid payload size \(payloadSize).")
				)
			}
			guard blockNumber == UInt32(blockIndex), totalBlocks == UInt32(count) else {
				throw UF2FirmwareValidationError.malformedUF2(
					String(localized: "Maintenance block numbering is inconsistent at block \(blockIndex).")
				)
			}
			if let expectedFamilyID, familyID != expectedFamilyID {
				throw UF2FirmwareValidationError.malformedUF2(
					String(localized: "Maintenance block \(blockIndex) has a different UF2 family ID.")
				)
			}
			expectedFamilyID = expectedFamilyID ?? familyID
			let (targetEnd, overflow) = targetAddress.addingReportingOverflow(payloadSize)
			guard !overflow else {
				throw UF2FirmwareValidationError.malformedUF2(
					String(localized: "Maintenance block \(blockIndex) target range overflows.")
				)
			}
			firstTargetAddress = firstTargetAddress ?? targetAddress
			minimumTargetAddress = min(minimumTargetAddress, targetAddress)
			maximumTargetEnd = max(maximumTargetEnd, targetEnd)
		}

		guard let firstTargetAddress, let familyID = expectedFamilyID else {
			throw UF2FirmwareValidationError.malformedUF2(String(localized: "The maintenance image contains no UF2 blocks."))
		}
		let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
		return UF2FirmwareArtifactIdentity(
			sha256: digest,
			byteCount: data.count,
			blockCount: count,
			firstTargetAddress: firstTargetAddress,
			minimumTargetAddress: minimumTargetAddress,
			maximumTargetEnd: maximumTargetEnd,
			familyID: familyID
		)
	}

	private static func uint32(in data: Data, at offset: Int) -> UInt32 {
		data.withUnsafeBytes {
			UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
		}
	}
}
