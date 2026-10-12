//
//  SpatialTerrainDownload.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/12/26.
//
import Foundation

/// How much of a box the downloaded terrain covers.
enum SpatialTerrainCoverage {
	/// Fraction of `box` covered by any of `sources`, sampled on an (n+1)×(n+1) lattice that
	/// includes the box's edges, so a thin uncovered strip along an edge is never missed.
	static func fraction(of box: GeoBounds, covered sources: [GeoBounds], samples: Int = 24) -> Double {
		guard samples > 0, !sources.isEmpty else { return 0 }
		// The last sample is the edge itself, not min + span, which can land a hair outside.
		func position(_ index: Int, _ low: Double, _ high: Double) -> Double {
			index == samples ? high : low + (high - low) * Double(index) / Double(samples)
		}
		var hits = 0
		for j in 0...samples {
			let lat = position(j, box.minLat, box.maxLat)
			for i in 0...samples {
				let lon = position(i, box.minLon, box.maxLon)
				if sources.contains(where: { lon >= $0.minLon && lon <= $0.maxLon && lat >= $0.minLat && lat <= $0.maxLat }) {
					hits += 1
				}
			}
		}
		return Double(hits) / Double((samples + 1) * (samples + 1))
	}
}

/// Why the spatial map can't download terrain for the whole box.
enum SpatialTerrainBlock: Equatable {
	/// The download would push offline maps past the total storage limit.
	case storage
	/// Even the smallest area that covers the box is over the per-map limit.
	case tooLarge
}

/// What the spatial map should do to keep its box covered by terrain. The app keeps one
/// terrain-only region of its own ("Spatial Map terrain") and grows or moves it as the mesh
/// changes; the user's regions count as coverage but are never changed.
enum SpatialTerrainAutoDecision: Equatable {
	/// Covered, busy, or the backoff says not now.
	case none
	/// No managed region yet: download one for this area.
	case create(GeoBounds)
	/// Replace the managed region with one for this area.
	case expand(GeoBounds, replacing: UUID)
	case blocked(SpatialTerrainBlock)

	/// Every sample must have terrain: the volume should show relief edge to edge.
	static let coverageThreshold = 1.0
	static let maxSpanMeters: Double = 350_000
	/// Rough size of global z0–12 terrain per km². The manager re-checks the real plan.
	static let bytesPerSquareKm: Int64 = 4_096
	/// Areas this small (per side) also get the regional high-resolution extract.
	static let regionalMaxSpanMeters: Double = 20_000

	static func make(
		box: GeoBounds,
		regions: [OfflineMapRegion],
		isBusy: Bool,
		backoff: SpatialTerrainBackoff,
		now: Date
	) -> SpatialTerrainAutoDecision {
		let terrain = regions.filter { $0.terrain != nil }
		if SpatialTerrainCoverage.fraction(of: box, covered: terrain.map(\.bounds)) >= coverageThreshold { return .none }
		if isBusy { return .none }
		let managed = terrain.first { $0.managedBy == OfflineMapRegion.spatialMapManager }
		// Grow the managed region to take in the box. If that gets too big (say the radio is now on
		// another continent), move it to the box instead; the bare box is the last resort.
		let candidates = [managed.map { $0.bounds.union(box).expandedForTerrain() }, box.expandedForTerrain(), box].compactMap { $0 }
		guard let target = candidates.first(where: fits) else { return .blocked(.tooLarge) }
		// Storage counts every region, less the managed one that the download replaces.
		let totalBytes = regions.reduce(Int64(0)) { $0 + $1.totalByteCount }
		let freed = managed?.terrain?.byteCount ?? 0
		if totalBytes - freed + estimatedBytes(target) > OfflineMapStorageLimits.maxTotalBytes { return .blocked(.storage) }
		guard backoff.allows(target, now: now) else { return .none }
		if let managed { return .expand(target, replacing: managed.id) }
		return .create(target)
	}

	static func estimatedBytes(_ bounds: GeoBounds) -> Int64 {
		Int64(bounds.areaSquareKm) * bytesPerSquareKm
	}

	static func includesRegional(_ bounds: GeoBounds) -> Bool {
		let size = bounds.sizeInMeters
		return max(size.width, size.height) <= regionalMaxSpanMeters
	}

	private static func fits(_ bounds: GeoBounds) -> Bool {
		let size = bounds.sizeInMeters
		return size.width <= maxSpanMeters && size.height <= maxSpanMeters
			&& estimatedBytes(bounds) <= OfflineMapStorageLimits.maxRegionBytes
	}

	/// The area to download, for `.create` and `.expand`.
	var target: GeoBounds? {
		switch self {
		case .create(let bounds), .expand(let bounds, _): return bounds
		case .none, .blocked: return nil
		}
	}
}

/// Retry rules for automatic downloads, per target area: a failure waits 10 min · 2^n before the
/// next try and stops after three; a cancel stops automatic tries for that area this session.
struct SpatialTerrainBackoff: Equatable {
	static let baseDelay: TimeInterval = 600
	static let maxFailures = 3

	var target: GeoBounds?
	var failures = 0
	var retryAfter: Date?
	var cancelled = false

	func allows(_ target: GeoBounds, now: Date) -> Bool {
		guard target == self.target else { return true }
		if gaveUp(on: target) { return false }
		if let retryAfter, now < retryAfter { return false }
		return true
	}

	/// True when automatic downloads have stopped for this area (cancelled, or failed too often).
	func gaveUp(on target: GeoBounds) -> Bool {
		target == self.target && (cancelled || failures >= Self.maxFailures)
	}

	mutating func recordFailure(_ target: GeoBounds, now: Date) {
		if target != self.target { self = SpatialTerrainBackoff(target: target) }
		failures += 1
		retryAfter = now.addingTimeInterval(Self.baseDelay * pow(2, Double(failures - 1)))
	}

	mutating func recordCancel(_ target: GeoBounds) {
		if target != self.target { self = SpatialTerrainBackoff(target: target) }
		cancelled = true
	}
}

extension GeoBounds {
	/// Width and height in meters, measured across the middle of the box.
	var sizeInMeters: (width: Double, height: Double) {
		let frame = SpatialFrame(bounds: self)
		return ((maxLon - minLon) * frame.metersPerDegreeLongitude, (maxLat - minLat) * SpatialFrame.metersPerDegreeLatitude)
	}

	var areaSquareKm: Double {
		let size = sizeInMeters
		return size.width * size.height / 1_000_000
	}

	func union(_ other: GeoBounds) -> GeoBounds {
		GeoBounds(
			minLon: min(minLon, other.minLon), minLat: min(minLat, other.minLat),
			maxLon: max(maxLon, other.maxLon), maxLat: max(maxLat, other.maxLat)
		)
	}

	/// Pads each side by max(`minPadMeters`, `ratio` × the box's size) and snaps outward to z10
	/// tile edges, so small moves of the mesh give the same area and nothing is downloaded again.
	func expandedForTerrain(ratio: Double = 0.15, minPadMeters: Double = 10_000) -> GeoBounds {
		let size = sizeInMeters
		let frame = SpatialFrame(bounds: self)
		let padLon = max(minPadMeters, ratio * size.width) / frame.metersPerDegreeLongitude
		let padLat = max(minPadMeters, ratio * size.height) / SpatialFrame.metersPerDegreeLatitude
		let n = 1024.0 // tiles per side at z10
		let epsilon = 1e-9
		let x0 = ((max(minLon - padLon, -180) + 180) / 360 * n + epsilon).rounded(.down)
		let x1 = ((min(maxLon + padLon, 180) + 180) / 360 * n - epsilon).rounded(.up)
		let yTop = (SpatialFrame.mercatorY(min(maxLat + padLat, 85)) * n + epsilon).rounded(.down)
		let yBottom = (SpatialFrame.mercatorY(max(minLat - padLat, -85)) * n - epsilon).rounded(.up)
		return GeoBounds(
			minLon: x0 / n * 360 - 180,
			minLat: SpatialFrame.latitude(mercatorY: yBottom / n),
			maxLon: x1 / n * 360 - 180,
			maxLat: SpatialFrame.latitude(mercatorY: yTop / n)
		)
	}
}
