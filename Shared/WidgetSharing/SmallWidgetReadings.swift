//
//  SmallWidgetReadings.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/21/26.
//
//  How many telemetry readings the small Telemetry and Node Tracker widgets
//  show, set per widget in Edit Widget. A widget can't tell where it is shown
//  (the phone and a home view give a small widget about the same size), so the
//  person picks: 2, or up to 8 where the widget is seen larger, like a home view.
//

import AppIntents

enum SmallWidgetReadings: Int, AppEnum {
	case two = 2
	case six = 6
	case eight = 8

	static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Readings Shown")
	static let caseDisplayRepresentations: [SmallWidgetReadings: DisplayRepresentation] = [
		.two: "2",
		.six: "6",
		.eight: "8"
	]
}
