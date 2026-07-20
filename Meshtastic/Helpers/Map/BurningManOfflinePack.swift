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
		if now < outsideAreaCleanupDate { return .install }
		guard let location,
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

@MainActor
protocol BurningManOfflinePackStoring: AnyObject {
	var regionID: UUID? { get }
	var userSuppressed: Bool { get }
	func record(region: OfflineMapRegion)
	func clearPack()
	func suppressIfManaging(regionID: UUID)
}

@MainActor
final class BurningManOfflinePackStore: BurningManOfflinePackStoring {
	static let shared = BurningManOfflinePackStore()

	private struct State: Codable {
		var regionID: UUID?
		var sourceBuild: String?
		var userSuppressed = false
	}

	private let defaults: UserDefaults
	private let key: String

	init(defaults: UserDefaults = .standard, key: String = "burning-man-2026-offline-pack") {
		self.defaults = defaults
		self.key = key
	}

	var regionID: UUID? { state.regionID }
	var userSuppressed: Bool { state.userSuppressed }

	func record(region: OfflineMapRegion) {
		var updated = state
		updated.regionID = region.id
		updated.sourceBuild = region.sourceBuild
		updated.userSuppressed = false
		state = updated
	}

	func clearPack() {
		var updated = state
		updated.regionID = nil
		updated.sourceBuild = nil
		state = updated
	}

	func suppressIfManaging(regionID: UUID) {
		guard state.regionID == regionID else { return }
		var updated = state
		updated.regionID = nil
		updated.sourceBuild = nil
		updated.userSuppressed = true
		state = updated
	}

	private var state: State {
		get {
			guard let data = defaults.data(forKey: key),
				let state = try? JSONDecoder().decode(State.self, from: data)
			else { return State() }
			return state
		}
		set {
			guard let data = try? JSONEncoder().encode(newValue) else { return }
			defaults.set(data, forKey: key)
		}
	}
}

@MainActor
protocol BurningManOfflinePackDownloading: AnyObject {
	var isDownloading: Bool { get }
	func region(id: UUID) -> OfflineMapRegion?
	func startSystemPackDownload(
		packID: String,
		bounds: GeoBounds,
		detail: OfflineMapDetailLevel,
		completion: @escaping (OfflineMapRegion?) -> Void
	)
	func removeSystemPack(id: UUID, reason: OfflineMapRemovalReason)
}

@MainActor
final class BurningManOfflinePackCoordinator {
	static let shared = BurningManOfflinePackCoordinator(
		store: BurningManOfflinePackStore.shared,
		downloader: OfflineMapManager.shared
	)

	private let store: any BurningManOfflinePackStoring
	private let downloader: any BurningManOfflinePackDownloading

	init(store: any BurningManOfflinePackStoring, downloader: any BurningManOfflinePackDownloading) {
		self.store = store
		self.downloader = downloader
	}

	func reconcile(now: Date, location: CLLocation?) async {
		switch BurningManOfflinePack.policy(now: now, location: location) {
		case .install:
			installIfNeeded()
		case .retain:
			return
		case .remove:
			removeIfPresent()
		}
	}

	private func installIfNeeded() {
		guard !store.userSuppressed, !downloader.isDownloading else { return }
		if let regionID = store.regionID {
			guard downloader.region(id: regionID) == nil else { return }
			store.clearPack()
		}

		downloader.startSystemPackDownload(
			packID: BurningManOfflinePack.packID,
			bounds: BurningManOfflinePack.bounds,
			detail: .high
		) { [weak self] region in
			guard let region else { return }
			self?.store.record(region: region)
		}
	}

	private func removeIfPresent() {
		guard let regionID = store.regionID else { return }
		downloader.removeSystemPack(id: regionID, reason: .automaticCleanup)
		store.clearPack()
	}
}
