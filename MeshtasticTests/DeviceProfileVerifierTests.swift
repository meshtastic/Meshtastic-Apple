//
//  DeviceProfileVerifierTests.swift
//  MeshtasticTests
//

import Foundation
import Testing
import MeshtasticProtobufs
@testable import Meshtastic

@Suite("DeviceProfile verification")
struct DeviceProfileVerifierTests {

	// MARK: - Source double

	@MainActor
	private final class MockSource: ProfileConfigSource {
		var payloads: [ImportItemKind: ImportPayload] = [:]
		var lastConfigRefresh: Date?
		func currentPayload(for kind: ImportItemKind) -> ImportPayload? { payloads[kind] }
	}

	private func planWith(telemetry: ModuleConfig.TelemetryConfig? = nil,
						  device: Config.DeviceConfig? = nil,
						  neighborInfo: ModuleConfig.NeighborInfoConfig? = nil) throws -> DeviceProfileImportPlan {
		var profile = DeviceProfile()
		if let device {
			var config = LocalConfig(); config.device = device; profile.config = config
		}
		var module = LocalModuleConfig()
		if let telemetry { module.telemetry = telemetry }
		if let neighborInfo { module.neighborInfo = neighborInfo }
		if telemetry != nil || neighborInfo != nil { profile.moduleConfig = module }
		return try DeviceProfileImportPlan(profile: profile, currentUser: nil)
	}

	// MARK: - Verification readiness

	@Test("A refresh received during import verifies when the result is published, then only once")
	func refreshDuringImportTriggersVerificationOnResultPublicationOnce() {
		let importStartedAt = Date()
		let refreshDuringImport = importStartedAt.addingTimeInterval(1)

		// The refresh alone cannot trigger before the importer publishes whether a reconnect is expected.
		let beforeResult = DeviceProfileVerificationReadiness(
			expectsReconnect: false,
			refreshNotBefore: importStartedAt,
			lastConfigRefresh: refreshDuringImport,
			hasVerification: false
		)
		#expect(!beforeResult.shouldVerify)

		// Publishing the rebooting result must consume the refresh that arrived while apply was suspended.
		let resultPublished = DeviceProfileVerificationReadiness(
			expectsReconnect: true,
			refreshNotBefore: importStartedAt,
			lastConfigRefresh: refreshDuringImport,
			hasVerification: false
		)
		#expect(resultPublished.shouldVerify)

		// Once verification is recorded, another refresh must not run it again.
		let afterLaterRefresh = DeviceProfileVerificationReadiness(
			expectsReconnect: true,
			refreshNotBefore: importStartedAt,
			lastConfigRefresh: refreshDuringImport.addingTimeInterval(1),
			hasVerification: true
		)
		#expect(!afterLaterRefresh.shouldVerify)
	}

	@Test("A refresh before a later deferred item does not trigger verification")
	func refreshBeforeDeferredItemDoesNotTriggerVerification() {
		let importStartedAt = Date()
		let channelRefresh = importStartedAt.addingTimeInterval(1)
		let deferredItemStartedAt = importStartedAt.addingTimeInterval(2)

		let resultPublished = DeviceProfileVerificationReadiness(
			expectsReconnect: true,
			refreshNotBefore: deferredItemStartedAt,
			lastConfigRefresh: channelRefresh,
			hasVerification: false
		)
		#expect(!resultPublished.shouldVerify)

		let refreshAfterDeferredItem = DeviceProfileVerificationReadiness(
			expectsReconnect: true,
			refreshNotBefore: deferredItemStartedAt,
			lastConfigRefresh: deferredItemStartedAt.addingTimeInterval(1),
			hasVerification: false
		)
		#expect(refreshAfterDeferredItem.shouldVerify)
	}

	@Test("Stale and non-reboot imports do not trigger verification")
	func staleOrNonRebootImportsDoNotTriggerVerification() {
		let importStartedAt = Date()
		let stale = DeviceProfileVerificationReadiness(
			expectsReconnect: true,
			refreshNotBefore: importStartedAt,
			lastConfigRefresh: importStartedAt.addingTimeInterval(-1),
			hasVerification: false
		)
		#expect(!stale.shouldVerify)

		let noReboot = DeviceProfileVerificationReadiness(
			expectsReconnect: false,
			refreshNotBefore: importStartedAt,
			lastConfigRefresh: importStartedAt.addingTimeInterval(1),
			hasVerification: false
		)
		#expect(!noReboot.shouldVerify)
	}

	// MARK: - Staleness gate

	@MainActor
	@Test("Verification refuses to run against a readback older than the import")
	func staleReadbackIsRefused() throws {
		var telemetry = ModuleConfig.TelemetryConfig()
		telemetry.deviceUpdateInterval = 1800
		let plan = try planWith(telemetry: telemetry)

		let source = MockSource()
		source.payloads[.telemetry] = .telemetry(telemetry)
		let importedAt = Date()
		source.lastConfigRefresh = importedAt.addingTimeInterval(-60)   // refreshed BEFORE the import

		let report = DeviceProfileVerifier.verify(applied: [.telemetry], plan: plan, before: [:],
												  source: source, readbackNotBefore: importedAt)
		// A stale cache still holds pre-import values, which would read as a total wipe. Reporting
		// "everything dropped" there would be worse than reporting nothing.
		#expect(report.unavailable != nil)
		#expect(report.outcomes.isEmpty)
		#expect(!report.isClean)
	}

	@MainActor
	@Test("Verification refuses when the app has never received a config")
	func noReadbackAtAllIsRefused() throws {
		let plan = try planWith(telemetry: ModuleConfig.TelemetryConfig())
		let source = MockSource()
		source.lastConfigRefresh = nil
		let report = DeviceProfileVerifier.verify(applied: [.telemetry], plan: plan, before: [:],
												  source: source, readbackNotBefore: Date())
		#expect(report.unavailable != nil)
	}

	// MARK: - Core classification

	@MainActor
	@Test("A setting the radio now reports is applied")
	func matchingValueIsApplied() throws {
		var telemetry = ModuleConfig.TelemetryConfig()
		telemetry.deviceUpdateInterval = 1800
		let plan = try planWith(telemetry: telemetry)

		let source = MockSource()
		source.payloads[.telemetry] = .telemetry(telemetry)
		source.lastConfigRefresh = Date().addingTimeInterval(60)

		let report = DeviceProfileVerifier.verify(applied: [.telemetry], plan: plan, before: [:],
												  source: source, readbackNotBefore: Date())
		#expect(report.applied == [.telemetry])
		#expect(report.isClean)
	}

	@MainActor
	@Test("A section the radio never received reads as likely dropped")
	func unchangedSectionIsLikelyDropped() throws {
		var sent = ModuleConfig.TelemetryConfig()
		sent.deviceUpdateInterval = 1800
		let plan = try planWith(telemetry: sent)

		var previous = ModuleConfig.TelemetryConfig()
		previous.deviceUpdateInterval = 3600

		let source = MockSource()
		source.payloads[.telemetry] = .telemetry(previous)   // radio still reports the OLD value
		source.lastConfigRefresh = Date().addingTimeInterval(60)

		let report = DeviceProfileVerifier.verify(applied: [.telemetry], plan: plan,
												  before: [.telemetry: .telemetry(previous)],
												  source: source, readbackNotBefore: Date())
		#expect(report.likelyDropped == [.telemetry])
		#expect(!report.isClean)
	}

	// MARK: - Firmware normalization

	@MainActor
	@Test("Firmware normalizing a sentinel back to its default is NOT reported as dropped")
	func normalizationIsNotAFalseDrop() throws {
		// The observed case: neighbor_info.update_interval sent as 0, radio reports its default 21600,
		// and `before` was already 21600. A whole-message rule of "after == before means dropped" flags
		// this as a failure even though the write applied. Restricting comparison to fields the profile
		// set to a NON-DEFAULT value excludes the 0 entirely, so there is nothing to misjudge.
		var sent = ModuleConfig.NeighborInfoConfig()
		sent.enabled = true
		sent.updateInterval = 0            // proto3 default: carries no signal

		var reported = ModuleConfig.NeighborInfoConfig()
		reported.enabled = true
		reported.updateInterval = 21600    // firmware normalized it

		let plan = try planWith(neighborInfo: sent)
		let source = MockSource()
		source.payloads[.neighborInfo] = .neighborInfo(reported)
		source.lastConfigRefresh = Date().addingTimeInterval(60)

		let report = DeviceProfileVerifier.verify(applied: [.neighborInfo], plan: plan,
												  before: [.neighborInfo: .neighborInfo(reported)],
												  source: source, readbackNotBefore: Date())
		#expect(report.likelyDropped.isEmpty)
		#expect(report.applied == [.neighborInfo])
		#expect(report.isClean)
	}

	@MainActor
	@Test("A profile that sets only default values is not comparable")
	func onlyDefaultsIsNotComparable() throws {
		let sent = ModuleConfig.TelemetryConfig()   // every field at its proto3 default
		let plan = try planWith(telemetry: sent)
		let source = MockSource()
		source.payloads[.telemetry] = .telemetry(sent)
		source.lastConfigRefresh = Date().addingTimeInterval(60)

		let report = DeviceProfileVerifier.verify(applied: [.telemetry], plan: plan, before: [:],
												  source: source, readbackNotBefore: Date())
		#expect(report.notComparable == [.telemetry])
		#expect(report.isClean)   // absence of signal is not a failure
	}

	@MainActor
	@Test("Partial application is inconclusive rather than a pass or a failure")
	func partialApplicationIsInconclusive() throws {
		var sent = Config.DeviceConfig()
		sent.nodeInfoBroadcastSecs = 900
		sent.buttonGpio = 7
		let plan = try planWith(device: sent)

		var reported = Config.DeviceConfig()
		reported.nodeInfoBroadcastSecs = 900   // landed
		reported.buttonGpio = 2                // neither sent nor previous
		var previous = Config.DeviceConfig()
		previous.buttonGpio = 1

		let source = MockSource()
		source.payloads[.deviceConfig] = .deviceConfig(reported)
		source.lastConfigRefresh = Date().addingTimeInterval(60)

		let report = DeviceProfileVerifier.verify(applied: [.deviceConfig], plan: plan,
												  before: [.deviceConfig: .deviceConfig(previous)],
												  source: source, readbackNotBefore: Date())
		#expect(report.inconclusive == [.deviceConfig])
		#expect(report.likelyDropped.isEmpty)
		#expect(report.isClean)   // not proof of loss
	}

	// MARK: - Unreadable kinds

	@MainActor
	@Test("Kinds the radio never echoes back are reported, not silently omitted")
	func unreadableKindsAreReported() throws {
		var profile = DeviceProfile()
		profile.ringtone = "a:d=4,o=5,b=100:c"
		profile.cannedMessages = "hi|bye"
		let plan = try DeviceProfileImportPlan(profile: profile, currentUser: nil)

		let source = MockSource()
		source.lastConfigRefresh = Date().addingTimeInterval(60)

		let report = DeviceProfileVerifier.verify(applied: [.ringtone, .cannedMessagesText], plan: plan,
												  before: [:], source: source, readbackNotBefore: Date())
		// Silently dropping these from the report invites "did my ringtone apply?" confusion.
		#expect(Set(report.notComparable) == [.ringtone, .cannedMessagesText])
		#expect(report.outcomes.count == 2)
	}
}
