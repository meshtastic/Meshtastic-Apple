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
			return "routes.activitytype.walking".localized
		case .hiking:
			return "routes.activitytype.hiking".localized
		case .biking:
			return "routes.activitytype.biking".localized
		case .driving:
			return "routes.activitytype.driving".localized
		case .overlanding:
			return "routes.activitytype.overlanding".localized
		case .skiing:
			return "routes.activitytype.skiing".localized
		}
	}

	var fileNameString: String {
		switch self {
		case .walking:
			return "routes.activitytype.filename.walking".localized
		case .hiking:
			return "routes.activitytype.filename.hiking".localized
		case .biking:
			return "routes.activitytype.filename.biking".localized
		case .driving:
			return "routes.activitytype.filename.driving".localized
		case .overlanding:
			return "routes.activitytype.filename.overlanding".localized
		case .skiing:
			return "routes.activitytype.filename.skiing".localized
		}
	}
}
