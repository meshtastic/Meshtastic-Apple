//
//  RouteEnums.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 4/14/24.
//

import Foundation
import SwiftUI

enum ActivityType: Int, CaseIterable, Identifiable {
	case walking = 0
	case hiking = 1
	case biking = 2
	case driving = 3
	case overlanding = 4
	case skiing = 5

	var id: Int { self.rawValue }
	var description: String {
		switch self {
		case .walking:
			return String(localized: "Walking", comment: "ActivityType.description")
		case .hiking:
			return String(localized: "Hiking", comment: "ActivityType.description")
		case .biking:
			return String(localized: "Biking", comment: "ActivityType.description")
		case .driving:
			return String(localized: "Driving", comment: "ActivityType.description")
		case .overlanding:
			return String(localized: "Overlanding", comment: "ActivityType.description")
		case .skiing:
			return String(localized: "Skiing", comment: "ActivityType.description")
		}
	}

	var fileNameString: String {
		switch self {
		case .walking:
			return String(localized: "Walking", comment: "ActivityType.fileNameString").lowercased()
		case .hiking:
			return String(localized: "Hiking", comment: "ActivityType.fileNameString").lowercased()
		case .biking:
			return String(localized: "Biking", comment: "ActivityType.fileNameString").lowercased()
		case .driving:
			return String(localized: "Driving", comment: "ActivityType.fileNameString").lowercased()
		case .overlanding:
			return String(localized: "Overlanding", comment: "ActivityType.fileNameString").lowercased()
		case .skiing:
			return String(localized: "Skiing", comment: "ActivityType.fileNameString").lowercased()
		}
	}
}
