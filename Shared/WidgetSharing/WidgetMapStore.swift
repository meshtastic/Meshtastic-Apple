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
	static let currentVersion = 1

	var version: Int = WidgetMapMeta.currentVersion
	let generatedAt: Date
	/// How many nodes have a pin on the image.
	let nodeCount: Int
}

enum WidgetMapStore {
	static let metaFilename = "widget-map.json"

	private static let logger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "Meshtastic",
		category: "🧩 WidgetSharing"
	)

	/// The square image serves small and large; the wide one serves medium —
	/// cropping the square to medium's 2:1 cut off the north/south pins.
	static func imageURL(dark: Bool, wide: Bool) -> URL? {
		let name = "widget-map\(wide ? "-wide" : "")\(dark ? "-dark" : "-light").png"
		return FileManager.default
			.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshotStore.appGroupID)?
			.appendingPathComponent(name)
	}

	static var metaURL: URL? {
		FileManager.default
			.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshotStore.appGroupID)?
			.appendingPathComponent(metaFilename)
	}

	/// Writes all four images and then the meta sidecar. Returns false when
	/// anything failed, so the renderer can retry instead of marking success.
	static func save(images: [(data: Data, dark: Bool, wide: Bool)], meta: WidgetMapMeta) -> Bool {
		guard let metaURL else {
			logger.warning("No app group container; widget map not written.")
			return false
		}
		do {
			let options: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
			for image in images {
				guard let url = imageURL(dark: image.dark, wide: image.wide) else { return false }
				try image.data.write(to: url, options: options)
			}
			let encoder = JSONEncoder()
			encoder.dateEncodingStrategy = .millisecondsSince1970
			try (try encoder.encode(meta)).write(to: metaURL, options: options)
			return true
		} catch {
			logger.error("Could not write the widget map: \(error.localizedDescription, privacy: .public)")
			return false
		}
	}

	/// For a mesh with no node positions: no images, a meta that says so —
	/// the widget then explains instead of prompting to open the app.
	static func saveEmpty(meta: WidgetMapMeta) -> Bool {
		guard let metaURL else { return false }
		for dark in [false, true] {
			for wide in [false, true] {
				if let url = imageURL(dark: dark, wide: wide) {
					try? FileManager.default.removeItem(at: url)
				}
			}
		}
		do {
			let encoder = JSONEncoder()
			encoder.dateEncodingStrategy = .millisecondsSince1970
			try (try encoder.encode(meta)).write(to: metaURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
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

	static func loadImageData(dark: Bool, wide: Bool) -> Data? {
		guard let url = imageURL(dark: dark, wide: wide) else { return nil }
		return try? Data(contentsOf: url)
	}
}
