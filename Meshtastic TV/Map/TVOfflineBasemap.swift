//
//  TVOfflineBasemap.swift
//  Meshtastic TV
//
//  Copyright(c) Garth Vander Houwen 8/14/26.
//
//  Downloads an offline Protomaps basemap covering the mesh, using the same
//  PMTilesExtractor and OfflineMapManager as iOS.
//
//  There is no file picker and no map-dragging region selector on tvOS, so the
//  region is derived from the mesh itself: take the bounding box of every node
//  that has reported a position, pad it, and extract that. One button, no
//  panning with the remote.
//
//  The archive lives in Caches (see OfflineMapManager.directoryURL), which tvOS
//  may purge — `needsDownload` goes back to true if that happens and the user
//  can re-download.
//

import Foundation
import MapKit
import OSLog
import SwiftUI

@MainActor
final class TVOfflineBasemap: ObservableObject {

	enum State: Equatable {
		case idle
		case preparing
		case downloading(fraction: Double)
		case ready
		case failed(String)
	}

	@Published private(set) var state: State = .idle

	/// Region the app downloaded for this mesh, if it is still on disk.
	@Published private(set) var region: OfflineMapRegion?

	/// Padding applied to the mesh bounding box so the map has context around the
	/// outermost nodes rather than clipping at them.
	private let paddingDegrees = 0.15

	/// The smallest box worth extracting. A mesh whose nodes all sit on one spot
	/// would otherwise produce a box of nearly zero area.
	private let minimumSpanDegrees = 0.25

	/// z0-z13 is the standard detail level: full road network without the z14/z15
	/// building footprints, which multiply the download size for little value at
	/// the viewing distance of a television.
	private let detail = OfflineMapDetailLevel.standard

	private let extractor = PMTilesExtractor()

	init() {
		refresh()
	}

	/// Adopts whatever the manager already has on disk. Called at launch and after
	/// a download so the map picks the archive up without restarting the app.
	func refresh() {
		region = OfflineMapManager.shared.regions.first
		if region != nil, case .idle = state {
			state = .ready
		}
	}

	var needsDownload: Bool { region == nil }

	/// Bounding box covering every located node, padded, or nil when no node has a position yet.
	static func bounds(for nodes: [MeshNode], padding: Double, minimumSpan: Double) -> GeoBounds? {
		let coordinates = nodes.compactMap(\.coordinate)
		guard !coordinates.isEmpty else { return nil }

		var minLat = Double.greatestFiniteMagnitude
		var maxLat = -Double.greatestFiniteMagnitude
		var minLon = Double.greatestFiniteMagnitude
		var maxLon = -Double.greatestFiniteMagnitude
		for coordinate in coordinates {
			minLat = min(minLat, coordinate.latitude)
			maxLat = max(maxLat, coordinate.latitude)
			minLon = min(minLon, coordinate.longitude)
			maxLon = max(maxLon, coordinate.longitude)
		}

		// Pad, then widen to the minimum span around the centre if the mesh is tightly clustered.
		minLat -= padding; maxLat += padding
		minLon -= padding; maxLon += padding
		if maxLat - minLat < minimumSpan {
			let centre = (maxLat + minLat) / 2
			minLat = centre - minimumSpan / 2
			maxLat = centre + minimumSpan / 2
		}
		if maxLon - minLon < minimumSpan {
			let centre = (maxLon + minLon) / 2
			minLon = centre - minimumSpan / 2
			maxLon = centre + minimumSpan / 2
		}

		return GeoBounds(
			minLon: max(minLon, -180),
			minLat: max(minLat, -85),
			maxLon: min(maxLon, 180),
			maxLat: min(maxLat, 85)
		)
	}

	/// Size the download would be, for the confirmation prompt.
	func estimate(for nodes: [MeshNode]) async -> (tiles: Int, bytes: Int64)? {
		guard let bounds = Self.bounds(for: nodes, padding: paddingDegrees, minimumSpan: minimumSpanDegrees) else {
			return nil
		}
		guard let result = try? await extractor.estimate(
			bounds: bounds,
			minZoom: detail.minZoom,
			maxZoom: detail.maxZoom
		) else { return nil }
		return (result.tileCount, result.bytes)
	}

	/// Extracts the area around the mesh from the current Protomaps daily build.
	func download(for nodes: [MeshNode]) async {
		guard let bounds = Self.bounds(for: nodes, padding: paddingDegrees, minimumSpan: minimumSpanDegrees) else {
			state = .failed(String(localized: "No node has reported a position yet."))
			return
		}
		guard let directory = OfflineMapManager.shared.directoryURL() else {
			state = .failed(String(localized: "Storage is unavailable."))
			return
		}

		state = .preparing
		do {
			guard let build = await extractor.latestBuild() else {
				state = .failed(String(localized: "Could not reach the map server."))
				return
			}
			let plan = try await extractor.makePlan(
				sourceURL: build.url,
				sourceBuild: build.build,
				bounds: bounds,
				minZoom: detail.minZoom,
				maxZoom: detail.maxZoom
			)

			let id = UUID()
			let fileName = "\(id.uuidString).pmtiles"
			let destination = directory.appendingPathComponent(fileName)

			state = .downloading(fraction: 0)
			try await extractor.extract(plan: plan, to: destination) { done, total in
				guard total > 0 else { return }
				let fraction = Double(done) / Double(total)
				Task { @MainActor [weak self] in
					self?.state = .downloading(fraction: fraction)
				}
			}

			let newRegion = OfflineMapRegion(
				id: id,
				name: String(localized: "Mesh Area"),
				fileName: fileName,
				bounds: bounds,
				minZoom: detail.minZoom,
				maxZoom: detail.maxZoom,
				fileSize: 0,
				sourceBuild: build.build
			)
			// Only one region on tvOS — replace whatever was there.
			for existing in OfflineMapManager.shared.regions {
				OfflineMapManager.shared.remove(existing)
			}
			OfflineMapManager.shared.add(newRegion)
			region = OfflineMapManager.shared.regions.first
			state = .ready
			Logger.services.info("🗺️ [Offline] tvOS region extracted from build \(build.build, privacy: .public)")
		} catch {
			Logger.services.error("🗺️ [Offline] tvOS extraction failed: \(error.localizedDescription, privacy: .public)")
			state = .failed(error.localizedDescription)
		}
	}

	func removeDownloadedRegion() {
		for existing in OfflineMapManager.shared.regions {
			OfflineMapManager.shared.remove(existing)
		}
		region = nil
		state = .idle
	}
}
