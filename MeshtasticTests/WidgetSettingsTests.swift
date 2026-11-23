//
//  WidgetSettingsTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 11/21/26.
//

import Foundation
import Testing
@testable import Meshtastic

@Suite("Widget settings")
struct WidgetSettingsTests {
	func node(_ num: Int64, online: Bool, favorite: Bool) -> NodeSnapshot {
		NodeSnapshot(
			num: num, longName: "Node \(num)", shortName: "N\(num)", colorSeed: UInt32(num), batteryLevel: nil, snr: nil, rssi: nil,
			signalRating: nil, lastHeard: nil, isOnline: online, hopsAway: 1, latitude: 47.6, longitude: -122.3, isFavorite: favorite
		)
	}

	@Test func nodeMapFiltersPickTheirNodesAndAlwaysTheRadio() {
		let radio = node(1, online: false, favorite: false)
		let online = node(2, online: true, favorite: false)
		let favorite = node(3, online: false, favorite: true)
		let nodes = [radio, online, favorite]
		#expect(nodes.filter { NodeMapFilter.all.includes($0, radioNum: 1) }.map(\.num) == [1, 2, 3])
		#expect(nodes.filter { NodeMapFilter.online.includes($0, radioNum: 1) }.map(\.num) == [1, 2])
		#expect(nodes.filter { NodeMapFilter.favorites.includes($0, radioNum: 1) }.map(\.num) == [1, 3])
	}

	@Test func messageSourcesKnowTheirChannel() {
		#expect(MessageSourceEntity.all.channelIndex == nil)
		#expect(MessageSourceEntity.direct.channelIndex == nil)
		#expect(MessageSourceEntity.channel(ChannelSnapshot(index: 2, name: "Hikers", unread: 3)).channelIndex == 2)
	}

	@Test func eachMinimumHopsChoiceHasItsOwnFile() {
		let urls = WidgetTraceRouteStore.minimumHopsChoices.compactMap { WidgetTraceRouteStore.metaURL(minimumHops: $0)?.lastPathComponent }
		#expect(Set(urls).count == urls.count)
		// A route saved before the setting existed is still read as Any.
		#expect(WidgetTraceRouteStore.metaURL(minimumHops: 0)?.lastPathComponent == WidgetTraceRouteStore.metaFilename)
	}
}
