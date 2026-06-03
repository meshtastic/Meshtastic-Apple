//
//  NodeListFilterParameters.swift
//  Meshtastic
//
//  Created by jake on 9/4/25.
//

import CoreLocation
import SwiftUI

struct NodeDistanceFilterBounds {
	private static let coordinateScale = 10_000_000.0
	private static let earthRadiusMeters = 6_371_009.0

	let minLatitudeI: Int32
	let maxLatitudeI: Int32
	let minLongitudeI: Int32
	let maxLongitudeI: Int32
	let crossesAntimeridian: Bool

	init?(center: CLLocationCoordinate2D?, maxDistance: Double) {
		guard let center, CLLocationCoordinate2DIsValid(center), maxDistance > 0 else { return nil }

		let distance = maxDistance * 1.1
		let meanLatitude = center.latitude * .pi / 180
		let latitudeCosine = cos(meanLatitude)
		guard abs(latitudeCosine) > 0.000001 else { return nil }

		let deltaLatitude = distance / Self.earthRadiusMeters * 180 / .pi
		let deltaLongitude = distance / (Self.earthRadiusMeters * latitudeCosine) * 180 / .pi
		let minLatitude = max(center.latitude - deltaLatitude, -90)
		let maxLatitude = min(center.latitude + deltaLatitude, 90)
		let rawMinLongitude = center.longitude - deltaLongitude
		let rawMaxLongitude = center.longitude + deltaLongitude
		crossesAntimeridian = rawMinLongitude < -180 || rawMaxLongitude > 180

		minLatitudeI = Self.scaledCoordinate(minLatitude, lowerBound: -90, upperBound: 90)
		maxLatitudeI = Self.scaledCoordinate(maxLatitude, lowerBound: -90, upperBound: 90)
		minLongitudeI = Self.scaledCoordinate(Self.normalizedLongitude(rawMinLongitude), lowerBound: -180, upperBound: 180)
		maxLongitudeI = Self.scaledCoordinate(Self.normalizedLongitude(rawMaxLongitude), lowerBound: -180, upperBound: 180)
	}

	func contains(_ position: PositionEntity) -> Bool {
		guard position.latest else { return false }
		guard position.latitudeI >= minLatitudeI && position.latitudeI <= maxLatitudeI else { return false }
		if crossesAntimeridian {
			return position.longitudeI >= minLongitudeI || position.longitudeI <= maxLongitudeI
		}
		return position.longitudeI >= minLongitudeI && position.longitudeI <= maxLongitudeI
	}

	private static func scaledCoordinate(_ value: Double, lowerBound: Double, upperBound: Double) -> Int32 {
		let boundedValue = min(max(value, lowerBound), upperBound)
		return Int32((boundedValue * coordinateScale).rounded(.towardZero))
	}

	private static func normalizedLongitude(_ value: Double) -> Double {
		var longitude = value
		while longitude < -180 { longitude += 360 }
		while longitude > 180 { longitude -= 360 }
		return longitude
	}
}

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

	var currentDistanceBounds: NodeDistanceFilterBounds? {
		guard distanceFilter,
			  let pointOfInterest = LocationsHandler.currentLocation,
			  pointOfInterest.latitude != LocationsHandler.DefaultLocation.latitude,
			  pointOfInterest.longitude != LocationsHandler.DefaultLocation.longitude else {
			return nil
		}
		return NodeDistanceFilterBounds(center: pointOfInterest, maxDistance: maxDistance)
	}

	var currentPreciseDistanceBounds: NodeDistanceFilterBounds? {
		guard distanceFilter,
			  let pointOfInterest = LocationsHandler.currentPreciseLocation else {
			return nil
		}
		return NodeDistanceFilterBounds(center: pointOfInterest, maxDistance: maxDistance)
	}

	// MARK: - In-Memory Matching

	/// In-memory filter matching for use with @Query results on NodeInfoEntity.
	func matches(
		_ node: NodeInfoEntity,
		latestPosition: PositionEntity? = nil,
		normalizedSearchText: String? = nil,
		onlineThreshold: Date? = nil,
		distanceBounds: NodeDistanceFilterBounds? = nil
	) -> Bool {
		// Search text
		let text = normalizedSearchText ?? searchText.lowercased()
		if !text.isEmpty {
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
			guard let lastHeard = node.lastHeard else {
				return false
			}
			let threshold = onlineThreshold ?? Date().addingTimeInterval(-7_200)
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
			if !node.hasEnvironmentMetrics { return false }
		}

		// Distance filter
		if distanceFilter, let bounds = distanceBounds ?? currentDistanceBounds {
			guard let position = latestPosition ?? node.latestPosition, bounds.contains(position) else {
				return false
			}
		}

		return true
	}
}
