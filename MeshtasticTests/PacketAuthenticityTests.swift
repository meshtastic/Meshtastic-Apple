// PacketAuthenticityTests.swift
// MeshtasticTests
//
// Covers the packet authenticity policy surfaced in Security config (design#121 / issue #2065):
//   - Config.SecurityConfig.packet_signature_policy (field 9) → SecurityConfigEntity.packetSignaturePolicy
//   - DeviceMetadata.has_xeddsa (field 14)                    → DeviceMetadataEntity.hasXeddsa
// The behavioral expectations mirror Android's PacketAuthenticitySettingTest (Meshtastic-Android#6178)
// so the two clients cannot drift apart on the wire contract or the Strict confirmation flow.

import Testing
import Foundation
import SwiftData
import MeshtasticProtobufs
@testable import Meshtastic

@Suite("Packet authenticity wire contract")
struct PacketAuthenticityWireTests {

	// MARK: - Defaults
	//
	// Compatible is the protobuf zero value. Firmware deliberately chose that ordering, so an absent
	// field must mean Compatible — if this flipped, a radio that never sent the field would silently
	// be treated as running a stricter receive policy than it actually is.

	@Test func policyDefaultsToCompatible() {
		#expect(Config.SecurityConfig().packetSignaturePolicy == .compatible)
	}

	@Test func policyRawValuesMatchTheShippedContract() {
		#expect(Config.SecurityConfig.PacketSignaturePolicy.compatible.rawValue == 0)
		#expect(Config.SecurityConfig.PacketSignaturePolicy.balanced.rawValue == 1)
		#expect(Config.SecurityConfig.PacketSignaturePolicy.strict.rawValue == 2)
	}

	// MARK: - Wire bytes (pin the field number and default omission)

	@Test func compatibleIsOmittedFromTheWire() throws {
		var config = Config.SecurityConfig()
		config.packetSignaturePolicy = .compatible
		#expect(try config.serializedData().isEmpty)
	}

	@Test func balancedEmitsField9Value1() throws {
		var config = Config.SecurityConfig()
		config.packetSignaturePolicy = .balanced
		// field 9, varint wire type: tag = (9 << 3) | 0 = 72 = 0x48; BALANCED = 1.
		#expect(Array(try config.serializedData()) == [0x48, 0x01])
	}

	@Test func strictEmitsField9Value2() throws {
		var config = Config.SecurityConfig()
		config.packetSignaturePolicy = .strict
		#expect(Array(try config.serializedData()) == [0x48, 0x02])
	}

	@Test func absentFieldDecodesAsCompatible() throws {
		let decoded = try Config.SecurityConfig(serializedBytes: [UInt8]())
		#expect(decoded.packetSignaturePolicy == .compatible)
	}

	@Test func unknownPolicyValueSurvivesARoundTrip() throws {
		// Newer firmware may add a level this app version predates. It must decode to .UNRECOGNIZED
		// and re-encode unchanged, so saving an unrelated setting cannot downgrade the radio's policy.
		let decoded = try Config.SecurityConfig(serializedBytes: [0x48, 0x07])
		#expect(decoded.packetSignaturePolicy == .UNRECOGNIZED(7))
		#expect(Array(try decoded.serializedData()) == [0x48, 0x07])
	}

	// MARK: - Capability field

	@Test func deviceMetadataHasXeddsaEmitsField14() throws {
		var metadata = DeviceMetadata()
		metadata.hasXeddsa_p = true
		// field 14, varint wire type: tag = (14 << 3) | 0 = 112 = 0x70; value true = 0x01.
		#expect(Array(try metadata.serializedData()) == [0x70, 0x01])
	}

	@Test func deviceMetadataHasXeddsaDefaultsFalseAndIsOmitted() throws {
		#expect(DeviceMetadata().hasXeddsa_p == false)
		#expect(try DeviceMetadata().serializedData().isEmpty)
	}
}

@Suite("Packet authenticity capability")
struct PacketAuthenticityCapabilityTests {

	@Test @MainActor func absentMetadataIsUnknownRatherThanUnsupported() {
		// A radio that has not answered the metadata request yet must not be described as lacking
		// the feature — hence the tri-state, matching Android's `supported: Boolean?`.
		#expect(PacketAuthenticityCapability(metadata: nil) == .unknown)
	}

	@Test @MainActor func metadataWithoutXeddsaIsUnsupported() {
		let context = TestContainerProvider.shared.mainContext
		let metadata = DeviceMetadataEntity()
		context.insert(metadata)
		#expect(metadata.hasXeddsa == false)
		#expect(PacketAuthenticityCapability(metadata: metadata) == .unsupported)
	}

	@Test @MainActor func metadataWithXeddsaIsSupported() {
		let context = TestContainerProvider.shared.mainContext
		let metadata = DeviceMetadataEntity()
		metadata.hasXeddsa = true
		context.insert(metadata)
		#expect(PacketAuthenticityCapability(metadata: metadata) == .supported)
	}

	@Test func onlySupportedAllowsChanges() {
		#expect(PacketAuthenticityCapability.supported.allowsChanges)
		#expect(!PacketAuthenticityCapability.unsupported.allowsChanges)
		#expect(!PacketAuthenticityCapability.unknown.allowsChanges)
	}

	@Test @MainActor func metadataIngestionCopiesTheCapability() {
		let context = TestContainerProvider.shared.mainContext
		let entity = DeviceMetadataEntity()
		context.insert(entity)

		var metadata = DeviceMetadata()
		metadata.firmwareVersion = "2.8.0.abcdef"
		metadata.hasXeddsa_p = true
		entity.update(from: metadata)
		#expect(entity.hasXeddsa == true)

		metadata.hasXeddsa_p = false
		entity.update(from: metadata)
		// Capability is read-only state reported by the radio, so it must follow the device rather
		// than latch — a downgrade to firmware without XEdDSA has to disable the selector again.
		#expect(entity.hasXeddsa == false)
	}
}

@Suite("Packet authenticity persistence")
struct PacketAuthenticityPersistenceTests {

	@Test @MainActor func entityDefaultsToCompatible() {
		let context = TestContainerProvider.shared.mainContext
		let config = SecurityConfigEntity()
		context.insert(config)
		#expect(config.packetSignaturePolicy == 0)
		#expect(config.storedPacketSignaturePolicy == .compatible)
	}

	@Test @MainActor func storedPolicyDecodesEachKnownLevel() {
		let context = TestContainerProvider.shared.mainContext
		let config = SecurityConfigEntity()
		context.insert(config)

		config.packetSignaturePolicy = 1
		#expect(config.storedPacketSignaturePolicy == .balanced)
		config.packetSignaturePolicy = 2
		#expect(config.storedPacketSignaturePolicy == .strict)
	}

	@Test @MainActor func storedPolicyPreservesAnUnknownLevel() {
		let context = TestContainerProvider.shared.mainContext
		let config = SecurityConfigEntity()
		context.insert(config)
		config.packetSignaturePolicy = 7
		#expect(config.storedPacketSignaturePolicy == .UNRECOGNIZED(7))
	}
}

/// Exercises the real ingestion path the Security screen reads from, rather than the entity alone:
/// a config arriving from the radio has to land in `SecurityConfigEntity.packetSignaturePolicy`,
/// on both the insert and the update branch of the upsert.
@Suite("Packet authenticity ingestion", .serialized)
struct PacketAuthenticityIngestionTests {

	@MainActor
	private func seedNode(_ nodeNum: Int64) throws {
		let context = PersistenceController.shared.context
		let descriptor = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == nodeNum })
		for existing in try context.fetch(descriptor) {
			context.delete(existing)
		}
		try context.save()

		let node = NodeInfoEntity()
		node.num = nodeNum
		context.insert(node)
		try context.save()
		MeshPackets.recreateShared()
	}

	@MainActor
	private func storedPolicy(_ nodeNum: Int64) throws -> Config.SecurityConfig.PacketSignaturePolicy? {
		let context = ModelContext(PersistenceController.shared.container)
		let descriptor = FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == nodeNum })
		return try context.fetch(descriptor).first?.securityConfig?.storedPacketSignaturePolicy
	}

	@Test @MainActor func upsertPersistsThePolicyWhenInsertingTheConfig() async throws {
		let nodeNum: Int64 = 0x00E0_0301
		try seedNode(nodeNum)

		var config = Config.SecurityConfig()
		// Balanced rather than Compatible: Compatible is the zero value, so it would pass even if
		// the field were never persisted at all.
		config.packetSignaturePolicy = .balanced
		await MeshPackets.shared.upsertSecurityConfigPacket(config: config, nodeNum: nodeNum)

		#expect(try storedPolicy(nodeNum) == .balanced)
	}

	@Test @MainActor func upsertPersistsThePolicyWhenUpdatingAnExistingConfig() async throws {
		let nodeNum: Int64 = 0x00E0_0302
		try seedNode(nodeNum)

		var config = Config.SecurityConfig()
		config.packetSignaturePolicy = .strict
		await MeshPackets.shared.upsertSecurityConfigPacket(config: config, nodeNum: nodeNum)
		#expect(try storedPolicy(nodeNum) == .strict)

		// Second pass takes the update branch, which is a separate assignment in the upsert.
		config.packetSignaturePolicy = .compatible
		await MeshPackets.shared.upsertSecurityConfigPacket(config: config, nodeNum: nodeNum)
		#expect(try storedPolicy(nodeNum) == .compatible)
	}
}

@Suite("Packet authenticity selection")
struct PacketAuthenticitySelectionStateTests {

	@Test func defaultsToCompatibleWithNothingPending() {
		let state = PacketAuthenticitySelectionState()
		#expect(state.selected == .compatible)
		#expect(!state.pendingStrict)
	}

	@Test func selectingBalancedCommitsImmediately() {
		var state = PacketAuthenticitySelectionState()
		state.propose(.balanced)
		#expect(state.selected == .balanced)
		#expect(!state.pendingStrict)
	}

	@Test func selectingStrictRequiresConfirmationBeforeCommitting() {
		var state = PacketAuthenticitySelectionState(selected: .balanced)
		state.propose(.strict)
		#expect(state.pendingStrict)
		#expect(state.selected == .balanced)
	}

	@Test func confirmingStrictCommitsIt() {
		var state = PacketAuthenticitySelectionState(selected: .balanced)
		state.propose(.strict)
		state.confirmStrict()
		#expect(state.selected == .strict)
		#expect(!state.pendingStrict)
	}

	@Test func cancellingStrictLeavesThePolicyUnchanged() {
		var state = PacketAuthenticitySelectionState(selected: .balanced)
		state.propose(.strict)
		state.cancelStrict()
		#expect(state.selected == .balanced)
		#expect(!state.pendingStrict)
	}

	@Test func confirmingWithNothingPendingIsANoOp() {
		// Guards the disconnect/capability-loss race: the section cancels the prompt, so a late
		// confirmation must not be able to enable Strict behind the user's back.
		var state = PacketAuthenticitySelectionState(selected: .compatible)
		state.confirmStrict()
		#expect(state.selected == .compatible)
		#expect(!state.pendingStrict)
	}

	@Test func reselectingTheCurrentStrictPolicyDoesNotPromptAgain() {
		var state = PacketAuthenticitySelectionState(selected: .strict)
		state.propose(.strict)
		#expect(!state.pendingStrict)
		#expect(state.selected == .strict)
	}

	@Test func leavingStrictCommitsWithoutPrompting() {
		var state = PacketAuthenticitySelectionState(selected: .strict)
		state.propose(.compatible)
		#expect(state.selected == .compatible)
		#expect(!state.pendingStrict)
	}

	@Test func proposingAnotherPolicyClearsAPendingStrictPrompt() {
		var state = PacketAuthenticitySelectionState(selected: .compatible)
		state.propose(.strict)
		state.propose(.balanced)
		#expect(state.selected == .balanced)
		#expect(!state.pendingStrict)
	}
}

@Suite("Packet authenticity picker options")
struct PacketAuthenticityPickerOptionTests {

	@Test func offersTheThreeShippedLevelsInOrder() {
		#expect(Config.SecurityConfig.PacketSignaturePolicy.packetAuthenticityOptions == [.compatible, .balanced, .strict])
	}

	@Test func knownSelectionDoesNotAddAnyOption() {
		let options = Config.SecurityConfig.PacketSignaturePolicy.pickerOptions(includingCurrent: .balanced)
		#expect(options == [.compatible, .balanced, .strict])
	}

	@Test func unrecognizedSelectionIsAppendedSoThePickerCanRenderIt() {
		// A SwiftUI Picker whose bound selection has no matching tag renders no selection at all,
		// which would hide the policy the radio is actually enforcing.
		let current = Config.SecurityConfig.PacketSignaturePolicy.UNRECOGNIZED(7)
		let options = Config.SecurityConfig.PacketSignaturePolicy.pickerOptions(includingCurrent: current)
		#expect(options == [.compatible, .balanced, .strict, current])
	}

	@Test func everyShippedLevelHasDistinctCopy() {
		let titles = Config.SecurityConfig.PacketSignaturePolicy.packetAuthenticityOptions.map(\.packetAuthenticityTitle)
		let descriptions = Config.SecurityConfig.PacketSignaturePolicy.packetAuthenticityOptions.map(\.packetAuthenticityDescription)
		#expect(Set(titles).count == titles.count)
		#expect(Set(descriptions).count == descriptions.count)
		#expect(!titles.contains { $0.isEmpty })
		#expect(!descriptions.contains { $0.isEmpty })
	}
}
