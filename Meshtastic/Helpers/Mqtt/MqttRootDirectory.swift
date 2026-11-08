//
//  MqttRootDirectory.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/8/26.
//

import CoreLocation
import Foundation
import OSLog

/// The geography a one-minute sample cannot learn on its own: named community roots, which
/// subdivisions border which, and the topic segment for a geocoder's subdivision name. Shared with
/// the Android app through the Meshtastic API (`/resource/mqttRoots`), so both suggest the same roots
/// for the same place; a copy is bundled for offline use.
struct MqttRootDirectory: Decodable, Equatable {
	/// A community root whose name says nothing about where it is ("msh/US/DMV"), with the area it
	/// serves as ISO 3166-2 subdivisions ("US-VA"), a center and radius, or both.
	struct Entry: Decodable, Equatable {
		let root: String
		let name: String
		var subdivisions: [String] = []
		/// `[latitude, longitude]`; anything else places nothing by radius.
		var center: [Double]?
		var radiusKm: Double?

		private enum CodingKeys: String, CodingKey { case root, name, subdivisions, center, radiusKm }

		init(root: String, name: String, subdivisions: [String] = [], center: [Double]? = nil, radiusKm: Double? = nil) {
			self.root = root
			self.name = name
			self.subdivisions = subdivisions
			self.center = center
			self.radiusKm = radiusKm
		}

		init(from decoder: Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			root = try container.decode(String.self, forKey: .root)
			name = try container.decode(String.self, forKey: .name)
			subdivisions = try container.decodeIfPresent([String].self, forKey: .subdivisions) ?? []
			center = try container.decodeIfPresent([Double].self, forKey: .center)
			radiusKm = try container.decodeIfPresent(Double.self, forKey: .radiusKm)
		}

		func serves(subdivision: String?, at coordinate: CLLocationCoordinate2D?) -> Bool {
			if let subdivision, subdivisions.contains(subdivision) { return true }
			guard let coordinate, let center, center.count == 2, let radiusKm else { return false }
			let distance = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
				.distance(from: CLLocation(latitude: center[0], longitude: center[1]))
			return distance <= radiusKm * 1_000
		}
	}

	var entries: [Entry] = []
	/// ISO 3166-2 code to the codes it borders, both directions present.
	var neighbors: [String: [String]] = [:]
	/// ISO 3166-1 country to a geocoder's subdivision name, lowercased, mapped to the topic segment.
	var subdivisionSegments: [String: [String: String]] = [:]

	private enum CodingKeys: String, CodingKey { case entries, neighbors, subdivisionSegments }

	init(entries: [Entry] = [], neighbors: [String: [String]] = [:], subdivisionSegments: [String: [String: String]] = [:]) {
		self.entries = entries
		self.neighbors = neighbors
		self.subdivisionSegments = subdivisionSegments
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		entries = try container.decodeIfPresent([Entry].self, forKey: .entries) ?? []
		neighbors = try container.decodeIfPresent([String: [String]].self, forKey: .neighbors) ?? [:]
		subdivisionSegments = try container.decodeIfPresent([String: [String: String]].self, forKey: .subdivisionSegments) ?? [:]
	}

	static let empty = MqttRootDirectory()
	static let endpoint = URL(string: "https://api.meshtastic.org/resource/mqttRoots")!

	/// The segment for a geocoder's subdivision name: the directory's code ("Washington" -> "WA"),
	/// else the name as given.
	func subdivisionSegment(countryCode: String?, name: String) -> String {
		guard let countryCode else { return name }
		return subdivisionSegments[countryCode.uppercased()]?[name.lowercased()] ?? name
	}

	func entries(servingSubdivision subdivision: String?, at coordinate: CLLocationCoordinate2D?) -> [Entry] {
		entries.filter { $0.serves(subdivision: subdivision, at: coordinate) }
	}

	/// Decoded with lowercased name keys, or nil for a document without subdivision names: a degraded
	/// response must not replace the names the ladder needs.
	static func decode(_ data: Data) -> MqttRootDirectory? {
		guard var directory = try? JSONDecoder().decode(MqttRootDirectory.self, from: data),
			  directory.subdivisionSegments.values.contains(where: { !$0.isEmpty }) else { return nil }
		directory.subdivisionSegments = Dictionary(
			directory.subdivisionSegments.map { country, names in
				(country.uppercased(), Dictionary(names.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first }))
			},
			uniquingKeysWith: { first, _ in first })
		return directory
	}

	/// The copy shipped in the app.
	static func bundled() -> MqttRootDirectory {
		guard let url = Bundle.main.url(forResource: "mqtt_roots", withExtension: "json"),
			  let data = try? Data(contentsOf: url),
			  let directory = decode(data) else {
			Logger.mqtt.warning("🔎 [MQTT Topics] bundled mqtt_roots.json missing or unreadable")
			return .empty
		}
		return directory
	}

	/// The published directory, or nil when the network or the response fails, leaving the caller on
	/// the bundled copy.
	static func fetch() async -> MqttRootDirectory? {
		var request = URLRequest(url: endpoint)
		request.cachePolicy = .reloadRevalidatingCacheData
		do {
			let (data, _) = try await URLSession(configuration: .meshtasticAPI).dataWithETag(for: request)
			guard let directory = decode(data) else {
				Logger.mqtt.warning("🔎 [MQTT Topics] mqttRoots response has no subdivision names; keeping the bundled copy")
				return nil
			}
			return directory
		} catch {
			Logger.mqtt.info("🔎 [MQTT Topics] mqttRoots fetch failed, using the bundled copy: \(error.localizedDescription, privacy: .public)")
			return nil
		}
	}
}
