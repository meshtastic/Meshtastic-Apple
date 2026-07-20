//
//  BurningManOfflinePack.swift
//  Meshtastic
//

import CoreLocation
import Foundation

enum BurningManPackAction: Equatable {
	case install
	case retain
	case remove
}

enum BurningManOfflinePack {
	static let packID = "burning-man-2026"
	static let bounds = GeoBounds(
		minLon: -119.287957, minLat: 40.722536,
		maxLon: -119.128520, maxLat: 40.843420
	)

	static let eventEnd = thresholdDate(year: 2026, month: 9, day: 8)
	static let outsideAreaCleanupDate = eventEnd
	static let noLocationCleanupDate = thresholdDate(year: 2026, month: 9, day: 12)

	static func policy(now: Date, location: CLLocation?) -> BurningManPackAction {
		if now >= noLocationCleanupDate { return .remove }
		guard now >= outsideAreaCleanupDate,
			let location,
			isUsable(location, at: now)
		else { return .retain }

		return contains(location.coordinate) ? .retain : .remove
	}

	private static func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
		coordinate.latitude >= bounds.minLat && coordinate.latitude <= bounds.maxLat &&
			coordinate.longitude >= bounds.minLon && coordinate.longitude <= bounds.maxLon
	}

	private static func isUsable(_ location: CLLocation, at now: Date) -> Bool {
		CLLocationCoordinate2DIsValid(location.coordinate) &&
			location.horizontalAccuracy.isFinite &&
			location.horizontalAccuracy >= 0 &&
			location.timestamp >= now.addingTimeInterval(-86_400)
	}

	private static func thresholdDate(year: Int, month: Int, day: Int) -> Date {
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
		return calendar.date(from: DateComponents(year: year, month: month, day: day))!
	}
}
