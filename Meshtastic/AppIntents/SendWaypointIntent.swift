//
//  SendWaypointIntent.swift
//  Meshtastic
//
//  Created by Benjamin Faershtein on 8/9/24.
//

import CoreLocation
import Foundation
import AppIntents
import MeshtasticProtobufs

struct SendWaypointIntent: AppIntent {
	
	var defaultDate = Date.now.addingTimeInterval(60 * 480)

	static var title = LocalizedStringResource("Send a Waypoint")

	@Parameter(title: "Name", default: "Dropped Pin")
	var nameParameter: String?

	@Parameter(title: "Description", default: "")
	var descriptionParameter: String?

	@Parameter(title: "Emoji", default: "📍")
	var emojiParameter: String?

	// Replace CLPlacemark with latitude and longitude parameters
	@Parameter(title: "Latitude", description: "Latitude in degrees (e.g., 37.7749)")
	var latitudeParameter: Double

	@Parameter(title: "Longitude", description: "Longitude in degrees (e.g., -122.4194)")
	var longitudeParameter: Double

	@Parameter(title: "Locked", default: false)
	var isLocked: Bool

	@Parameter(title: "Expiration")
	var expiration: Date?

	func perform() async throws -> some IntentResult {
		if !BLEManager.shared.isConnected {
			throw AppIntentErrors.AppIntentError.notConnected
		}

		// Provide default values if parameters are nil
		let name = nameParameter ?? "Dropped Pin"
		let description = descriptionParameter ?? ""
		let emoji = emojiParameter ?? "📍"

		// Validate name length
		if name.utf8.count > 30 {
			throw $nameParameter.needsValueError("Name must be less than 30 bytes")
		}

		// Validate description length
		if description.utf8.count > 100 {
			throw $descriptionParameter.needsValueError("Description must be less than 100 bytes")
		}

		// Validate emoji
		guard isValidSingleEmoji(emoji) else {
			throw $emojiParameter.needsValueError("Must be a single emoji")
		}

		// Validate latitude and longitude
		guard abs(latitudeParameter) <= 90 else {
			throw $latitudeParameter.needsValueError("Latitude must be between -90 and 90 degrees")
		}
		guard abs(longitudeParameter) <= 180 else {
			throw $longitudeParameter.needsValueError("Longitude must be between -180 and 180 degrees")
		}

		var newWaypoint = Waypoint()

		// Set latitude and longitude directly
		newWaypoint.latitudeI = Int32(latitudeParameter * 10_000_000)
		newWaypoint.longitudeI = Int32(longitudeParameter * 10_000_000)

		newWaypoint.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		let unicodeScalers = emoji.unicodeScalars
		let unicode = unicodeScalers[unicodeScalers.startIndex].value
		newWaypoint.icon = unicode
		newWaypoint.name = name
		newWaypoint.description_p = description
		
		if let expirationDate = expiration {
			newWaypoint.expire = UInt32(expirationDate.timeIntervalSince1970)
		}
		
		if isLocked {
			newWaypoint.lockedTo = UInt32(BLEManager.shared.connectedPeripheral!.num)
		}

		if !BLEManager.shared.sendWaypoint(waypoint: newWaypoint) {
			throw AppIntentErrors.AppIntentError.message("Failed to Send Waypoint")
		}
		return .result()
	}

	private func isValidSingleEmoji(_ emoji: String) -> Bool {
		let emojiPattern = "^([\\p{So}\\p{Cn}])$"
		let regex = try? NSRegularExpression(pattern: emojiPattern, options: [])
		let matches = regex?.matches(in: emoji, options: [], range: NSRange(location: 0, length: emoji.utf16.count))
		return matches?.count == 1
	}
}
