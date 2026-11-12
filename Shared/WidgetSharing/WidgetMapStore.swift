//
//  WidgetMapStore.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/16/26.
//
//  The pre-rendered map images for the map widget. The app renders them with
//  MKMapSnapshotter — the widget process never renders a map (no network, a
//  tight memory cap, and a reload budget) — and this store moves the PNGs and
//  a small metadata sidecar through the app group. File protection is class C
//  so the images still render on a locked phone, like the snapshot.
//

import CoreLocation
import Foundation
import OSLog

struct WidgetMapMeta: Codable {
	static let currentVersion = 2

	var version: Int = WidgetMapMeta.currentVersion
	let generatedAt: Date
	/// The nodes drawn on the image.
	let nodeNums: [Int64]
	/// The connected radio's node, ringed on the map.
	let radioNum: Int64?
	/// The drawn nodes as they were drawn, so the widget's counts and
	/// distance cover a pin that has since left the snapshot's node list.
	/// Nil in metadata written before this was added.
	var pins: [WidgetMapPin]?

	var nodeCount: Int { nodeNums.count }
}

/// One drawn node: where it was drawn, and what the widget needs to count it
/// when it is no longer in the snapshot.
struct WidgetMapPin: Codable, Equatable {
	let num: Int64
	let latitude: Double
	let longitude: Double
	let lastHeard: Date?
	let isFavorite: Bool
}

/// The map widget's counts, over the nodes drawn on the image. Online and
/// favorite come from the live snapshot when it still lists the node, so they
/// stay current between renders, and from the drawn pin otherwise. The
/// distance uses the drawn positions, so it matches the image.
struct WidgetMapStats: Equatable {
	/// Same window as NodeInfoEntity.isOnline.
	static let onlineWindow: TimeInterval = 2 * 3600

	let onMap: Int
	let online: Int
	let favorites: Int
	/// Meters from the radio to the farthest drawn node, when the radio has a
	/// position.
	let farthest: Double?

	init(meta: WidgetMapMeta, snapshot: WidgetSnapshot?, now: Date = .now) {
		let live = Dictionary((snapshot?.nodes ?? []).map { ($0.num, $0) }, uniquingKeysWith: { first, _ in first })
		let drawn = Dictionary((meta.pins ?? []).map { ($0.num, $0) }, uniquingKeysWith: { first, _ in first })

		var online = 0
		var favorites = 0
		var coordinates: [Int64: (lat: Double, lon: Double)] = [:]
		for num in meta.nodeNums {
			if let node = live[num] {
				if node.isOnline { online += 1 }
				if node.isFavorite { favorites += 1 }
			} else if let pin = drawn[num] {
				if let lastHeard = pin.lastHeard, now.timeIntervalSince(lastHeard) < Self.onlineWindow { online += 1 }
				if pin.isFavorite { favorites += 1 }
			}
			if let pin = drawn[num] {
				coordinates[num] = (pin.latitude, pin.longitude)
			} else if let node = live[num], let lat = node.latitude, let lon = node.longitude {
				coordinates[num] = (lat, lon)
			}
		}
		self.onMap = meta.nodeCount
		self.online = online
		self.favorites = favorites

		// The connected radio, not the one the image was drawn for, so the
		// distance and the widget's title name the same radio.
		let radioNum = snapshot?.radioNodeNum ?? meta.radioNum
		if let radioNum, let origin = coordinates[radioNum] {
			let from = CLLocation(latitude: origin.lat, longitude: origin.lon)
			farthest = coordinates
				.filter { $0.key != radioNum }
				.map { from.distance(from: CLLocation(latitude: $0.value.lat, longitude: $0.value.lon)) }
				.max()
		} else {
			farthest = nil
		}
	}
}

/// The shapes the Node Map and Trace Route widgets' maps are rendered in, one
/// per widget size that shows a map.
enum WidgetMapShape: String, CaseIterable {
	/// Small and medium.
	case square
	/// Large.
	case wide
	/// Extra large portrait (iOS 27, Vision Pro).
	case tall

	/// The rendered size, in points.
	var size: CGSize {
		switch self {
		case .square: CGSize(width: 170, height: 170)
		case .wide: CGSize(width: 330, height: 190)
		case .tall: CGSize(width: 330, height: 520)
		}
	}
}

enum WidgetMapStore {
	static let metaFilename = "widget-map.json"

	/// Files from the first version: light and dark images in two shapes.
	private static let legacyFilenames = [
		"widget-map-light.png", "widget-map-dark.png",
		"widget-map-wide-light.png", "widget-map-wide-dark.png"
	]

	private static let logger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "Meshtastic",
		category: "🧩 WidgetSharing"
	)

	private static var containerURL: URL? {
		FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshotStore.appGroupID)
	}

	static func imageURL(_ shape: WidgetMapShape) -> URL? {
		containerURL?.appendingPathComponent("widget-map-\(shape.rawValue).png")
	}

	static var metaURL: URL? {
		containerURL?.appendingPathComponent(metaFilename)
	}

	/// Writes the images and then the meta sidecar, and removes the image of
	/// any shape left out, so the widget doesn't show an older map. Returns
	/// false when anything failed, so the renderer can retry instead of
	/// marking success.
	static func save(images: [WidgetMapShape: Data], meta: WidgetMapMeta) -> Bool {
		guard let metaURL else {
			logger.warning("No app group container; widget map not written.")
			return false
		}
		do {
			let options: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
			for (shape, image) in images {
				guard let url = imageURL(shape) else { return false }
				try image.write(to: url, options: options)
			}
			for shape in WidgetMapShape.allCases where images[shape] == nil {
				if let url = imageURL(shape) {
					try? FileManager.default.removeItem(at: url)
				}
			}
			try encode(meta).write(to: metaURL, options: options)
		} catch {
			logger.error("Could not write the widget map: \(error.localizedDescription, privacy: .public)")
			return false
		}
		removeLegacyFiles()
		return true
	}

	/// For a mesh with no node positions: no images, a meta that says so —
	/// the widget then explains instead of prompting to open the app.
	static func saveEmpty(meta: WidgetMapMeta) -> Bool {
		guard let metaURL else { return false }
		for shape in WidgetMapShape.allCases {
			if let url = imageURL(shape) {
				try? FileManager.default.removeItem(at: url)
			}
		}
		removeLegacyFiles()
		do {
			try encode(meta).write(to: metaURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
			return true
		} catch {
			return false
		}
	}

	static func loadMeta() -> WidgetMapMeta? {
		guard let metaURL,
			  let data = try? Data(contentsOf: metaURL) else { return nil }
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .millisecondsSince1970
		guard let meta = try? decoder.decode(WidgetMapMeta.self, from: data),
			  meta.version == WidgetMapMeta.currentVersion else { return nil }
		return meta
	}

	static func loadImageData(_ shape: WidgetMapShape) -> Data? {
		guard let url = imageURL(shape) else { return nil }
		return try? Data(contentsOf: url)
	}

	private static func encode(_ meta: WidgetMapMeta) throws -> Data {
		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .millisecondsSince1970
		return try encoder.encode(meta)
	}

	private static func removeLegacyFiles() {
		guard let containerURL else { return }
		for name in legacyFilenames {
			try? FileManager.default.removeItem(at: containerURL.appendingPathComponent(name))
		}
	}
}
