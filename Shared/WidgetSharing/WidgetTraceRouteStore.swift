//
//  WidgetTraceRouteStore.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/16/26.
//
//  The most recent trace route for the trace route widget: the route drawn on
//  a map, as images the app renders, plus the route's details as plain values
//  the widget lays out itself. Same app group, file protection and version
//  check as the widget snapshot.
//

import Foundation
import OSLog

struct WidgetTraceRoute: Codable {
	static let currentVersion = 1

	struct Stop: Codable {
		let num: Int64
		let shortName: String
		let longName: String
		/// A repeater that didn't add its number; drawn as a dashed "?".
		let isUnknownRepeater: Bool
		let viaMqtt: Bool
	}

	var version: Int = WidgetTraceRoute.currentVersion
	let generatedAt: Date
	/// The trace route's id, for the deep link to the route on the map.
	let routeId: Int64
	/// When the response arrived.
	let time: Date?
	/// Seen on the mesh rather than requested from this radio.
	let observed: Bool
	/// Every stop on the way out, origin first and destination last.
	let forward: [Stop]
	/// Every stop on the way back; empty when the response didn't carry a return path.
	let back: [Stop]
	let roundTrip: TimeInterval?
	/// Length of the forward path in meters, when every endpoint had a position.
	let distance: Double?
	let bestSNR: Float?
	let worstSNR: Float?
	/// False when too few stops had a position to draw a map, or the map
	/// couldn't be drawn this time (the details still show).
	var hasMap: Bool

	var origin: Stop? { forward.first }
	var destination: Stop? { forward.last }
	var hopsTowards: Int { max(forward.count - 2, 0) }
	var hopsBack: Int? { back.isEmpty ? nil : max(back.count - 2, 0) }
}

enum WidgetTraceRouteStore {
	static let metaFilename = "widget-traceroute.json"
	private static let imagePrefix = "widget-traceroute-"

	private static let logger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "Meshtastic",
		category: "🧩 WidgetSharing"
	)

	private static var containerURL: URL? {
		FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshotStore.appGroupID)
	}

	/// Images are named for their route, so the sidecar can only ever point at
	/// its own route's map. `wide` serves the large family; the square one
	/// serves small and medium.
	static func imageURL(routeId: Int64, wide: Bool) -> URL? {
		containerURL?.appendingPathComponent("\(imagePrefix)\(routeId)-\(wide ? "wide" : "square").png")
	}

	static var metaURL: URL? {
		containerURL?.appendingPathComponent(metaFilename)
	}

	/// Writes the images (none when the route has no map), then the sidecar,
	/// then removes the previous route's images. A failure part way leaves the
	/// old sidecar pointing at the old images. Returns false when anything
	/// failed, so the renderer can retry.
	static func save(route: WidgetTraceRoute, squareImage: Data?, wideImage: Data?) -> Bool {
		guard let metaURL else {
			logger.warning("No app group container; widget trace route not written.")
			return false
		}
		let options: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
		do {
			if let squareImage, let wideImage {
				guard let squareURL = imageURL(routeId: route.routeId, wide: false),
					  let wideURL = imageURL(routeId: route.routeId, wide: true) else { return false }
				try squareImage.write(to: squareURL, options: options)
				try wideImage.write(to: wideURL, options: options)
			}
			let encoder = JSONEncoder()
			encoder.dateEncodingStrategy = .millisecondsSince1970
			try (try encoder.encode(route)).write(to: metaURL, options: options)
		} catch {
			logger.error("Could not write the widget trace route: \(error.localizedDescription, privacy: .public)")
			return false
		}
		removeImages(keeping: route.hasMap ? route.routeId : nil)
		return true
	}

	/// Removes the sidecar and every image: no stored route is left to show.
	static func clear() {
		if let metaURL {
			try? FileManager.default.removeItem(at: metaURL)
		}
		removeImages(keeping: nil)
	}

	static func load() -> WidgetTraceRoute? {
		guard let metaURL, let data = try? Data(contentsOf: metaURL) else { return nil }
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .millisecondsSince1970
		guard let route = try? decoder.decode(WidgetTraceRoute.self, from: data),
			  route.version == WidgetTraceRoute.currentVersion else { return nil }
		return route
	}

	static func loadImageData(routeId: Int64, wide: Bool) -> Data? {
		guard let url = imageURL(routeId: routeId, wide: wide) else { return nil }
		return try? Data(contentsOf: url)
	}

	private static func removeImages(keeping routeId: Int64?) {
		guard let containerURL,
			  let names = try? FileManager.default.contentsOfDirectory(atPath: containerURL.path) else { return }
		let kept = routeId.map { "\(imagePrefix)\($0)-" }
		for name in names where name.hasPrefix(imagePrefix) && name.hasSuffix(".png") {
			if let kept, name.hasPrefix(kept) { continue }
			try? FileManager.default.removeItem(at: containerURL.appendingPathComponent(name))
		}
	}
}
