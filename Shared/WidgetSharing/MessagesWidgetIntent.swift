//
//  MessagesWidgetIntent.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/21/26.
//
//  The Messages widget's configuration: all messages, direct messages or one
//  channel, and whether to show only unread ones. The choices come from the
//  shared snapshot, so the widget process never touches the database.
//

import AppIntents

/// Which messages a Messages widget shows.
struct MessageSourceEntity: AppEntity {
	static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Messages")
	static let defaultQuery = MessageSourceQuery()

	static let allID = "all"
	static let directID = "direct"

	/// "all", "direct", or "channel-<index>".
	let id: String
	let name: String

	var displayRepresentation: DisplayRepresentation {
		DisplayRepresentation(title: "\(name)")
	}

	/// The channel index, for a channel.
	var channelIndex: Int32? {
		id.hasPrefix("channel-") ? Int32(id.dropFirst("channel-".count)) : nil
	}

	static var all: MessageSourceEntity {
		MessageSourceEntity(id: allID, name: String(localized: "All Messages", comment: "Messages widget choice"))
	}

	static var direct: MessageSourceEntity {
		MessageSourceEntity(id: directID, name: String(localized: "Direct Messages", comment: "Messages widget choice"))
	}

	static func channel(_ channel: ChannelSnapshot) -> MessageSourceEntity {
		MessageSourceEntity(id: "channel-\(channel.index)", name: channel.name)
	}
}

struct MessageSourceQuery: EntityQuery {
	/// Every identifier answers, so a saved channel keeps its place after the
	/// radio's channels change; one no longer there is named by its index.
	func entities(for identifiers: [String]) async throws -> [MessageSourceEntity] {
		let known = try await suggestedEntities()
		return identifiers.map { id in
			known.first { $0.id == id }
				?? MessageSourceEntity(id: id, name: String(localized: "Channel \(String(id.dropFirst("channel-".count)))", comment: "A label for a channel index. The argument is the channel index."))
		}
	}

	func suggestedEntities() async throws -> [MessageSourceEntity] {
		let channels = WidgetSnapshotStore.load()?.channels ?? []
		return [.all, .direct] + channels.map(MessageSourceEntity.channel)
	}

	func defaultResult() async -> MessageSourceEntity? {
		.all
	}
}

struct MessagesWidgetIntent: WidgetConfigurationIntent {
	static let title: LocalizedStringResource = "Messages"
	static let description = IntentDescription("Pick the messages to show.")

	@Parameter(title: "Show")
	var source: MessageSourceEntity?

	@Parameter(title: "Unread Only", default: false)
	var unreadOnly: Bool

	init() {}
}
