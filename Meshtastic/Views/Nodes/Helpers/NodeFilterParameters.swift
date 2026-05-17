//
//  NodeListFilterParameters.swift
//  Meshtastic
//
//  Created by jake on 9/4/25.
//

import SwiftUI

@MainActor
final class NodeFilterParameters: ObservableObject {
	// Public variables
	@Published var searchText = ""
	@Published var isOnline = false
	@Published var isPkiEncrypted = false
	@Published var isFavorite = false
	@Published var isIgnored = false
	@Published var isEnvironment = false
	@Published var distanceFilter = false
	@Published var maxDistance: Double = 800_000
	@Published var hopsAway: Double = -1.0
	@Published var roleFilter = false
	@Published var deviceRoles: Set<Int> = []
	
	// Private backing vars
	@Published private var _viaLora = true
	@Published private var _viaMqtt = true
	
	// Public computed wrappers with enforcement
	var viaLora: Bool {
		get { _viaLora }
		set {
			objectWillChange.send()
			_viaLora = newValue
			if !_viaLora && !_viaMqtt {
				_viaMqtt = true   // enforce at least one ON
			}
		}
	}
	
	var viaMqtt: Bool {
		get { _viaMqtt }
		set {
			objectWillChange.send()
			_viaMqtt = newValue
			if !_viaLora && !_viaMqtt {
				_viaLora = true   // enforce at least one ON
			}
		}
	}

	/// Whether any filter is actively narrowing results (ignoring search text).
	var isFiltering: Bool {
		isOnline || isPkiEncrypted || isFavorite || isIgnored || isEnvironment ||
		distanceFilter || hopsAway >= 0.0 || (roleFilter && !deviceRoles.isEmpty) ||
		(viaLora && !viaMqtt) || (!viaLora && viaMqtt)
	}

	// MARK: - In-Memory Matching

	/// In-memory filter matching for use with @Query results on NodeInfoEntity.
	func matches(_ node: NodeInfoEntity) -> Bool {
		// Search text
		if !searchText.isEmpty {
			let text = searchText.lowercased()
			let matchesSearch = [
				node.user?.userId,
				node.user?.numString,
				node.user?.hwModel,
				node.user?.hwDisplayName,
				node.user?.longName,
				node.user?.shortName
			].compactMap { $0 }.contains { $0.localizedCaseInsensitiveContains(text) }
			if !matchesSearch { return false }
		}

		// Favorite filter
		if isFavorite && !node.favorite { return false }

		// Via Lora/MQTT filters
		if viaLora && !viaMqtt && node.viaMqtt { return false }
		if !viaLora && viaMqtt && !node.viaMqtt { return false }

		// Role filter
		if roleFilter && !deviceRoles.isEmpty {
			guard let role = node.user?.role else { return false }
			if !deviceRoles.contains(Int(role)) { return false }
		}

		// Hops Away filter
		if hopsAway == 0.0 {
			if node.hopsAway != 0 { return false }
		} else if hopsAway > 0.0 {
			if node.hopsAway <= 0 || node.hopsAway > Int32(hopsAway) { return false }
		}

		// Online filter
		if isOnline {
			guard let lastHeard = node.lastHeard,
				  let threshold = Calendar.current.date(byAdding: .minute, value: -120, to: Date()) else {
				return false
			}
			if lastHeard < threshold { return false }
		}

		// Encrypted filter
		if isPkiEncrypted {
			if node.user?.pkiEncrypted != true { return false }
		}

		// Ignored filter
		if isIgnored {
			if !node.ignored { return false }
		} else {
			if node.ignored { return false }
		}

		// Environment filter
		if isEnvironment {
			let hasEnvironmentTelemetry = node.telemetries.contains { $0.metricsType == 1 }
			if !hasEnvironmentTelemetry { return false }
		}

		// Distance filter
		if distanceFilter {
			if let pointOfInterest = LocationsHandler.currentLocation {
				if pointOfInterest.latitude != LocationsHandler.DefaultLocation.latitude &&
					pointOfInterest.longitude != LocationsHandler.DefaultLocation.longitude {
					let d: Double = maxDistance * 1.1
					let r: Double = 6371009
					let meanLatitude = pointOfInterest.latitude * .pi / 180
					let deltaLatitude = d / r * 180 / .pi
					let deltaLongitude = d / (r * cos(meanLatitude)) * 180 / .pi
					let minLatitude = pointOfInterest.latitude - deltaLatitude
					let maxLatitude = pointOfInterest.latitude + deltaLatitude
					let minLongitude = pointOfInterest.longitude - deltaLongitude
					let maxLongitude = pointOfInterest.longitude + deltaLongitude

					let hasPositionInRange = node.positions.contains { position in
						guard position.latest else { return false }
						let lon = Double(position.longitudeI) / 1e7
						let lat = Double(position.latitudeI) / 1e7
						return lon >= minLongitude && lon <= maxLongitude && lat >= minLatitude && lat <= maxLatitude
					}
					if !hasPositionInRange { return false }
				}
			}
		}

		return true
	}
}
