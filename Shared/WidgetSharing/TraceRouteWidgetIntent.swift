//
//  TraceRouteWidgetIntent.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/21/26.
//
//  The Trace Route widget's configuration: the newest route of any length, or
//  the newest with at least a number of hops. The app keeps the newest route
//  for each choice in the app group.
//

import AppIntents

enum TraceRouteMinimumHops: Int, AppEnum {
	case any = 0
	case one = 1
	case two = 2
	case three = 3
	case four = 4

	static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Minimum Hops")
	static let caseDisplayRepresentations: [TraceRouteMinimumHops: DisplayRepresentation] = [
		.any: "Any",
		.one: "1",
		.two: "2",
		.three: "3",
		.four: "4"
	]
}

struct TraceRouteWidgetIntent: WidgetConfigurationIntent {
	static let title: LocalizedStringResource = "Trace Route"
	static let description = IntentDescription("Show the newest trace route, or the newest with at least this many hops.")

	@Parameter(title: "Minimum Hops", default: .any)
	var minimumHops: TraceRouteMinimumHops

	init() {}
}
