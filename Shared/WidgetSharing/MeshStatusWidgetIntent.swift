//
//  MeshStatusWidgetIntent.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/21/26.
//
//  The Mesh Status widget's configuration: which of the radio's readings the
//  small size shows, in order.
//

import AppIntents

/// One reading the small Mesh Status widget can show.
enum MeshStatusReading: String, AppEnum, CaseIterable {
	case nodes
	case battery
	case channelUtilization
	case airtime
	case unreadMessages
	case uptime
	case packetsSent
	case packetsReceived
	case packetsRelayed
	case duplicates

	static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Reading")
	static let caseDisplayRepresentations: [MeshStatusReading: DisplayRepresentation] = [
		.nodes: DisplayRepresentation(title: "Nodes Online", image: .init(systemName: "dot.radiowaves.left.and.right")),
		.battery: DisplayRepresentation(title: "Battery", image: .init(systemName: "battery.75percent")),
		.channelUtilization: DisplayRepresentation(title: "Channel Utilization", image: .init(systemName: "chart.bar")),
		.airtime: DisplayRepresentation(title: "Airtime", image: .init(systemName: "waveform")),
		.unreadMessages: DisplayRepresentation(title: "Unread Messages", image: .init(systemName: "bubble.left")),
		.uptime: DisplayRepresentation(title: "Uptime", image: .init(systemName: "clock.arrow.circlepath")),
		.packetsSent: DisplayRepresentation(title: "Packets Sent", image: .init(systemName: "arrow.up")),
		.packetsReceived: DisplayRepresentation(title: "Packets Received", image: .init(systemName: "arrow.down")),
		.packetsRelayed: DisplayRepresentation(title: "Packets Relayed", image: .init(systemName: "arrow.triangle.2.circlepath")),
		.duplicates: DisplayRepresentation(title: "Duplicates", image: .init(systemName: "square.on.square"))
	]

	/// What the widget showed before it had a setting; the intent's default repeats it as a literal.
	static let standard: [MeshStatusReading] = [.nodes, .battery, .channelUtilization, .airtime, .unreadMessages, .uptime]
}

struct MeshStatusWidgetIntent: WidgetConfigurationIntent {
	static let title: LocalizedStringResource = "Mesh Status"
	static let description = IntentDescription("Pick the readings the small size shows, in order.")

	/// The small size shows up to six, two to a row.
	@Parameter(title: "Readings", default: [.nodes, .battery, .channelUtilization, .airtime, .unreadMessages, .uptime])
	var readings: [MeshStatusReading]

	init() {}
}
