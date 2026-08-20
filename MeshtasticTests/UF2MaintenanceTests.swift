import Foundation
import Testing
@testable import Meshtastic

@Suite("UF2 maintenance")
struct UF2MaintenanceTests {
	private var descriptor: UF2MaintenanceApplicationDescriptor {
		UF2MaintenanceApplicationDescriptor(
			localURL: FileManager.default.temporaryDirectory.appendingPathComponent("firmware-tracker-t1000-e-2.8.0.uf2"),
			fileName: "firmware-tracker-t1000-e-2.8.0.uf2",
			version: "v2.8.0",
			platformioTarget: "tracker-t1000-e",
			architecture: "nrf52840"
		)
	}

	@Test("Maintenance target gate matches Android")
	func targetCoverage() {
		let supported = [
			"rak4631", "rak_wismeshtag", "t-echo", "heltec-mesh-node-t114",
			"nrf52_promicro_diy_tcxo", "thinknode_m1", "thinknode_m3", "thinknode_m6",
			"tracker-t1000-e", "seeed_wio_tracker_L1", "seeed_wio_tracker_L1_eink",
			"seeed_solar_node", "seeed_xiao_nrf52840_kit"
		]
		for target in supported {
			#expect(UF2MaintenanceCatalog.supports(target: target))
		}
		#expect(!UF2MaintenanceCatalog.supports(target: "minewsemi_mx25le01"))
		#expect(!UF2MaintenanceCatalog.supports(target: "thinknode_m1-inkhud"))
		#expect(!UF2MaintenanceCatalog.supports(target: "rp2040-target"))
	}

	@Test("OTAFIX selection uses Board-ID")
	func otafixSelection() throws {
		let artifact = try UF2MaintenanceCatalog.artifact(
			for: .bootloaderUpgrade,
			volume: makeVolume()
		)
		#expect(artifact.fileName == "update-t1000_e_bootloader-0.9.2-OTAFIX2.2-BP1.4_nosd.uf2")
		#expect(artifact.sha256 == "1b02fb4e8083a85930f615d95adcc29e983f2795a9c7755674d6a380b00410e5")
	}

	@Test("Unknown Board-ID and SoftDevice are refused")
	func unknownIdentityRefused() {
		#expect(throws: UF2MaintenanceError.unknownBoardID("unknown")) {
			_ = try UF2MaintenanceCatalog.artifact(
				for: .bootloaderUpgrade,
				volume: UF2VolumeIdentity(bootloaderVersion: nil, boardID: "unknown", softDevice: "S140 7.3.0")
			)
		}
		#expect(UF2MaintenanceCatalog.applicationStart(for: "S113 7.3.0") == nil)
		#expect(throws: UF2MaintenanceError.unknownSoftDevice("S140 8.0.0")) {
			_ = try UF2MaintenanceCatalog.artifact(
				for: .factoryErase,
				volume: UF2VolumeIdentity(
					bootloaderVersion: nil,
					boardID: "nRF52840-T1000-E-v1",
					softDevice: "S140 8.0.0"
				)
			)
		}
	}

	@Test("Bundled erase images match pinned hashes and addresses")
	func bundledEraseImages() async throws {
		for (softDevice, expectedAddress, expectedHash) in [
			("S140 6.1.1", UInt32(0x0002_6000), "30abd2d05a5c0aeb737f3018539813a31371f919abc6a5dba5e62cddac1fdbc8"),
			("S140 7.3.0", UInt32(0x0002_7000), "919721f1129c9b79edaa631a2eb0e00d0274ba2478af2563233e744613ec4c00")
		] {
			let artifact = try UF2MaintenanceCatalog.artifact(
				for: .factoryErase,
				volume: UF2VolumeIdentity(
					bootloaderVersion: nil,
					boardID: "nRF52840-T1000-E-v1",
					softDevice: softDevice
				)
			)
			let (_, identity) = try await UF2MaintenanceArtifactLoader.load(
				artifact,
				request: .factoryErase
			)
			#expect(identity.sha256 == expectedHash)
			#expect(identity.firstTargetAddress == expectedAddress)
			#expect(identity.familyID == 0xADA5_2840)
		}
	}

	@Test("Application destination requires matching Board-ID and SoftDevice")
	func applicationDestinationValidation() throws {
		let identity = try UF2MaintenanceArtifactInspector.inspect(
			data: makeUF2(blockCount: 1, firstTargetAddress: 0x0002_7000)
		)
		#expect(throws: UF2FirmwareValidationError.self) {
			try UF2MaintenanceDestinationValidator.validate(
				volume: UF2VolumeIdentity(
					bootloaderVersion: nil,
					boardID: "WisBlock-RAK4631-Board",
					softDevice: "S140 7.3.0"
				),
				artifact: identity,
				descriptor: descriptor
			)
		}
		#expect(throws: UF2FirmwareValidationError.self) {
			try UF2MaintenanceDestinationValidator.validate(
				volume: UF2VolumeIdentity(
					bootloaderVersion: nil,
					boardID: "nRF52840-T1000-E-v1",
					softDevice: "S140 6.1.1"
				),
				artifact: identity,
				descriptor: descriptor
			)
		}
	}

	@Test("Application validation rejects bootloader-region writes")
	func applicationRangeValidation() throws {
		let descriptor = descriptor
		let data = makeUF2(blockCount: 1, firstTargetAddress: 0x000F_4000)
		try data.write(to: descriptor.localURL, options: .atomic)
		defer { try? FileManager.default.removeItem(at: descriptor.localURL) }
		#expect(throws: UF2FirmwareValidationError.self) {
			_ = try UF2MaintenanceApplicationInspector.inspect(
				fileURL: descriptor.localURL,
				descriptor: descriptor
			)
		}
	}

	@Test("Volume inspection reads INFO_UF2 and rejects ordinary folders")
	func volumeInspection() async throws {
		let folder = try makeVolumeFolder()
		defer { try? FileManager.default.removeItem(at: folder) }
		let volume = try await UF2MaintenanceVolumeIO.inspect(folderURL: folder)
		#expect(volume == makeVolume())

		let ordinary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try FileManager.default.createDirectory(at: ordinary, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: ordinary) }
		await #expect(throws: UF2FirmwareValidationError.self) {
			_ = try await UF2MaintenanceVolumeIO.inspect(folderURL: ordinary)
		}
	}

	@MainActor
	@Test("Offline preparation and mandatory two-pass sequence succeed without a live node")
	func mandatoryTwoPassSequence() async throws {
		let applicationData = makeUF2(blockCount: 2, firstTargetAddress: 0x0002_7000)
		try applicationData.write(to: descriptor.localURL, options: .atomic)
		defer { try? FileManager.default.removeItem(at: descriptor.localURL) }
		let maintenanceData = makeUF2(
			blockCount: 1,
			firstTargetAddress: 0x000F_4000,
			familyID: 0xD663_823C
		)
		let maintenanceIdentity = try UF2MaintenanceArtifactInspector.inspect(data: maintenanceData)
		let store = MemoryStore()
		let coordinator = UF2MaintenanceCoordinator(
			descriptor: descriptor,
			request: .bootloaderUpgrade,
			store: store,
			artifactLoad: { artifact, request in
				(maintenanceData, makeMaintenanceIdentity(artifact, request, maintenanceIdentity))
			}
		)
		let folder = try makeVolumeFolder()
		defer { try? FileManager.default.removeItem(at: folder) }

		await coordinator.prepare()
		#expect(coordinator.state == .ready)
		coordinator.selectVolume()
		await coordinator.write(to: folder)
		#expect(coordinator.state == .awaitingApplicationWrite)
		#expect(store.record?.phase == .awaitingApplicationWrite)
		#expect(coordinator.blocksDismissal)

		try writeVolumeInfo(
			to: folder,
			bootloaderVersion: "UF2 Bootloader \(UF2MaintenanceCatalog.expectedOTAFIXVersion)"
		)
		coordinator.selectVolume()
		await coordinator.write(to: folder)
		#expect(coordinator.state == .awaitingReconnect)
		#expect(store.record?.phase == .awaitingReconnect)
		#expect(store.record?.maintenanceVerified == true)

		coordinator.verify(reportedFirmwareVersion: "2.8.0.597f676")
		guard case .completed(let warnings) = coordinator.state else {
			Issue.record("Expected completed maintenance")
			return
		}
		#expect(warnings.isEmpty)
		#expect(store.record == nil)
	}

}

extension UF2MaintenanceTests {
	@MainActor
	@Test("Factory erase uses the same mandatory two-pass sequence")
	func factoryEraseTwoPassSequence() async throws {
		let applicationData = makeUF2(blockCount: 2, firstTargetAddress: 0x0002_7000)
		try applicationData.write(to: descriptor.localURL, options: .atomic)
		defer { try? FileManager.default.removeItem(at: descriptor.localURL) }
		let maintenanceData = makeUF2(blockCount: 1, firstTargetAddress: 0x0002_7000)
		let maintenanceIdentity = try UF2MaintenanceArtifactInspector.inspect(data: maintenanceData)
		let store = MemoryStore()
		let coordinator = UF2MaintenanceCoordinator(
			descriptor: descriptor,
			request: .factoryErase,
			store: store,
			artifactLoad: { artifact, request in
				(maintenanceData, makeMaintenanceIdentity(artifact, request, maintenanceIdentity))
			}
		)
		let folder = try makeVolumeFolder()
		defer { try? FileManager.default.removeItem(at: folder) }

		await coordinator.prepare()
		coordinator.selectVolume()
		await coordinator.write(to: folder)
		#expect(coordinator.state == .awaitingApplicationWrite)
		#expect(store.record?.phase == .awaitingApplicationWrite)

		coordinator.selectVolume()
		await coordinator.write(to: folder)
		#expect(coordinator.state == .awaitingReconnect)
		#expect(store.record?.phase == .awaitingReconnect)

		coordinator.verify(reportedFirmwareVersion: "2.8.0.597f676")
		guard case .completed(let warnings) = coordinator.state else {
			Issue.record("Expected completed maintenance")
			return
		}
		#expect(warnings.isEmpty)
		#expect(store.record == nil)
	}

	@MainActor
	@Test("External verification requires parsable matching versions")
	func externalVerificationRequiresMatchingVersions() throws {
		let identity = try UF2MaintenanceArtifactInspector.inspect(
			data: makeUF2(blockCount: 1, firstTargetAddress: 0x0002_7000)
		)
		let invalidDescriptor = UF2MaintenanceApplicationDescriptor(
			localURL: descriptor.localURL,
			fileName: descriptor.fileName,
			version: "not-a-version",
			platformioTarget: descriptor.platformioTarget,
			architecture: descriptor.architecture
		)
		let invalidRecord = UF2MaintenanceRecoveryRecord(
			id: UUID(),
			createdAt: Date(timeIntervalSince1970: 1_000),
			request: .factoryErase,
			descriptor: invalidDescriptor,
			applicationArtifact: identity,
			phase: .awaitingReconnect,
			volume: makeVolume(),
			maintenanceArtifact: nil,
			maintenanceCopyError: nil,
			applicationCopyError: nil,
			maintenanceVerified: nil
		)
		let invalidStore = MemoryStore(record: invalidRecord)
		let invalidCoordinator = UF2MaintenanceCoordinator(
			descriptor: invalidDescriptor,
			request: .factoryErase,
			store: invalidStore
		)

		invalidCoordinator.verify(reportedFirmwareVersion: "also-not-a-version")
		#expect(invalidCoordinator.state == .awaitingReconnect)
		#expect(invalidStore.record != nil)

		let validStore = MemoryStore(record: makeRecord(phase: .awaitingReconnect, identity: identity))
		let validCoordinator = UF2MaintenanceCoordinator(
			descriptor: descriptor,
			request: .bootloaderUpgrade,
			store: validStore
		)
		validCoordinator.verify(reportedFirmwareVersion: "2.9.0")
		#expect(validCoordinator.state == .awaitingReconnect)
		validCoordinator.verify(reportedFirmwareVersion: "2.8.0.597f676")
		guard case .completed = validCoordinator.state else {
			Issue.record("Expected matching release components to complete verification")
			return
		}
	}

	@MainActor
	@Test("Unconfirmed OTAFIX never blocks application reinstall")
	func unconfirmedOTAFIXStillReinstalls() async throws {
		let applicationData = makeUF2(blockCount: 1, firstTargetAddress: 0x0002_7000)
		try applicationData.write(to: descriptor.localURL, options: .atomic)
		defer { try? FileManager.default.removeItem(at: descriptor.localURL) }
		let identity = try UF2MaintenanceApplicationInspector.inspect(
			fileURL: descriptor.localURL,
			descriptor: descriptor
		).1
		let store = MemoryStore(record: makeRecord(phase: .awaitingApplicationWrite, identity: identity))
		let coordinator = UF2MaintenanceCoordinator(
			descriptor: descriptor,
			request: .bootloaderUpgrade,
			store: store
		)
		let folder = try makeVolumeFolder()
		defer { try? FileManager.default.removeItem(at: folder) }

		coordinator.selectVolume()
		await coordinator.write(to: folder)
		#expect(coordinator.state == .awaitingReconnect)
		#expect(store.record?.maintenanceVerified == false)
		#expect(coordinator.warningMessage?.contains("will continue") == true)
	}

	@MainActor
	@Test("A destination failure before maintenance bytes remains retryable")
	func preWriteFailureRemainsRetryable() async throws {
		let applicationData = makeUF2(blockCount: 1, firstTargetAddress: 0x0002_7000)
		try applicationData.write(to: descriptor.localURL, options: .atomic)
		defer { try? FileManager.default.removeItem(at: descriptor.localURL) }
		let store = MemoryStore()
		let coordinator = UF2MaintenanceCoordinator(
			descriptor: descriptor,
			request: .bootloaderUpgrade,
			store: store
		)
		let folder = try makeVolumeFolder(boardID: "WisBlock-RAK4631-Board")
		defer { try? FileManager.default.removeItem(at: folder) }

		await coordinator.prepare()
		coordinator.selectVolume()
		await coordinator.write(to: folder)

		#expect(coordinator.state == .ready)
		#expect(store.record?.phase == .prepared)
		#expect(coordinator.canSelectVolume)
	}

	@MainActor
	@Test("Changed application and changed second-pass volume are refused before writing")
	func secondPassChangesAreRefused() async throws {
		var original = makeUF2(blockCount: 1, firstTargetAddress: 0x0002_7000)
		try original.write(to: descriptor.localURL, options: .atomic)
		defer { try? FileManager.default.removeItem(at: descriptor.localURL) }
		let identity = try UF2MaintenanceApplicationInspector.inspect(
			fileURL: descriptor.localURL,
			descriptor: descriptor
		).1
		let store = MemoryStore(record: makeRecord(phase: .awaitingApplicationWrite, identity: identity))
		let coordinator = UF2MaintenanceCoordinator(
			descriptor: descriptor,
			request: .bootloaderUpgrade,
			store: store
		)
		let folder = try makeVolumeFolder()
		defer { try? FileManager.default.removeItem(at: folder) }

		original[32] = 1
		try original.write(to: descriptor.localURL, options: .atomic)
		coordinator.selectVolume()
		await coordinator.write(to: folder)
		#expect(coordinator.state == .awaitingApplicationWrite)
		#expect(coordinator.errorMessage?.contains("firmware changed") == true)
		#expect(store.record?.phase == .awaitingApplicationWrite)

		try makeUF2(blockCount: 1, firstTargetAddress: 0x0002_7000)
			.write(to: descriptor.localURL, options: .atomic)
		let changedVolume = try makeVolumeFolder(softDevice: "S140 6.1.1")
		defer { try? FileManager.default.removeItem(at: changedVolume) }
		coordinator.selectVolume()
		await coordinator.write(to: changedVolume)
		#expect(coordinator.state == .awaitingApplicationWrite)
		#expect(store.record?.phase == .awaitingApplicationWrite)
	}

	@MainActor
	@Test("Interrupted writes resume forward and are never retried")
	func interruptedWritesResumeForward() async throws {
		let applicationData = makeUF2(blockCount: 1, firstTargetAddress: 0x0002_7000)
		try applicationData.write(to: descriptor.localURL, options: .atomic)
		defer { try? FileManager.default.removeItem(at: descriptor.localURL) }
		let identity = try UF2MaintenanceArtifactInspector.inspect(data: applicationData)
		let folder = try makeVolumeFolder()
		defer { try? FileManager.default.removeItem(at: folder) }

		let maintenanceStore = MemoryStore(record: makeRecord(phase: .writingMaintenance, identity: identity))
		let maintenanceCoordinator = UF2MaintenanceCoordinator(
			descriptor: descriptor,
			request: .bootloaderUpgrade,
			store: maintenanceStore,
			artifactLoad: { artifact, request in
				Issue.record("Interrupted maintenance must resume with the application pass")
				return (applicationData, makeMaintenanceIdentity(artifact, request, identity))
			}
		)
		#expect(maintenanceCoordinator.state == .awaitingApplicationWrite)
		#expect(maintenanceStore.record?.phase == .awaitingApplicationWrite)
		maintenanceCoordinator.selectVolume()
		await maintenanceCoordinator.write(to: folder)
		#expect(maintenanceCoordinator.state == .awaitingReconnect)
		#expect(maintenanceStore.record?.phase == .awaitingReconnect)

		let applicationStore = MemoryStore(record: makeRecord(phase: .writingApplication, identity: identity))
		let applicationCoordinator = UF2MaintenanceCoordinator(
			descriptor: descriptor,
			request: .bootloaderUpgrade,
			store: applicationStore
		)
		#expect(applicationCoordinator.state == .awaitingReconnect)
		#expect(applicationStore.record?.phase == .awaitingReconnect)
		#expect(!applicationCoordinator.canSelectVolume)
		#expect(applicationCoordinator.canStopTracking)
		applicationCoordinator.verify(reportedFirmwareVersion: "2.8.0.597f676")
		guard case .completed = applicationCoordinator.state else {
			Issue.record("Expected an interrupted application write to remain verifiable")
			return
		}
		#expect(applicationStore.record == nil)
	}

	@Test("Recovery state persists without device-profile data")
	func recoveryPersistence() throws {
		let suiteName = "UF2MaintenanceTests-\(UUID().uuidString)"
		let defaults = try #require(UserDefaults(suiteName: suiteName))
		defer { defaults.removePersistentDomain(forName: suiteName) }
		let store = UF2MaintenanceRecoveryStore(defaults: defaults)
		let identity = try UF2MaintenanceArtifactInspector.inspect(
			data: makeUF2(blockCount: 1, firstTargetAddress: 0x0002_7000)
		)
		let record = makeRecord(phase: .awaitingApplicationWrite, identity: identity)

		try store.save(record)
		#expect(store.load() == record)
		store.clear()
		#expect(store.load() == nil)
	}

	private func makeVolume() -> UF2VolumeIdentity {
		UF2VolumeIdentity(
			bootloaderVersion: "UF2 Bootloader 0.9.1",
			boardID: "nRF52840-T1000-E-v1",
			softDevice: "S140 7.3.0"
		)
	}

	private func makeVolumeFolder(
		boardID: String = "nRF52840-T1000-E-v1",
		softDevice: String = "S140 7.3.0"
	) throws -> URL {
		let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		try writeVolumeInfo(
			to: folder,
			bootloaderVersion: "UF2 Bootloader 0.9.1",
			boardID: boardID,
			softDevice: softDevice
		)
		return folder
	}

	private func writeVolumeInfo(
		to folder: URL,
		bootloaderVersion: String,
		boardID: String = "nRF52840-T1000-E-v1",
		softDevice: String = "S140 7.3.0"
	) throws {
		let info = """
		\(bootloaderVersion)
		Model: Seeed T1000-E for Meshtastic
		Board-ID: \(boardID)
		SoftDevice: \(softDevice)
		"""
		try info.write(to: folder.appendingPathComponent("INFO_UF2.TXT"), atomically: true, encoding: .utf8)
	}

	private func makeRecord(
		phase: UF2MaintenanceRecoveryRecord.Phase,
		identity: UF2FirmwareArtifactIdentity
	) -> UF2MaintenanceRecoveryRecord {
		UF2MaintenanceRecoveryRecord(
			id: UUID(),
			createdAt: Date(timeIntervalSince1970: 1_000),
			request: .bootloaderUpgrade,
			descriptor: descriptor,
			applicationArtifact: identity,
			phase: phase,
			volume: makeVolume(),
			maintenanceArtifact: nil,
			maintenanceCopyError: nil,
			applicationCopyError: nil,
			maintenanceVerified: nil
		)
	}

	private func makeMaintenanceIdentity(
		_ artifact: UF2MaintenanceArtifact,
		_ request: UF2MaintenanceRequest,
		_ identity: UF2FirmwareArtifactIdentity
	) -> UF2MaintenanceArtifactIdentity {
		UF2MaintenanceArtifactIdentity(
			request: request,
			fileName: artifact.fileName,
			sourceURL: nil,
			sha256: identity.sha256,
			byteCount: identity.byteCount,
			blockCount: identity.blockCount,
			firstTargetAddress: identity.firstTargetAddress,
			maximumTargetEnd: identity.maximumTargetEnd,
			familyID: identity.familyID
		)
	}

	private func makeUF2(
		blockCount: Int,
		firstTargetAddress: UInt32,
		familyID: UInt32 = 0xADA5_2840
	) -> Data {
		var data = Data(count: blockCount * 512)
		for index in 0..<blockCount {
			let offset = index * 512
			writeUInt32(0x0A32_4655, to: &data, at: offset)
			writeUInt32(0x9E5D_5157, to: &data, at: offset + 4)
			writeUInt32(0x0000_2000, to: &data, at: offset + 8)
			writeUInt32(firstTargetAddress + UInt32(index * 256), to: &data, at: offset + 12)
			writeUInt32(256, to: &data, at: offset + 16)
			writeUInt32(UInt32(index), to: &data, at: offset + 20)
			writeUInt32(UInt32(blockCount), to: &data, at: offset + 24)
			writeUInt32(familyID, to: &data, at: offset + 28)
			writeUInt32(0x0AB1_6F30, to: &data, at: offset + 508)
		}
		return data
	}

	private func writeUInt32(_ value: UInt32, to data: inout Data, at offset: Int) {
		var littleEndian = value.littleEndian
		withUnsafeBytes(of: &littleEndian) { bytes in
			data.replaceSubrange(offset..<(offset + 4), with: bytes)
		}
	}
}

private final class MemoryStore: UF2MaintenanceRecoveryStoring {
	var record: UF2MaintenanceRecoveryRecord?

	init(record: UF2MaintenanceRecoveryRecord? = nil) {
		self.record = record
	}

	func load() -> UF2MaintenanceRecoveryRecord? { record }
	func save(_ record: UF2MaintenanceRecoveryRecord) throws { self.record = record }
	func clear() { record = nil }
}
