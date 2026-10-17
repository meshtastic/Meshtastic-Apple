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

import Foundation
import OSLog

struct WidgetMapMeta: Codable {
	static let currentVersion = 2

	var version: Int = WidgetMapMeta.currentVersion
	let generatedAt: Date
	/// The nodes drawn on the image. The widget joins these with the live
	/// snapshot for online counts and distances, so those stay current
	/// between renders, which only happen when a pin moves.
	let nodeNums: [Int64]
	/// The connected radio's node, ringed on the map.
	let radioNum: Int64?

	var nodeCount: Int { nodeNums.count }
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

	/// The square image serves small and medium; the wide one serves large.
	static func imageURL(wide: Bool) -> URL? {
		containerURL?.appendingPathComponent(wide ? "widget-map-wide.png" : "widget-map-square.png")
	}

	static var metaURL: URL? {
		containerURL?.appendingPathComponent(metaFilename)
	}

	/// Writes both images and then the meta sidecar. Returns false when
	/// anything failed, so the renderer can retry instead of marking success.
	static func save(squareImage: Data, wideImage: Data, meta: WidgetMapMeta) -> Bool {
		guard let metaURL, let squareURL = imageURL(wide: false), let wideURL = imageURL(wide: true) else {
			logger.warning("No app group container; widget map not written.")
			return false
		}
		do {
			let options: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
			try squareImage.write(to: squareURL, options: options)
			try wideImage.write(to: wideURL, options: options)
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
		for wide in [false, true] {
			if let url = imageURL(wide: wide) {
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

	static func loadImageData(wide: Bool) -> Data? {
		guard let url = imageURL(wide: wide) else { return nil }
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
