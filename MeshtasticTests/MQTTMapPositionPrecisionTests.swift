// Issue #2259: MQTT map precision 15 (about 700 m) must be saveable and survive readback.
// Firmware accepts values 12...15 and defaults unsupported values to 14.

import Foundation
import MeshtasticProtobufs
import SwiftData
import Testing

@testable import Meshtastic

@Suite("MQTT map position precision")
struct MQTTMapPositionPrecisionTests {
	@Test(arguments: [12.0, 13.0, 14.0, 15.0])
	func acceptsFirmwareSupportedValues(_ value: Double) {
		#expect(MQTTMapPositionPrecision.normalized(value) == value)
	}

	@Test(arguments: [0.0, 11.0, 16.0, 32.0])
	func defaultsUnsupportedValues(_ value: Double) {
		#expect(MQTTMapPositionPrecision.normalized(value) == MQTTMapPositionPrecision.defaultValue)
	}

	@Test func userChangesFromStoredValueMarkConfigDirty() {
		#expect(MQTTMapPositionPrecision.hasChanged(from: 14, to: 15, storedValue: 14))
		#expect(MQTTMapPositionPrecision.hasChanged(from: 15, to: 12, storedValue: 15))
	}

	@Test func loadingStoredValueDoesNotMarkConfigDirty() {
		#expect(MQTTMapPositionPrecision.hasChanged(from: 14, to: 15, storedValue: 15) == false)
	}

	@Test func normalizingUnsupportedValueDoesNotMarkConfigDirty() {
		#expect(MQTTMapPositionPrecision.hasChanged(from: 14, to: 14, storedValue: 11) == false)
		#expect(MQTTMapPositionPrecision.hasChanged(from: 14, to: 14, storedValue: 32) == false)
	}

	@Test func editingUnsupportedStoredValueKeepsConfigDirtyAfterReturningToEffectiveDefault() {
		var hasChanges = false
		if MQTTMapPositionPrecision.hasChanged(from: 14, to: 15, storedValue: 0) {
			hasChanges = true
		}
		if MQTTMapPositionPrecision.hasChanged(from: 15, to: 14, storedValue: 0) {
			hasChanges = true
		}

		#expect(hasChanges)
	}

	@Test func savingUnrelatedChangePreservesStoredPrecisionUntilSliderIsEdited() {
		#expect(MQTTMapPositionPrecision.valueForSave(displayedValue: 14, storedValue: 0, wasEdited: false) == 0)
		#expect(MQTTMapPositionPrecision.valueForSave(displayedValue: 14, storedValue: 11, wasEdited: false) == 11)
		#expect(MQTTMapPositionPrecision.valueForSave(displayedValue: 14, storedValue: 32, wasEdited: false) == 32)
		#expect(MQTTMapPositionPrecision.valueForSave(displayedValue: 15, storedValue: 0, wasEdited: true) == 15)
		#expect(MQTTMapPositionPrecision.valueForSave(displayedValue: 14, storedValue: 0, wasEdited: true) == 14)
	}

	@Test @MainActor func sevenHundredMeterPrecisionSurvivesProtoAndPersistenceRoundTrip() async throws {
		let container = try ModelContainer(
			for: Schema(MeshtasticSchema.allModels),
			configurations: ModelConfiguration(isStoredInMemoryOnly: true)
		)
		let context = ModelContext(container)
		let node = NodeInfoEntity()
		node.num = 2_259
		context.insert(node)
		try context.save()

		var config = ModuleConfig.MQTTConfig()
		config.mapReportSettings.positionPrecision = 15
		#expect(config.hasMapReportSettings)

		let decoded = try ModuleConfig.MQTTConfig(serializedData: config.serializedData())
		let mesh = MeshPackets(modelContainer: container)
		await mesh.upsertMqttModuleConfigPacket(config: decoded, nodeNum: node.num)
		await mesh.flushDebouncedSaves()

		let nodeNum = node.num
		var descriptor = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == nodeNum })
		descriptor.fetchLimit = 1
		let persistedNodes = try ModelContext(container).fetch(descriptor)
		let persistedConfig = try #require(persistedNodes.first?.mqttConfig)

		#expect(persistedConfig.mapPositionPrecision == 15)
		#expect(MQTTMapPositionPrecision.normalized(Double(persistedConfig.mapPositionPrecision)) == 15)
	}
}
