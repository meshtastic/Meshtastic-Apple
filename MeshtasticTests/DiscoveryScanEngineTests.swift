// MARK: DiscoveryScanEngineTests

import Foundation
import Testing
import MeshtasticProtobufs
import SwiftData

@testable import Meshtastic

@Suite("ScanTarget")
struct ScanTargetTests {

	@Test func publicTargetIsNotCustomAndLabelsByPreset() {
		let target = ScanTarget(preset: .longFast)
		#expect(target.isCustomChannel == false)
		#expect(target.label == ModemPresets.longFast.name)
	}

	@Test func emptyChannelNameIsNotCustom() {
		let target = ScanTarget(preset: .longFast, channelName: "", channelPSK: Data())
		#expect(target.isCustomChannel == false)
		#expect(target.label == ModemPresets.longFast.name)
	}

	@Test func customChannelTargetLabelsWithChannel() {
		let target = ScanTarget(preset: .shortFast, channelName: "SecretMesh", channelPSK: Data([1, 2, 3]))
		#expect(target.isCustomChannel)
		#expect(target.label == "\(ModemPresets.shortFast.name) · SecretMesh")
	}

	// Two beacon targets on the same preset but different channels must be distinct so their results
	// and discovered nodes don't collide (labels differ, and Equatable sees the channel difference).
	@Test func samePresetDifferentChannelAreDistinct() {
		let a = ScanTarget(preset: .longFast, channelName: "MeshA", channelPSK: Data([1]))
		let b = ScanTarget(preset: .longFast, channelName: "MeshB", channelPSK: Data([2]))
		#expect(a != b)
		#expect(a.label != b.label)
	}

	@Test func equalTargetsMatch() {
		let a = ScanTarget(preset: .longFast, regionRaw: 1, channelName: "M", channelPSK: Data([9]))
		let b = ScanTarget(preset: .longFast, regionRaw: 1, channelName: "M", channelPSK: Data([9]))
		#expect(a == b)
	}

	// MARK: - Targets built from a beacon

	@Test func beaconTargetCarriesThePinnedSlot() {
		let target = ScanTarget.beacon(
			offeredPreset: .longFast,
			offerRegion: RegionCodes.us.rawValue,
			channel: ("M", Data([9])),
			frequencySlot: 20,
			radioRegion: RegionCodes.us.rawValue,
			regionPresets: [:]
		)
		#expect(target?.frequencySlot == 20)
		#expect(target?.regionRaw == RegionCodes.us.rawValue)
		#expect(target?.isCustomChannel == true)
	}

	@Test func beaconTargetWithoutASlotLeavesItToTheFirmware() {
		let target = ScanTarget.beacon(
			offeredPreset: .longFast,
			offerRegion: 0,
			channel: ("M", Data([9])),
			frequencySlot: nil,
			radioRegion: RegionCodes.us.rawValue,
			regionPresets: [:]
		)
		#expect(target?.frequencySlot == nil)
		#expect(target?.regionRaw == nil)
	}

	@Test func beaconTargetWithASlotPastTheRegionIsDropped() {
		// No region advertised, so the slot is checked against the radio's own region.
		let target = ScanTarget.beacon(
			offeredPreset: .longFast,
			offerRegion: 0,
			channel: ("M", Data([9])),
			frequencySlot: 500,
			radioRegion: RegionCodes.us.rawValue,
			regionPresets: [:]
		)
		#expect(target == nil)
	}

	@Test func beaconTargetWithoutAPresetUsesTheRegionDefault() {
		let usTurbo = RegionPresetInfo(presets: [.longFast, .longTurbo], defaultPreset: .longTurbo, licensedOnly: false)
		let target = ScanTarget.beacon(
			offeredPreset: nil,
			offerRegion: RegionCodes.us.rawValue,
			channel: nil,
			frequencySlot: nil,
			radioRegion: RegionCodes.us.rawValue,
			regionPresets: [.us: usTurbo]
		)
		#expect(target?.preset == .longTurbo)
		#expect(target?.isCustomChannel == false)
	}

	@Test func aSlotCheckedAgainstTheRadioRegionKeepsThatRegion() {
		// The slot was validated for US, so the target must apply it in US even if an earlier
		// target has moved the radio to another region.
		let target = ScanTarget.beacon(
			offeredPreset: .longFast,
			offerRegion: 0,
			channel: nil,
			frequencySlot: 20,
			radioRegion: RegionCodes.us.rawValue,
			regionPresets: [:]
		)
		#expect(target?.frequencySlot == 20)
		#expect(target?.regionRaw == RegionCodes.us.rawValue)
	}

	@Test func aUSSlotIsNotCarriedIntoEU868() {
		// Slot 20 exists in US but not in EU868's single LongFast slot. Checked against US it keeps
		// US, so a queued EU868 target ahead of it can't leave the radio applying slot 20 in EU868.
		let us = ScanTarget.beacon(
			offeredPreset: .longFast, offerRegion: 0, channel: nil, frequencySlot: 20,
			radioRegion: RegionCodes.us.rawValue
		)
		#expect(us?.regionRaw == RegionCodes.us.rawValue)
		let eu = ScanTarget.beacon(
			offeredPreset: .longFast, offerRegion: 0, channel: nil, frequencySlot: 20,
			radioRegion: RegionCodes.eu868.rawValue
		)
		#expect(eu == nil)
	}

	@Test func aPinnedSlotBeaconIsNotTheActivePresetDwell() {
		// Heard during a plain LongFast dwell, a beacon pinning LongFast slot 20 is a different
		// target with a different results key, so it still gets queued.
		let active = ScanTarget(preset: .longFast)
		let beacon = ScanTarget.beacon(
			offeredPreset: .longFast, offerRegion: 0, channel: nil, frequencySlot: 20,
			radioRegion: RegionCodes.us.rawValue
		)
		#expect(beacon != nil)
		#expect(beacon != active)
		#expect(beacon?.label != active.label)
	}

	// MARK: - Labels key results, so a pinned slot must show in them

	@Test func pinnedSlotIsInTheLabel() {
		#expect(ScanTarget(preset: .longFast, frequencySlot: 20).label == "\(ModemPresets.longFast.name) · slot 20")
		let custom = ScanTarget(preset: .longFast, channelName: "M", channelPSK: Data([9]), frequencySlot: 3)
		#expect(custom.label == "\(ModemPresets.longFast.name) · M · slot 3")
	}

	@Test func samePresetDifferentSlotAreDistinct() {
		let derived = ScanTarget(preset: .longFast)
		let pinned = ScanTarget(preset: .longFast, regionRaw: RegionCodes.us.rawValue, frequencySlot: 20)
		let other = ScanTarget(preset: .longFast, regionRaw: RegionCodes.us.rawValue, frequencySlot: 21)
		#expect(Set([derived.label, pinned.label, other.label]).count == 3)
	}

	// MARK: - Saved beacon offers in the scan setup

	@MainActor @Test func savedPublicOfferKeepsItsPinnedSlot() {
		let beacon = DiscoveredBeaconEntity()
		beacon.offerPreset = ModemPresets.longFast.rawValue
		beacon.offerFrequencySlot = 42
		let row = DiscoveryScanView.BeaconChannel(beacon: beacon, radioRegion: RegionCodes.us.rawValue, regionPresets: [:])
		#expect(row?.name == "")
		#expect(row?.scanTarget.isCustomChannel == false)
		#expect(row?.scanTarget.frequencySlot == 42)
		#expect(row?.scanTarget.regionRaw == RegionCodes.us.rawValue)
	}

	@MainActor @Test func savedPublicOfferWithoutASlotIsLeftToThePresetChips() {
		let beacon = DiscoveredBeaconEntity()
		beacon.offerPreset = ModemPresets.longFast.rawValue
		#expect(DiscoveryScanView.BeaconChannel(beacon: beacon, radioRegion: RegionCodes.us.rawValue, regionPresets: [:]) == nil)
	}

	@MainActor @Test func savedCustomOfferKeepsItsChannelAndSlot() {
		let beacon = DiscoveredBeaconEntity()
		beacon.offerPreset = ModemPresets.longFast.rawValue
		beacon.hasOfferChannel = true
		beacon.offerChannelName = "M"
		beacon.offerChannelPSK = Data([9])
		beacon.offerFrequencySlot = 7
		let row = DiscoveryScanView.BeaconChannel(beacon: beacon, radioRegion: RegionCodes.us.rawValue, regionPresets: [:])
		#expect(row?.name == "M")
		#expect(row?.scanTarget.channelName == "M")
		#expect(row?.scanTarget.frequencySlot == 7)
	}
}

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
		entity.paFanDisabled = true
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
		#expect(config.paFanDisabled)
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
