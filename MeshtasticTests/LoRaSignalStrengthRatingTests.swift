// MARK: LoRaSignalStrengthRatingTests
//
//  Covers the unified signal-quality rating in LoRaSignalStrengthIndicator.swift
//  (issue #2042):
//   - signalQuality() is the single source of truth for the 4 tiers.
//   - getLoRaSignalStrength() uses the real link margin (rssi - noiseFloor) when a
//     noise floor is available, taking the more conservative of the SNR and RSSI
//     tiers; otherwise it falls back to the legacy guessed-RSSI-threshold rating
//     (RSSI still factors in when there's no noise floor to compute a real margin).
//   - getSnrColor() and the bar rating can never disagree (both derive from
//     signalQuality()).
//   - NodeInfoEntity.recentNoiseFloor gates on presence/zero/staleness.
//

import Testing
import Foundation
import SwiftData
import SwiftUI
@testable import Meshtastic

@Suite("LoRaSignalStrengthRating")
struct LoRaSignalStrengthRatingTests {

	// MARK: signalQuality bands (margin above the preset demod floor)

	@Test("signalQuality maps margins to the correct tiers")
	func signalQualityBands() {
		#expect(signalQuality(snrMargin: 1) == .good)      // above floor
		#expect(signalQuality(snrMargin: 0) == .fair)      // exactly at floor
		#expect(signalQuality(snrMargin: -5.5) == .bad)    // boundary fair/bad
		#expect(signalQuality(snrMargin: -6) == .bad)
		#expect(signalQuality(snrMargin: -7.5) == .bad)    // boundary bad/none
		#expect(signalQuality(snrMargin: -8) == .none)
	}

	// MARK: Legacy RSSI+SNR fallback (no noise floor)

	@Test("Without a noise floor, a weak RSSI still downgrades a good SNR")
	func legacyFallbackStillConsidersRssi() {
		// LongFast floor is -17.5. snr -10 is well above it → Good on SNR alone.
		// But a very weak RSSI (-140) must still downgrade it via the legacy -120/-126
		// fixed thresholds — RSSI shouldn't be silently ignored just because there's no
		// noise floor to compute a real margin from.
		#expect(getLoRaSignalStrength(snr: -10, rssi: -140, preset: .longFast) == .bad)
	}

	@Test("Without a noise floor and without RSSI, rating is SNR-only")
	func legacyFallbackIsSnrOnlyWhenRssiAlsoUnavailable() {
		// rssi == 0 means "not available" (not "0 dBm"), so this stays SNR-only.
		#expect(getLoRaSignalStrength(snr: -10, rssi: 0, preset: .longFast) == .good)
	}

	@Test("Without a noise floor, a good RSSI and good SNR still rate Good")
	func legacyFallbackHappyPathStillGood() {
		#expect(getLoRaSignalStrength(snr: -10, rssi: -100, preset: .longFast) == .good)
	}

	// MARK: Real link margin (noise floor available)

	@Test("A poor RSSI-vs-noiseFloor margin downgrades an otherwise-good SNR")
	func noiseFloorDowngradesWhenLinkMarginPoor() {
		// snr -10 → SNR tier Good. rssi -140 with noiseFloor -120 → margin -20,
		// which is -2.5 below the -17.5 floor → Fair. Conservative combine → Fair.
		#expect(getLoRaSignalStrength(snr: -10, rssi: -140, preset: .longFast, noiseFloor: -120) == .fair)
	}

	@Test("A healthy RSSI-vs-noiseFloor margin does not upgrade a poor SNR")
	func noiseFloorDoesNotUpgradeWhenSnrPoor() {
		// snr -25 → SNR tier Bad (-7.5 margin). Strong RSSI margin stays Good, but the
		// conservative combine keeps the worse tier → Bad.
		#expect(getLoRaSignalStrength(snr: -25, rssi: -100, preset: .longFast, noiseFloor: -120) == .bad)
	}

	@Test("A zero noise floor is treated as unavailable (legacy fallback, not SNR-only)")
	func zeroNoiseFloorFallsBackToLegacyRating() {
		#expect(getLoRaSignalStrength(snr: -10, rssi: -140, preset: .longFast, noiseFloor: 0) == .bad)
	}

	// MARK: Bar rating and SNR text color agree

	@Test("getSnrColor matches the SNR-only bar tier for the same reading")
	func snrColorMatchesBarTier() {
		for snr: Float in [-1, -17.5, -20, -23, -30] {
			let tier = getLoRaSignalStrength(snr: snr, rssi: 0, preset: .longFast)
			#expect(getSnrColor(snr: snr, preset: .longFast) == tier.color)
		}
	}
}

@Suite("NodeRecentNoiseFloor")
@MainActor
struct NodeRecentNoiseFloorTests {

	private func makeNode(context: ModelContext, num: Int64) -> NodeInfoEntity {
		let node = NodeInfoEntity()
		node.num = num
		context.insert(node)
		return node
	}

	private func addLocalStats(context: ModelContext, node: NodeInfoEntity, noiseFloor: Int32?, time: Date) {
		let stats = TelemetryEntity()
		stats.metricsType = 4 // Local Stats
		stats.time = time
		stats.noiseFloor = noiseFloor
		stats.nodeTelemetry = node
		context.insert(stats)
	}

	@Test("A fresh Local Stats noise floor is returned")
	func freshNoiseFloorReturned() throws {
		let context = ModelContext(sharedModelContainer)
		let node = makeNode(context: context, num: 1001)
		addLocalStats(context: context, node: node, noiseFloor: -119, time: Date())
		try context.save()
		#expect(node.recentNoiseFloor == -119)
	}

	@Test("A stale noise floor (older than 2 h) is ignored")
	func staleNoiseFloorIgnored() throws {
		let context = ModelContext(sharedModelContainer)
		let node = makeNode(context: context, num: 1002)
		let threeHoursAgo = Calendar.current.date(byAdding: .hour, value: -3, to: Date())!
		addLocalStats(context: context, node: node, noiseFloor: -119, time: threeHoursAgo)
		try context.save()
		#expect(node.recentNoiseFloor == nil)
	}

	@Test("A zero noise floor is ignored")
	func zeroNoiseFloorIgnored() throws {
		let context = ModelContext(sharedModelContainer)
		let node = makeNode(context: context, num: 1003)
		addLocalStats(context: context, node: node, noiseFloor: 0, time: Date())
		try context.save()
		#expect(node.recentNoiseFloor == nil)
	}

	@Test("No Local Stats yields nil")
	func noLocalStatsYieldsNil() throws {
		let context = ModelContext(sharedModelContainer)
		let node = makeNode(context: context, num: 1004)
		try context.save()
		#expect(node.recentNoiseFloor == nil)
	}
}
