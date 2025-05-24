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
			return "Walking".localized
		case .hiking:
			return "Hiking".localized
		case .biking:
			return "Biking".localized
		case .driving:
			return "Driving".localized
		case .overlanding:
			return "Overlanding".localized
		case .skiing:
			return "Skiing".localized
		}
	}

	var fileNameString: String {
		switch self {
		case .walking:
			return "Walking".localized.lowercased()
		case .hiking:
			return "Hiking".localized.lowercased()
		case .biking:
			return "Biking".localized.lowercased()
		case .driving:
			return "Driving".localized.lowercased()
		case .overlanding:
			return "Overlanding".localized.lowercased()
		case .skiing:
			return "Skiing".localized.lowercased()
		}
	}
}
