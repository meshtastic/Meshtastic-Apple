//
//  CoverageEstimateRunner.swift
//  Meshtastic
//
//  Runs a coverage estimate on the device: fetches Mapterhorn terrain around the
//  site, predicts received power with kp1812 (ITU-R P.1812), and imports the
//  resulting signal bands as a map overlay. Needs the network only for terrain
//  tiles it hasn't cached yet.
//

import Foundation
import CoreLocation
import OSLog

/// Progress of a single coverage run.
enum CoverageEstimateState: Equatable {
	case idle
	case running
	case imported
	case failed(String)
}

/// Geographic bounding box (degrees) of an imported coverage overlay, used to frame the map on it.
struct CoverageBounds: Codable, Equatable, Sendable {
	let minLatitude: Double
	let maxLatitude: Double
	let minLongitude: Double
	let maxLongitude: Double
}

/// The result of a successful run: the imported overlay's metadata, the transmitter coordinate, and
/// the coverage geometry's bounding box (to frame the map on it). `Equatable` (by a per-result
/// token) so it can drive a SwiftUI `onChange`.
struct CoverageEstimateResult: Equatable {
	let token = UUID()
	let metadata: MapDataMetadata
	let coordinate: CLLocationCoordinate2D
	/// Bounding box of the imported coverage geometry, when derivable from the GeoJSON.
	let boundingBox: CoverageBounds?

	static func == (lhs: CoverageEstimateResult, rhs: CoverageEstimateResult) -> Bool {
		lhs.token == rhs.token
	}
}

@MainActor
final class CoverageEstimateRunner: ObservableObject {

	@Published private(set) var state: CoverageEstimateState = .idle

	/// The most recent successful import (overlay metadata + transmitter coordinate).
	/// Observe via `onChange` to recenter the map and enable the overlay.
	@Published private(set) var importedResult: CoverageEstimateResult?

	private var task: Task<Void, Never>?

	/// Whether a run is currently in flight.
	var isRunning: Bool { state == .running }

	/// Start a coverage run for `params`. Requires a valid coordinate. `nodeNum` is the node the run is
	/// for, saved with the estimate; nil when it is for another location.
	func start(params: SitePlannerParameters, nodeNum: Int64? = nil) {
		cancel()
		guard params.isValid else {
			state = .failed(String(localized: "Invalid coverage parameters."))
			return
		}
		state = .running
		task = Task { [weak self] in
			do {
				let started = Date()
				let geoJSON = try await Self.estimate(params)
				try Task.checkCancellation()
				Logger.services.info("🗺️ [Coverage] Estimate for \(params.maxRangeKm, privacy: .public) km took \(Date().timeIntervalSince(started), privacy: .public) s")
				await self?.importCoverage(geoJSON, params: params, nodeNum: nodeNum)
			} catch is CancellationError {
				return
			} catch {
				// A cancelled fetch can surface as a URL error; the run was cancelled, not failed.
				guard !Task.isCancelled else { return }
				Logger.services.error("🗺️ [Coverage] Estimate failed: \(error.localizedDescription, privacy: .public)")
				self?.state = .failed(error.localizedDescription)
			}
		}
	}

	/// Cancel any in-flight run.
	func cancel() {
		task?.cancel()
		task = nil
		if state == .running { state = .idle }
	}

	/// Reset back to idle (e.g. when the form is dismissed after success/failure).
	func reset() {
		cancel()
		state = .idle
	}

	// MARK: - Private

	/// Terrain, sweep and bands for `params`, off the main actor.
	nonisolated static func estimate(_ params: SitePlannerParameters) async throws -> String {
		let site = CoverageSite(
			name: params.name.trimmingCharacters(in: .whitespacesAndNewlines),
			latitude: params.latitude,
			longitude: params.longitude,
			frequencyMHz: params.txFrequencyMHz,
			txPowerDBm: 10 * log10(params.txPowerWatts) + 30,
			txGainDBi: params.txGainDBi,
			txHeightMeters: params.txHeightMeters,
			radiusKm: params.maxRangeKm
		)
		let terrain = try await CoverageTerrainLoader.load(latitude: site.latitude, longitude: site.longitude, radiusKm: site.radiusKm)
		let polar = try await LocalCoverage.sweepPolar(site: site) { latitude, longitude in
			terrain.elevation(latitude: latitude, longitude: longitude)
		}
		// Bands start at the receiver's sensitivity, so the outermost one is where a node can hear the site at all.
		let style = CoverageStyle(colorScale: params.colorScale, minDBm: params.rxSensitivityDBm, maxDBm: params.rxSensitivityDBm + 50)
		return LocalCoverage.grid(from: polar).geoJSON(style: style)
	}

	private func importCoverage(_ geoJSON: String, params: SitePlannerParameters, nodeNum: Int64?) async {
		let coordinate = CLLocationCoordinate2D(latitude: params.latitude, longitude: params.longitude)
		let layerName = params.name.trimmingCharacters(in: .whitespacesAndNewlines)
		let importName = layerName.isEmpty ? "Coverage" : layerName
		let boundingBox = Self.boundingBox(fromGeoJSON: geoJSON)
		let coverage = SitePlannerCoverageInfo(
			nodeNum: nodeNum, latitude: params.latitude, longitude: params.longitude,
			maxRangeKm: params.maxRangeKm, txHeightMeters: params.txHeightMeters,
			colorScale: params.colorScale.rawValue, bounds: boundingBox
		)
		do {
			let metadata = try await MapDataManager.shared.importFromString(geoJSON, name: importName, source: .sitePlanner, coverage: coverage)
			importedResult = CoverageEstimateResult(metadata: metadata, coordinate: coordinate, boundingBox: boundingBox)
			state = .imported
		} catch {
			state = .failed(error.localizedDescription)
		}
	}

	/// Compute the bounding box of every position in a GeoJSON string. Walks the parsed JSON
	/// generically: any array whose first element is a number is a `[lon, lat, …]` position, and
	/// everything else is a container to recurse into — so it works for Point / LineString / Polygon /
	/// MultiPolygon without a schema. Returns nil when no positions are found.
	nonisolated static func boundingBox(fromGeoJSON geoJSON: String) -> CoverageBounds? {
		guard let data = geoJSON.data(using: .utf8),
			  let root = try? JSONSerialization.jsonObject(with: data) else { return nil }
		var minLat = Double.infinity, maxLat = -Double.infinity
		var minLon = Double.infinity, maxLon = -Double.infinity
		func walk(_ node: Any) {
			if let array = node as? [Any] {
				if let lon = array.first as? Double, array.count >= 2, let lat = array[1] as? Double {
					minLat = min(minLat, lat); maxLat = max(maxLat, lat)
					minLon = min(minLon, lon); maxLon = max(maxLon, lon)
				} else {
					array.forEach(walk)
				}
			} else if let dict = node as? [String: Any] {
				dict.values.forEach(walk)
			}
		}
		walk(root)
		guard minLat <= maxLat, minLon <= maxLon else { return nil }
		return CoverageBounds(minLatitude: minLat, maxLatitude: maxLat, minLongitude: minLon, maxLongitude: maxLon)
	}
}
