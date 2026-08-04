// MultiRadioProductionWiringGuardTests.swift
// MeshtasticTests

import Foundation
import Testing

@Suite("Multi-radio production wiring guard")
struct MultiRadioProductionWiringGuardTests {
	@Test("production persistence opens the bootstrapped selected store")
	func productionPersistenceUsesBootstrap() throws {
		let source = try source("Meshtastic/Persistence/Persistence.swift")
		#expect(source.contains("MultiRadioStoreBootstrap.prepare(paths: paths)"))
		#expect(source.contains("selectedStoreKey: bootstrap.selectedStoreKey"))
	}

	@Test("connections preselect stores and MyInfo confirms canonical identity")
	func connectionFlowUsesCoordinator() throws {
		let connectSource = try source(
			"Meshtastic/Accessory/Accessory Manager/AccessoryManager+Connect.swift"
		)
		let ingestSource = try source(
			"Meshtastic/Accessory/Accessory Manager/AccessoryManager+FromRadio.swift"
		)

		#expect(connectSource.contains("try await prepareRadioStoreForConnection(to: device)"))
		#expect(connectSource.contains("radioStoreCoordinator.prepareForConnection("))
		#expect(ingestSource.contains("radioStoreCoordinator.confirmIdentity("))
		let managerSource = try source(
			"Meshtastic/Accessory/Accessory Manager/AccessoryManager.swift"
		)
		#expect(managerSource.contains("guard await handleMyInfo(myNodeInfo) else { return }"))
	}

	@Test("long-lived contexts retain containers and rebind after selection")
	func longLivedContextsRemainBoundToLiveContainers() throws {
		let accessoryManager = try source(
			"Meshtastic/Accessory/Accessory Manager/AccessoryManager.swift"
		)
		#expect(accessoryManager.contains("lazy var modelContainer = PersistenceController.shared.container"))
		#expect(accessoryManager.contains("context = modelContainer.mainContext"))

		let carPlay = try source("Meshtastic/CarPlay/CarPlaySceneDelegate.swift")
		#expect(carPlay.contains("private var modelContainer = PersistenceController.shared.container"))
		#expect(carPlay.contains("publisher(for: .radioStoreDidChange)"))
		#expect(carPlay.contains("self.context = self.modelContainer.mainContext"))

		let discovery = try source("Meshtastic/Services/DiscoveryScanEngine.swift")
		#expect(discovery.contains("modelContainer = modelContext.container"))
		let tak = try source("Meshtastic/Helpers/TAK/TAKMeshtasticBridge.swift")
		#expect(tak.contains("modelContainer = context?.container"))
	}

	@Test("stored contexts do not capture the persistence singleton directly")
	func storedContextsAvoidDirectSingletonCapture() throws {
		let repositoryRoot = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
		let sourceRoot = repositoryRoot.appendingPathComponent("Meshtastic", isDirectory: true)
		let pattern = #"(?:private(?:\(set\))?\s+var|(?:private\s+)?lazy\s+var)\s+\w+(?:\s*:\s*ModelContext)?\s*=\s*PersistenceController\.shared(?:\.context|\.container\.mainContext)"#
		let expression = try NSRegularExpression(pattern: pattern)
		var violations: [String] = []
		let enumerator = FileManager.default.enumerator(
			at: sourceRoot,
			includingPropertiesForKeys: [.isRegularFileKey],
			options: [.skipsHiddenFiles]
		)
		while let fileURL = enumerator?.nextObject() as? URL {
			guard fileURL.pathExtension == "swift" else { continue }
			let contents = try String(contentsOf: fileURL, encoding: .utf8)
			let range = NSRange(contents.startIndex..<contents.endIndex, in: contents)
			if expression.firstMatch(in: contents, range: range) != nil {
				violations.append(fileURL.lastPathComponent)
			}
		}
		#expect(violations.isEmpty, "Stored contexts captured PersistenceController.shared directly: \(violations)")
	}

	@Test("backups use the selected radio store and validate restore identity")
	func backupsRemainRadioScoped() throws {
		let backupSource = try source("Meshtastic/Persistence/NodeBackupManager.swift")
		#expect(backupSource.contains("PersistenceController.shared.activeRadioStoreURL"))
		#expect(backupSource.contains("sourceURL.path + \"-wal\""))
		#expect(backupSource.contains("sourceURL.path + \"-shm\""))
		let restoreSource = try source("Meshtastic/Views/Connect/Connect.swift")
		let identityCheck = try #require(restoreSource.range(of: "expectedDeviceID: backup.deviceID"))
		let destructiveClear = try #require(restoreSource.range(of: "clearDatabase(includeRoutes: false)"))
		#expect(identityCheck.lowerBound < destructiveClear.lowerBound)
	}

	@Test("radio-owned packets stay behind the identity gate")
	func ingestRemainsGated() throws {
		let source = try source(
			"Meshtastic/Accessory/Accessory Manager/AccessoryManager.swift"
		)
		#expect(source.contains("if !identityConfirmedForConnection"))
		#expect(source.contains("packetsPendingIdentity.append(decodedInfo)"))
		#expect(source.contains("let pending = packetsPendingIdentity"))
	}

	private func source(_ relativePath: String) throws -> String {
		let repositoryRoot = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
		return try String(
			contentsOf: repositoryRoot.appendingPathComponent(relativePath),
			encoding: .utf8
		)
	}
}
