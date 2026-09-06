//
//  LoRaConfigChangeTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 9/5/26.
//

import Testing
import Foundation
@testable import Meshtastic

@Suite("LoRa channel change")
struct LoRaConfigChangeTests {

	private func settings(
		region: Int32 = 1,
		preset: Int32 = 3,
		usePreset: Bool = true,
		channelNum: Int32 = 0,
		overrideFrequency: Float = 0,
		bandwidth: Int32 = 250,
		spreadFactor: Int32 = 11,
		codingRate: Int32 = 5
	) -> LoRaChannelSettings {
		LoRaChannelSettings(
			regionCode: region, modemPreset: preset, usePreset: usePreset,
			channelNum: channelNum, overrideFrequency: overrideFrequency,
			bandwidth: bandwidth, spreadFactor: spreadFactor, codingRate: codingRate
		)
	}

	@Test("an unchanged config does not move the radio")
	func unchangedStaysPut() {
		#expect(!settings().movesOffChannel(from: settings()))
	}

	@Test("region, preset, slot and override frequency each move the radio")
	func channelDefiningFieldsMove() {
		#expect(settings(region: 2).movesOffChannel(from: settings()))
		#expect(settings(preset: 5).movesOffChannel(from: settings()))
		#expect(settings(channelNum: 20).movesOffChannel(from: settings()))
		#expect(settings(overrideFrequency: 906.875).movesOffChannel(from: settings()))
		#expect(settings(usePreset: false).movesOffChannel(from: settings()))
	}

	@Test("custom radio parameters only count when the radio is using them")
	func customParametersOnlyCountWhenActive() {
		// usePreset true: the radio derives its channel from the preset and ignores these, so
		// editing them changes a stored value with no effect on what it listens to.
		#expect(!settings(bandwidth: 125).movesOffChannel(from: settings()))
		#expect(!settings(spreadFactor: 12).movesOffChannel(from: settings()))
		#expect(!settings(codingRate: 8).movesOffChannel(from: settings()))

		// usePreset false: now they define the channel.
		let custom = settings(usePreset: false)
		#expect(settings(usePreset: false, bandwidth: 125).movesOffChannel(from: custom))
		#expect(settings(usePreset: false, spreadFactor: 12).movesOffChannel(from: custom))
		#expect(settings(usePreset: false, codingRate: 8).movesOffChannel(from: custom))
	}

	@Test("changing the preset while on custom parameters does not move the radio")
	func presetIgnoredWhileCustom() {
		let custom = settings(usePreset: false)
		#expect(!settings(preset: 5, usePreset: false).movesOffChannel(from: custom))
	}

	@Test("a node heard before the change is flagged, one heard after is not")
	func flagsNodesHeardBeforeTheChange() {
		let changedAt = Date(timeIntervalSince1970: 2000)
		#expect(LoRaConfigChange.isUnheard(
			lastHeard: Date(timeIntervalSince1970: 1000), viaMqtt: false, changedAt: changedAt))
		#expect(!LoRaConfigChange.isUnheard(
			lastHeard: Date(timeIntervalSince1970: 3000), viaMqtt: false, changedAt: changedAt))
	}

	@Test("MQTT hears do not clear the flag")
	func mqttDoesNotCount() {
		// Heard over the internet, not over this radio's channel, so it says nothing about whether
		// the two still share one.
		#expect(!LoRaConfigChange.isUnheard(
			lastHeard: Date(timeIntervalSince1970: 3000), viaMqtt: true,
			changedAt: Date(timeIntervalSince1970: 2000)))
	}

	@Test("nothing is flagged before a change has been recorded")
	func noChangeMeansNoFlags() {
		#expect(!LoRaConfigChange.isUnheard(
			lastHeard: Date(timeIntervalSince1970: 1000), viaMqtt: false, changedAt: nil))
	}

	@Test("a node that has never been heard is not flagged")
	func neverHeardIsNotFlagged() {
		// Never heard is a different problem from gone quiet, and the epoch default is what an
		// unheard node carries in the store.
		let changedAt = Date(timeIntervalSince1970: 2000)
		#expect(!LoRaConfigChange.isUnheard(lastHeard: nil, viaMqtt: false, changedAt: changedAt))
		#expect(!LoRaConfigChange.isUnheard(
			lastHeard: Date(timeIntervalSince1970: 0), viaMqtt: false, changedAt: changedAt))
	}

	@Test("the recorded change is per radio")
	func changeIsRecordedPerRadio() throws {
		let store = try #require(UserDefaults(suiteName: "LoRaConfigChangeTests"))
		defer { store.removePersistentDomain(forName: "LoRaConfigChangeTests") }

		let when = Date(timeIntervalSince1970: 5000)
		LoRaConfigChange.recordChange(forNode: 4242, at: when, store: store)

		#expect(LoRaConfigChange.changedAt(forNode: 4242, store: store) == when)
		// A different radio has its own settings and its own history.
		#expect(LoRaConfigChange.changedAt(forNode: 9999, store: store) == nil)

		LoRaConfigChange.clear(forNode: 4242, store: store)
		#expect(LoRaConfigChange.changedAt(forNode: 4242, store: store) == nil)
	}

	@Test("the offer stands until dismissed, and returns on the next change")
	func offerIsPerChange() throws {
		let store = try #require(UserDefaults(suiteName: "LoRaConfigChangeOfferTests"))
		defer { store.removePersistentDomain(forName: "LoRaConfigChangeOfferTests") }

		#expect(!LoRaConfigChange.shouldOfferCleanup(forNode: 7, store: store))

		LoRaConfigChange.recordChange(forNode: 7, at: Date(timeIntervalSince1970: 1000), store: store)
		#expect(LoRaConfigChange.shouldOfferCleanup(forNode: 7, store: store))

		LoRaConfigChange.dismissOffer(forNode: 7, store: store)
		#expect(!LoRaConfigChange.shouldOfferCleanup(forNode: 7, store: store))

		// A later change is a new question, not the one they already answered.
		LoRaConfigChange.recordChange(forNode: 7, at: Date(timeIntervalSince1970: 2000), store: store)
		#expect(LoRaConfigChange.shouldOfferCleanup(forNode: 7, store: store))
	}

}
