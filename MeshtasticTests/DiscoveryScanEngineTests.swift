// MARK: DiscoveryScanEngineTests

import Foundation
import Testing
import MeshtasticProtobufs

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
}

// MARK: - LoRa config preservation (#1952)

/// The scan changes only the modem preset; it must carry through every other LoRa field.
/// Building a partial config previously zeroed omitted fields on the device — notably
/// `channelNum` (frequency slot) → 0 — moving the radio off the user's frequency and wiping
/// their settings, and never restoring them. These lock in that `loRaConfigProto` preserves
/// the full config.
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

	@Test("Preset change preserves the frequency slot and every other LoRa field")
	func presetChangePreservesAllFields() {
		let engine = DiscoveryScanEngine()
		let config = engine.loRaConfigProto(from: makeEntity(), presetOverride: .longSlow)

		// Only the modem preset changes.
		#expect(config.modemPreset == ModemPresets.longSlow.protoEnumValue())
		// Everything else is carried through (the #1952 bug zeroed these).
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
