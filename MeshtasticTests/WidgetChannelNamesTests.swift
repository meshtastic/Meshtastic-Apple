//
//  WidgetChannelNamesTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/27/26.
//

import Foundation
import SwiftData
import Testing
@testable import Meshtastic

@Suite("Widget channel names")
struct WidgetChannelNamesTests {

	private static let radioNum: Int64 = 0x1234_5678

	private func makeContainer() throws -> ModelContainer {
		let schema = Schema(versionedSchema: MeshtasticSchema.current)
		let config = ModelConfiguration(
			"WidgetChannelNamesTests-\(UUID().uuidString)",
			schema: schema,
			isStoredInMemoryOnly: true,
			allowsSave: true
		)
		return try ModelContainer(for: schema, configurations: config)
	}

	private func makeChannel(index: Int32, name: String?, role: Int32 = 1) -> ChannelEntity {
		let channel = ChannelEntity()
		channel.index = index
		channel.name = name
		channel.role = role
		return channel
	}

	@Test func namesComeFromTheRadiosChannelsWithFallbacks() throws {
		let container = try makeContainer()
		let context = ModelContext(container)
		let myInfo = MyInfoEntity()
		myInfo.myNodeNum = Self.radioNum
		context.insert(myInfo)
		for channel in [makeChannel(index: 0, name: ""), makeChannel(index: 1, name: "Hikers"), makeChannel(index: 2, name: nil), makeChannel(index: 3, name: "Off", role: 0)] {
			context.insert(channel)
			myInfo.channels.append(channel)
		}
		try context.save()

		let names = WidgetDataBroker.fetchChannelNames(context: ModelContext(container), radioNum: Self.radioNum)
		#expect(names == [0: "Primary", 1: "Hikers", 2: "Channel 2"])
		#expect(WidgetDataBroker.fetchChannelNames(context: ModelContext(container), radioNum: 1).isEmpty)
	}

	/// The crash: the widget's context had read the channels, then a channel refresh on another
	/// context deleted and replaced them. The names must come from the store, not the deleted rows.
	@Test func namesFollowAChannelRefreshOnAnotherContext() throws {
		let container = try makeContainer()
		let main = ModelContext(container)
		let myInfo = MyInfoEntity()
		myInfo.myNodeNum = Self.radioNum
		main.insert(myInfo)
		let old = makeChannel(index: 1, name: "Old")
		main.insert(old)
		myInfo.channels.append(old)
		try main.save()

		let widget = ModelContext(container)
		#expect(WidgetDataBroker.fetchChannelNames(context: widget, radioNum: Self.radioNum) == [1: "Old"])

		// What the channel refresh does: delete every channel and insert the new set.
		for channel in myInfo.channels { main.delete(channel) }
		myInfo.channels.removeAll()
		let new = makeChannel(index: 1, name: "New")
		main.insert(new)
		myInfo.channels.append(new)
		try main.save()

		#expect(WidgetDataBroker.fetchChannelNames(context: widget, radioNum: Self.radioNum) == [1: "New"])
	}
}
