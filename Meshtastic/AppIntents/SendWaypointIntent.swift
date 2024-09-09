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

	static var title = LocalizedStringResource("Send a Waypoint")

	@Parameter(title: "Name", default: "Dropped Pin")
	var nameParameter: String?

	@Parameter(title: "Description", default: "")
	var descriptionParameter: String?

	@Parameter(title: "Emoji", default: "📍")
	var emojiParameter: String?

	@Parameter(title: "Location")
	var locationParameter: CLPlacemark

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

		var newWaypoint = Waypoint()

		if let latitude = locationParameter.location?.coordinate.latitude {
			newWaypoint.latitudeI = Int32(latitude * 10_000_000)
		}

		if let longitude = locationParameter.location?.coordinate.longitude {
			newWaypoint.longitudeI = Int32(longitude * 10_000_000)
		}

		newWaypoint.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		// Unicode scalar value for the icon emoji string
		let unicodeScalers = emoji.unicodeScalars
		// First element as an UInt32
		let unicode = unicodeScalers[unicodeScalers.startIndex].value
		newWaypoint.icon = unicode
		newWaypoint.name = name
		newWaypoint.description_p = description
		if !BLEManager.shared.sendWaypoint(waypoint: newWaypoint) {
			throw AppIntentErrors.AppIntentError.message("Failed to Send Waypoint")
		}

		return .result()
	}

	private func isValidSingleEmoji(_ emoji: String) -> Bool {
		// This regex pattern is for matching a single emoji
		let emojiPattern = "^([\\p{So}\\p{Cn}])$"
		let regex = try? NSRegularExpression(pattern: emojiPattern, options: [])
		let matches = regex?.matches(in: emoji, options: [], range: NSRange(location: 0, length: emoji.utf16.count))

		return matches?.count == 1
	}
}
