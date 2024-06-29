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
			return NSLocalizedString("routes.activitytype.walking", comment: "No comment provided")
		case .hiking:
			return NSLocalizedString("routes.activitytype.hiking", comment: "No comment provided")
		case .biking:
			return NSLocalizedString("routes.activitytype.biking", comment: "No comment provided")
		case .driving:
			return NSLocalizedString("routes.activitytype.driving", comment: "No comment provided")
		case .overlanding:
			return NSLocalizedString("routes.activitytype.overlanding", comment: "No comment provided")
		case .skiing:
			return NSLocalizedString("routes.activitytype.skiing", comment: "No comment provided")
		}
	}

	var fileNameString: String {
		switch self {
		case .walking:
			return NSLocalizedString("routes.activitytype.filename.walking", comment: "No comment provided")
		case .hiking:
			return NSLocalizedString("routes.activitytype.filename.hiking", comment: "No comment provided")
		case .biking:
			return NSLocalizedString("routes.activitytype.filename.biking", comment: "No comment provided")
		case .driving:
			return NSLocalizedString("routes.activitytype.filename.driving", comment: "No comment provided")
		case .overlanding:
			return NSLocalizedString("routes.activitytype.filename.overlanding", comment: "No comment provided")
		case .skiing:
			return NSLocalizedString("routes.activitytype.filename.skiing", comment: "No comment provided")
		}
	}
}
