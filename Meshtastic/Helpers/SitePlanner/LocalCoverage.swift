//
//  LocalCoverage.swift
//  Meshtastic
//
//  Coverage computed on the device with kp1812 (ITU-R P.1812) over Mapterhorn
//  terrain, the same engine Meshtastic-Android uses. P.1812 is a different model
//  from the hosted planner's SPLAT! ITM, so results don't match it pixel for pixel.
//

import Foundation
import Kp1812

/// The transmitter and radio to model.
struct CoverageSite: Sendable {
	var name: String
	var latitude: Double
	var longitude: Double
	var frequencyMHz: Double
	var txPowerDBm: Double
	var txGainDBi: Double
	var txHeightMeters: Double
	var rxHeightMeters: Double = 1
	var rxGainDBi: Double = 0
	var radiusKm: Double
	var clutterHeightMeters: Double = 1
	/// Percentage of time the prediction holds. P.1812 accepts 1...50.
	var timePercent: Double = 50
}

enum LocalCoverageError: LocalizedError {
	case frequencyOutOfRange

	var errorDescription: String? {
		switch self {
		case .frequencyOutOfRange: return String(localized: "Coverage needs a frequency between 30 and 6000 MHz.")
		}
	}
}

/// Received power on a polar lattice centered on the site, indexed `bearing * rings + ring`.
struct PolarCoverage: Sendable {
	let site: CoverageSite
	let radials: Int
	let rings: Int
	/// Distance of ring 0 from the site, km.
	let firstKm: Double
	let ringStepKm: Double
	let dbm: [Double]

	/// Received power at `ring` of bearing index `bearing`, which wraps.
	func at(_ bearing: Int, _ ring: Int) -> Double {
		let wrapped = ((bearing % radials) + radials) % radials
		return dbm[wrapped * rings + ring]
	}
}

/// Received power on a regular lat/lon grid. Row 0 is north; NaN marks cells outside the disc.
struct CoverageGrid: Sendable {
	let site: CoverageSite
	let width: Int
	let height: Int
	let north: Double
	let south: Double
	let east: Double
	let west: Double
	let dbm: [Double]

	func at(_ x: Int, _ y: Int) -> Double { dbm[y * width + x] }
	func longitude(atColumn x: Double) -> Double { west + (east - west) * x / Double(width - 1) }
	func latitude(atRow y: Double) -> Double { north - (north - south) * y / Double(height - 1) }
}

enum LocalCoverage {
	/// 720 bearings by 128 rings puts about one 256-cell grid cell between samples at a 25 km radius.
	static let defaultRadials = 720
	static let defaultRings = 128
	/// Terrain step along a radial, near Mapterhorn z12's ~37 m. Stepping at 100 m under-reports shadowing.
	static let defaultProfileStepKm = 0.05
	static let defaultGridResolution = 256
	/// P.1812's frequency range.
	static let frequencyRangeMHz: ClosedRange<Double> = 30...6000

	private static let minProfilePoints = 3
	private static let inlandZone: Int32 = 4
	private static let earthRadiusKm = 6371.0
	private static let kmPerDegreeLatitude = 111.32
	/// kp1812's `Atmosphere()` defaults, which its Swift export doesn't carry: the ITU global medians, far inland.
	private static let atmosphere = Atmosphere(deltaN: 45, n0: 325, distanceToCoastTxKm: 500, distanceToCoastRxKm: 500)

	/// Sweep coverage in polar form. Every ring on a bearing is a prefix of that bearing's one terrain profile,
	/// so each radial walks the terrain once. Radials run concurrently; `elevation` must be thread-safe.
	static func sweepPolar(
		site: CoverageSite,
		radials: Int = defaultRadials,
		rings: Int = defaultRings,
		profileStepKm: Double = defaultProfileStepKm,
		elevation: @escaping @Sendable (_ latitude: Double, _ longitude: Double) -> Double
	) async throws -> PolarCoverage {
		precondition(radials >= 8 && rings >= 4 && profileStepKm > 0)
		// kp1812 aborts the process on an out-of-range frequency rather than throwing.
		guard frequencyRangeMHz.contains(site.frequencyMHz) else { throw LocalCoverageError.frequencyOutOfRange }
		let profilePoints = max(Int(site.radiusKm / profileStepKm) + 1, minProfilePoints)
		let stepKm = site.radiusKm / Double(profilePoints - 1)
		// P.1812 needs interior profile points, so the innermost receiver is never the first or second.
		let firstIndex = minProfilePoints - 1
		let indexStride = Double(profilePoints - 1 - firstIndex) / Double(rings - 1)

		// One radial per core but one, at utility priority, so the sweep leaves room for the rest of the app.
		let workers = max(1, ProcessInfo.processInfo.activeProcessorCount - 1)
		let rows = try await withThrowingTaskGroup(of: (Int, [Double]).self) { group in
			var pending = (0..<radials).makeIterator()
			func addNext() {
				guard let bearingIndex = pending.next() else { return }
				group.addTask(priority: .utility) {
					try Task.checkCancellation()
					let bearing = 360.0 * Double(bearingIndex) / Double(radials)
					var latitudes = [Double](repeating: 0, count: profilePoints)
					var heights = [Double](repeating: 0, count: profilePoints)
					for step in 0..<profilePoints {
						let point = destination(latitude: site.latitude, longitude: site.longitude, bearing: bearing, distanceKm: stepKm * Double(step))
						latitudes[step] = point.latitude
						heights[step] = elevation(point.latitude, point.longitude)
					}
					var row = [Double](repeating: 0, count: rings)
					for ring in 0..<rings {
						let end = firstIndex + Int(Double(ring) * indexStride)
						row[ring] = predict(site: site, heights: heights, receiverLatitude: latitudes[end], stepKm: stepKm, end: end)
					}
					return (bearingIndex, row)
				}
			}
			for _ in 0..<workers { addNext() }
			var rows = [[Double]](repeating: [], count: radials)
			for try await (bearingIndex, row) in group {
				rows[bearingIndex] = row
				addNext()
			}
			return rows
		}
		return PolarCoverage(
			site: site,
			radials: radials,
			rings: rings,
			firstKm: stepKm * Double(firstIndex),
			ringStepKm: stepKm * indexStride,
			dbm: rows.flatMap { $0 }
		)
	}

	/// Received power at profile index `end` of a walked radial, from the prefix of `heights` through it.
	static func predict(site: CoverageSite, heights: [Double], receiverLatitude: Double, stepKm: Double, end: Int) -> Double {
		let count = Int32(end + 1)
		let distances = KotlinDoubleArray(size: count)
		let terrain = KotlinDoubleArray(size: count)
		let clutter = KotlinDoubleArray(size: count)
		let zones = KotlinIntArray(size: count)
		for index in 0...end {
			let i = Int32(index)
			distances.set(index: i, value: stepKm * Double(index))
			terrain.set(index: i, value: heights[index])
			clutter.set(index: i, value: site.clutterHeightMeters)
			zones.set(index: i, value: inlandZone)
		}
		let prediction = P1812.shared.predict(
			path: TerrainPath(distancesKm: distances, heightsM: terrain, clutterHeightsM: clutter, zones: zones),
			frequencyGhz: site.frequencyMHz / 1000,
			txHeightM: site.txHeightMeters,
			rxHeightM: site.rxHeightMeters,
			timePercent: site.timePercent,
			pathCenterLatitudeDeg: (site.latitude + receiverLatitude) / 2,
			polarization: Polarization.vertical,
			atmosphere: atmosphere,
			locationPercent: 50,
			locationVariabilityDb: 0
		)
		return P1812.shared.receivedPower(prediction: prediction, txPowerDbm: site.txPowerDBm, txGainDbi: site.txGainDBi, rxGainDbi: site.rxGainDBi)
	}

	/// Resample the polar lattice onto a regular grid, bilinear in bearing and range, so bands follow the
	/// terrain rather than the lattice's spokes. Cells outside the disc are NaN.
	static func grid(from polar: PolarCoverage, resolution: Int = defaultGridResolution) -> CoverageGrid {
		let site = polar.site
		let latitudeSpan = site.radiusKm / kmPerDegreeLatitude
		let longitudeSpan = latitudeSpan / cos(site.latitude * .pi / 180)
		let north = site.latitude + latitudeSpan
		let south = site.latitude - latitudeSpan
		let east = site.longitude + longitudeSpan
		let west = site.longitude - longitudeSpan
		var out = [Double](repeating: .nan, count: resolution * resolution)
		let last = Double(resolution - 1)
		for y in 0..<resolution {
			let latitude = north - (north - south) * Double(y) / last
			for x in 0..<resolution {
				let longitude = west + (east - west) * Double(x) / last
				let km = haversineKm(site.latitude, site.longitude, latitude, longitude)
				if km > site.radiusKm { continue }
				// Inside the first ring and beyond the last both clamp to the nearest ring.
				let ringPosition = min(max((km - polar.firstKm) / polar.ringStepKm, 0), Double(polar.rings - 1))
				let r0 = min(Int(ringPosition.rounded(.down)), polar.rings - 1)
				let r1 = min(r0 + 1, polar.rings - 1)
				let rf = ringPosition - Double(r0)
				let bearingPosition = bearing(site.latitude, site.longitude, latitude, longitude) / 360 * Double(polar.radials)
				let b0 = Int(bearingPosition.rounded(.down))
				let bf = bearingPosition - Double(b0)
				let inner = polar.at(b0, r0) + (polar.at(b0 + 1, r0) - polar.at(b0, r0)) * bf
				let outer = polar.at(b0, r1) + (polar.at(b0 + 1, r1) - polar.at(b0, r1)) * bf
				out[y * resolution + x] = inner + (outer - inner) * rf
			}
		}
		return CoverageGrid(site: site, width: resolution, height: resolution, north: north, south: south, east: east, west: west, dbm: out)
	}

	// MARK: - Geodesy

	/// Great-circle destination from a point along `bearing` (degrees) for `distanceKm`.
	static func destination(latitude: Double, longitude: Double, bearing: Double, distanceKm: Double) -> (latitude: Double, longitude: Double) {
		let angle = distanceKm / earthRadiusKm
		let lat1 = latitude * .pi / 180
		let lon1 = longitude * .pi / 180
		let brg = bearing * .pi / 180
		let lat2 = asin(sin(lat1) * cos(angle) + cos(lat1) * sin(angle) * cos(brg))
		let lon2 = lon1 + atan2(sin(brg) * sin(angle) * cos(lat1), cos(angle) - sin(lat1) * sin(lat2))
		return (lat2 * 180 / .pi, lon2 * 180 / .pi)
	}

	/// Initial great-circle bearing between two points, degrees in 0..<360.
	static func bearing(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
		let p1 = lat1 * .pi / 180
		let p2 = lat2 * .pi / 180
		let dl = (lon2 - lon1) * .pi / 180
		let degrees = atan2(sin(dl) * cos(p2), cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl)) * 180 / .pi
		return (degrees + 360).truncatingRemainder(dividingBy: 360)
	}

	/// Great-circle distance between two points, km.
	static func haversineKm(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
		let dLat = (lat2 - lat1) * .pi / 180
		let dLon = (lon2 - lon1) * .pi / 180
		let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
		return 2 * earthRadiusKm * asin(min(1, sqrt(a)))
	}
}
