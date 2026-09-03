//
//  NodeTrackTimeRange.swift
//  Meshtastic
//

import Foundation

enum NodeTrackTimeRange: String, CaseIterable, Identifiable {
	case all
	case oneHour
	case eightHours
	case oneDay
	case twoDays

	var id: String { rawValue }

	var title: String {
		switch self {
		case .all: "All"
		case .oneHour: "1h"
		case .eightHours: "8h"
		case .oneDay: "1d"
		case .twoDays: "2d"
		}
	}

	private var duration: TimeInterval? {
		switch self {
		case .all: nil
		case .oneHour: 3_600
		case .eightHours: 28_800
		case .oneDay: 86_400
		case .twoDays: 172_800
		}
	}

	func includes(_ date: Date?, relativeTo now: Date) -> Bool {
		guard let date else { return false }
		guard let duration else { return true }
		return date >= now.addingTimeInterval(-duration)
	}

	func filtered<T>(_ values: [T], timestamp: (T) -> Date?, relativeTo now: Date) -> [T] {
		values.filter { includes(timestamp($0), relativeTo: now) }
	}
}
