// MARK: DiscoveryScanEngineTests

import Foundation
import Testing
import MeshtasticProtobufs
import SwiftData

@testable import Meshtastic

@Suite("DiscoveryScanEngine")
struct DiscoveryScanEngineTests {

	// MARK: - Initial State

	@Test func initialStateIsIdle() async {
		let engine = await DiscoveryScanEngine()
		let state = await engine.currentState
		#expect(state == .idle)
	}

	@Test func isScanningFalseWhenIdle() async {
		let engine = await DiscoveryScanEngine()
		let scanning = await engine.isScanning
		#expect(!scanning)
	}

	@Test func defaultDwellDurationIs900() async {
		let engine = await DiscoveryScanEngine()
		let dwell = await engine.dwellDuration
		#expect(dwell == 900)
	}

	// MARK: - Start Scan Guards

	@Test func startScanFailsWithNoPresets() async {
		let engine = await DiscoveryScanEngine()
		await engine.startScan()
		let state = await engine.currentState
		#expect(state == .idle)
	}

	@Test func startScanFailsWithoutConnection() async {
		let engine = await DiscoveryScanEngine()
		await MainActor.run {
			engine.selectedPresets = [.longFast]
		}
		await engine.startScan()
		let state = await engine.currentState
		#expect(state == .idle)
	}

	/// A normal multi-preset scan changes the radio's preset, so it must stay gated on a live
	/// connection even when the engine is fully configured with a model context.
	@MainActor
	@Test func normalScanStillRequiresConnectionWhenConfigured() async {
		let engine = DiscoveryScanEngine()
		let manager = AccessoryManager(transports: [])
		engine.configure(accessoryManager: manager, modelContext: sharedModelContainer.mainContext)
		#expect(!manager.isConnected)
		engine.selectedPresets = [.longFast]
		await engine.startScan()
		#expect(engine.currentState == .idle, "A normal multi-preset scan must not start without a connection")
		withExtendedLifetime(manager) {}
	}

	/// "Analyze Current Preset" (FR-028) is seeded entirely from local SwiftData and sends nothing
	/// to the radio, so it MUST run with no radio connected. A fresh AccessoryManager reports
	/// isConnected == false, standing in for the offline case.
	@MainActor
	@Test func analyzeCurrentPresetStartsAndEndsCleanlyWithoutConnection() async {
		let engine = DiscoveryScanEngine()
		let manager = AccessoryManager(transports: [])
		engine.configure(accessoryManager: manager, modelContext: sharedModelContainer.mainContext)
		#expect(!manager.isConnected)

		await engine.startCurrentPresetScan()
		// Seeded pass begins dwelling immediately — no connection required, no config change.
		#expect(engine.currentState == .dwell)
		#expect(engine.activePreset != nil)
		#expect(engine.session != nil)

		await engine.stopScan()
		// Tears down cleanly back to idle without any radio calls (nothing was snapshotted).
		#expect(engine.currentState == .idle)
		withExtendedLifetime(manager) {}
	}

	// MARK: - State Enumeration

	@Test func allScanStatesExist() {
		let states: [DiscoveryScanState] = [
			.idle, .shifting, .reconnecting, .dwell,
			.analysis, .complete, .paused, .restoring
		]
		#expect(states.count == 8)
	}

	@Test func scanStatesEquality() {
		#expect(DiscoveryScanState.idle == DiscoveryScanState.idle)
		#expect(DiscoveryScanState.dwell != DiscoveryScanState.shifting)
	}

	// MARK: - isScanning States

	@Test func activeScanStatesReturnTrue() async {
		let engine = await DiscoveryScanEngine()
		// Test via the computed property definition
		let activeStates: [DiscoveryScanState] = [.shifting, .reconnecting, .dwell, .paused, .restoring]
		for state in activeStates {
			await MainActor.run {
				engine.currentState = state
			}
			let scanning = await engine.isScanning
			#expect(scanning, "Expected isScanning=true for state \(state)")
		}
	}

	@Test func inactiveScanStatesReturnFalse() async {
		let engine = await DiscoveryScanEngine()
		let inactiveStates: [DiscoveryScanState] = [.idle, .analysis, .complete]
		for state in inactiveStates {
			await MainActor.run {
				engine.currentState = state
			}
			let scanning = await engine.isScanning
			#expect(!scanning, "Expected isScanning=false for state \(state)")
		}
	}

	// MARK: - Reconnect timeout resolution (#1952 item 3)

	@Test func reconnectTimeoutResolvesToDwellOnlyWhenConnectedAndSubscribed() {
		// Connected & subscribed → resume dwelling (covers a missed disconnect edge that
		// previously left the scan hung on one preset and never rotating).
		#expect(DiscoveryScanEngine.reconnectTimeoutResolution(isConnected: true, isSubscribed: true) == .dwell)
		// Anything short of fully connected → pause (link genuinely down).
		#expect(DiscoveryScanEngine.reconnectTimeoutResolution(isConnected: false, isSubscribed: false) == .paused)
		#expect(DiscoveryScanEngine.reconnectTimeoutResolution(isConnected: true, isSubscribed: false) == .paused)
		#expect(DiscoveryScanEngine.reconnectTimeoutResolution(isConnected: false, isSubscribed: true) == .paused)
	}
}

// MARK: - LoRa config preservation (#1952)

/// `loRaConfigProto` is the full-fidelity copy used to snapshot the user's config at scan
/// start and restore it verbatim afterward, so it must carry through every LoRa field. Building
/// a partial config previously zeroed omitted fields on the device — bandwidth, coding rate,
/// MQTT flags, etc. — wiping the user's settings and never restoring them. These lock in that
/// `loRaConfigProto` preserves the full config.
///
/// Note: the per-preset config the scan actually sends forces the default frequency slot
/// (`channelNum = 0`) in `sendPresetChange` so the firmware auto-derives each preset's
/// frequency; the user's real slot lives only in the snapshot and is restored when the scan
/// ends. `loRaConfigProto` itself never zeroes the slot — that override is applied at send time.
@MainActor
@Suite("DiscoveryScanEngine LoRa config preservation (#1952)")
struct DiscoveryScanEngineLoRaConfigTests {

	/// A config entity with distinctive non-default values in every field.
	private func makeEntity() -> LoRaConfigEntity {
		let entity = LoRaConfigEntity()
		entity.modemPreset = Int32(ModemPresets.longFast.rawValue)
		entity.regionCode = 1 // US
		entity.usePreset = true
		entity.hopLimit = 5
		entity.txEnabled = true
		entity.txPower = 27
		entity.channelNum = 20
		entity.bandwidth = 250
		entity.codingRate = 8
		entity.spreadFactor = 11
		entity.frequencyOffset = 1.5
		entity.overrideFrequency = 915.0
		entity.overrideDutyCycle = true
		entity.sx126xRxBoostedGain = true
		entity.ignoreMqtt = true
		entity.okToMqtt = true
		return entity
	}

	@Test("loRaConfigProto overrides only the preset and carries through every other field")
	func presetChangePreservesAllFields() {
		let engine = DiscoveryScanEngine()
		let config = engine.loRaConfigProto(from: makeEntity(), presetOverride: .longSlow)

		// Only the modem preset changes.
		#expect(config.modemPreset == ModemPresets.longSlow.protoEnumValue())
		// Everything else is carried through (the #1952 bug zeroed these). The frequency slot is
		// preserved here for the snapshot/restore path; the scan send path zeroes it separately.
		#expect(config.channelNum == 20)
		#expect(config.region.rawValue == 1)
		#expect(config.usePreset)
		#expect(config.hopLimit == 5)
		#expect(config.txEnabled)
		#expect(config.txPower == 27)
		#expect(config.bandwidth == 250)
		#expect(config.codingRate == 8)
		#expect(config.spreadFactor == 11)
		#expect(config.frequencyOffset == 1.5)
		#expect(config.overrideFrequency == 915.0)
		#expect(config.overrideDutyCycle)
		#expect(config.sx126XRxBoostedGain)
		#expect(config.ignoreMqtt)
		#expect(config.configOkToMqtt)
	}

	@Test("Home snapshot (no override) keeps the entity's own preset and frequency slot")
	func homeSnapshotKeepsPresetAndSlot() {
		let engine = DiscoveryScanEngine()
		let config = engine.loRaConfigProto(from: makeEntity(), presetOverride: nil)
		#expect(config.modemPreset == ModemPresets.longFast.protoEnumValue())
		#expect(config.channelNum == 20)
	}
}
