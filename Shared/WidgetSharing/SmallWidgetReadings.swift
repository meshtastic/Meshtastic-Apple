//
//  SmallWidgetReadings.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/21/26.
//
//  How many telemetry readings the small Telemetry and Node Tracker widgets
//  show, set per widget in Edit Widget. The tracker's readings sit two to a
//  row under its node details, so it stops at 8. A widget can't tell where it is shown
//  (the phone and a home view give a small widget about the same size), so the
//  person picks: 2, or more where the widget is seen larger, like a home view.
//

import AppIntents

enum SmallWidgetReadings: Int, AppEnum {
	case two = 2
	case three = 3
	case six = 6
	case twelve = 12

	static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Readings Shown")
	static let caseDisplayRepresentations: [SmallWidgetReadings: DisplayRepresentation] = [
		.two: "2",
		.three: "3",
		.six: "6",
		.twelve: "12"
	]
}

/// The Node Tracker's choice of readings.
enum SmallTrackerReadings: Int, AppEnum {
	case two = 2
	case three = 3
	case six = 6
	case eight = 8

	static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Readings Shown")
	static let caseDisplayRepresentations: [SmallTrackerReadings: DisplayRepresentation] = [
		.two: "2",
		.three: "3",
		.six: "6",
		.eight: "8"
	]
}
