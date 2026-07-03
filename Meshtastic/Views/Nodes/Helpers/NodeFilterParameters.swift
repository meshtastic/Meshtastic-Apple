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

	/// Shared, app-wide filter instance. `NodeList`, `MeshMap`, and `UserList` all observe this
	/// single object, so a filter set on one screen applies across the app. Using one shared
	/// instance — rather than three independent `@StateObject`s — keeps behavior consistent with
	/// the global `nodeFilter.*` persisted keys, which are not namespaced per screen.
	static let shared = NodeFilterParameters()

	private enum Keys {
		static let isOnline = "nodeFilter.isOnline"
		static let isPkiEncrypted = "nodeFilter.isPkiEncrypted"
		static let isFavorite = "nodeFilter.isFavorite"
		static let isIgnored = "nodeFilter.isIgnored"
		static let isEnvironment = "nodeFilter.isEnvironment"
		static let distanceFilter = "nodeFilter.distanceFilter"
		static let maxDistance = "nodeFilter.maxDistance"
		static let hopsAway = "nodeFilter.hopsAway"
		static let roleFilter = "nodeFilter.roleFilter"
		static let deviceRoles = "nodeFilter.deviceRoles"
		static let viaLora = "nodeFilter.viaLora"
		static let viaMqtt = "nodeFilter.viaMqtt"
	}

	/// Search text is intentionally **not** persisted — relaunching into a stale search that hides
	/// most nodes is confusing. It lives in memory for the app session only.
	@Published var searchText = ""

	// Each filter is `@Published` (so SwiftUI observers update live when it toggles — an
	// `@AppStorage` property inside an `ObservableObject` reads/writes `UserDefaults` but does NOT
	// fire `objectWillChange`) and mirrors its value to `store` in `didSet` so it survives relaunch.
	@Published var isOnline: Bool { didSet { store.set(isOnline, forKey: Keys.isOnline) } }
	@Published var isPkiEncrypted: Bool { didSet { store.set(isPkiEncrypted, forKey: Keys.isPkiEncrypted) } }
	@Published var isFavorite: Bool { didSet { store.set(isFavorite, forKey: Keys.isFavorite) } }
	@Published var isIgnored: Bool { didSet { store.set(isIgnored, forKey: Keys.isIgnored) } }
	@Published var isEnvironment: Bool { didSet { store.set(isEnvironment, forKey: Keys.isEnvironment) } }
	@Published var distanceFilter: Bool { didSet { store.set(distanceFilter, forKey: Keys.distanceFilter) } }
	@Published var maxDistance: Double { didSet { store.set(maxDistance, forKey: Keys.maxDistance) } }
	@Published var hopsAway: Double { didSet { store.set(hopsAway, forKey: Keys.hopsAway) } }
	@Published var roleFilter: Bool { didSet { store.set(roleFilter, forKey: Keys.roleFilter) } }

	@Published var deviceRoles: Set<Int> = [] {
		didSet { store.set(Array(deviceRoles), forKey: Keys.deviceRoles) }
	}

	// `viaLora`/`viaMqtt` use private `@Published` storage with public wrappers that enforce "at
	// least one ON". Being `@Published`, mutating the backing value publishes `objectWillChange`;
	// `didSet` persists it.
	@Published private var _viaLora: Bool { didSet { store.set(_viaLora, forKey: Keys.viaLora) } }
	@Published private var _viaMqtt: Bool { didSet { store.set(_viaMqtt, forKey: Keys.viaMqtt) } }

	/// Backing store for all persisted filter values. Defaults to `.standard`; tests inject an
	/// isolated suite so they don't read or clobber the shared `UserDefaults.standard` domain.
	private let store: UserDefaults

	// Public computed wrappers with enforcement
	var viaLora: Bool {
		get { _viaLora }
		set {
			_viaLora = newValue
			if !_viaLora && !_viaMqtt {
				_viaMqtt = true   // enforce at least one ON
			}
		}
	}

	var viaMqtt: Bool {
		get { _viaMqtt }
		set {
			_viaMqtt = newValue
			if !_viaLora && !_viaMqtt {
				_viaLora = true   // enforce at least one ON
			}
		}
	}

	/// - Parameter store: The `UserDefaults` instance backing all persisted filter values.
	///   Defaults to `.standard`; pass an isolated suite in tests.
	init(store: UserDefaults = .standard) {
		self.store = store

		// Property observers do not fire for assignments made inside `init`, so loading persisted
		// values here reads from `store` without writing back to it.
		isOnline = store.object(forKey: Keys.isOnline) as? Bool ?? false
		isPkiEncrypted = store.object(forKey: Keys.isPkiEncrypted) as? Bool ?? false
		isFavorite = store.object(forKey: Keys.isFavorite) as? Bool ?? false
		isIgnored = store.object(forKey: Keys.isIgnored) as? Bool ?? false
		isEnvironment = store.object(forKey: Keys.isEnvironment) as? Bool ?? false
		distanceFilter = store.object(forKey: Keys.distanceFilter) as? Bool ?? false
		maxDistance = store.object(forKey: Keys.maxDistance) as? Double ?? 800_000
		hopsAway = store.object(forKey: Keys.hopsAway) as? Double ?? -1.0
		roleFilter = store.object(forKey: Keys.roleFilter) as? Bool ?? false
		_viaLora = store.object(forKey: Keys.viaLora) as? Bool ?? true
		_viaMqtt = store.object(forKey: Keys.viaMqtt) as? Bool ?? true

		if let storedRoles = store.array(forKey: Keys.deviceRoles) as? [Int] {
			deviceRoles = Set(storedRoles)
		}
	}

	/// Restores every filter to its default and clears the search text. Backs the reset affordance
	/// on the node and contact lists.
	func reset() {
		searchText = ""
		isOnline = false
		isPkiEncrypted = false
		isFavorite = false
		isIgnored = false
		isEnvironment = false
		distanceFilter = false
		maxDistance = 800_000
		hopsAway = -1.0
		roleFilter = false
		deviceRoles = []
		_viaLora = true
		_viaMqtt = true
	}

	/// Whether any filter is actively narrowing results (ignoring search text).
	var isFiltering: Bool {
		isOnline || isPkiEncrypted || isFavorite || isIgnored || isEnvironment ||
		distanceFilter || hopsAway >= 0.0 || (roleFilter && !deviceRoles.isEmpty) ||
		(viaLora && !viaMqtt) || (!viaLora && viaMqtt)
	}

	/// Fallback origin for distance filtering when the phone's location services are
	/// unavailable. Set by the owning view to the connected device's last known position.
	@Published var fallbackLocation: CLLocationCoordinate2D?

	var currentDistanceBounds: NodeDistanceFilterBounds? {
		guard distanceFilter else { return nil }
		let center = LocationsHandler.currentLocation ?? fallbackLocation
		guard let center,
			  center.latitude != LocationsHandler.DefaultLocation.latitude,
			  center.longitude != LocationsHandler.DefaultLocation.longitude else {
			return nil
		}
		return NodeDistanceFilterBounds(center: center, maxDistance: maxDistance)
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
