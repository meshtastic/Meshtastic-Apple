//
//  MqttTopicDiscovery.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/11/26.
//

import CoreLocation
import Foundation
import MeshtasticProtobufs

/// The root topic rules the firmware and broker impose.
enum MqttRootTopic {
	/// The firmware's buffer: 31 UTF-8 bytes plus the terminator.
	static let byteCap = 31

	enum Problem: Equatable, CaseIterable {
		case empty, whitespace, wildcard, leadingSlash, trailingSlash, emptySegment, endsWithVersion, tooLong

		var message: String {
			switch self {
			case .empty:
				return String(localized: "Enter a topic.", comment: "MQTT root topic rule")
			case .whitespace:
				return String(localized: "Topics cannot contain spaces or control characters.", comment: "MQTT root topic rule")
			case .wildcard:
				return String(localized: "Topics cannot contain + or #.", comment: "MQTT root topic rule")
			case .leadingSlash:
				return String(localized: "Topics cannot start with a slash.", comment: "MQTT root topic rule")
			case .trailingSlash:
				return String(localized: "Topics cannot end with a slash.", comment: "MQTT root topic rule")
			case .emptySegment:
				return String(localized: "Topics cannot contain two slashes in a row.", comment: "MQTT root topic rule")
			case .endsWithVersion:
				return String(localized: "Topics cannot end with /2.", comment: "MQTT root topic rule")
			case .tooLong:
				return String(localized: "Topics are limited to 31 bytes (æ, ø and å use two).", comment: "MQTT root topic rule")
			}
		}
	}

	/// Whitespace trimmed at both ends, runs of "/" collapsed to one, one trailing "/" dropped.
	/// Used only by the sheet's custom field before validating; the form's own field is never rewritten.
	static func sanitized(_ text: String) -> String {
		var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
		while result.contains("//") {
			result = result.replacingOccurrences(of: "//", with: "/")
		}
		if result.hasSuffix("/") {
			result.removeLast()
		}
		return result
	}

	/// First rule broken, in enum order; nil when the radio accepts the root as typed.
	static func problem(in root: String) -> Problem? {
		if root.isEmpty { return .empty }
		let scalars = root.unicodeScalars
		// Any kind of space, control or invisible character, not only the ASCII ones.
		if scalars.contains(where: { $0.properties.isWhitespace || [.control, .format].contains($0.properties.generalCategory) }) { return .whitespace }
		if root.contains("+") || root.contains("#") { return .wildcard }
		if root.hasPrefix("/") { return .leadingSlash }
		if root.hasSuffix("/") { return .trailingSlash }
		if root.contains("//") { return .emptySegment }
		if root.split(separator: "/").last == "2" { return .endsWithVersion }
		if root.utf8.count > byteCap { return .tooLong }
		return nil
	}

	/// "", "msh" and `regionTopic` (the full "msh/<REGION>" string; exact, case-sensitive like the
	/// firmware) are the roots `MQTT::applyRegionRootTopic` treats as its own default.
	static func isFirmwareDefault(_ root: String, regionTopic: String) -> Bool {
		root.isEmpty || root == "msh" || root == regionTopic
	}

	/// Firmware before 2.8.1 overwrote every root starting with "msh" on a region set. Only worth a
	/// warning when the version is known and the root is not one the rewrite leaves correct.
	static func olderFirmwareReplaces(root: String, regionTopic: String, firmwareKnown: Bool, firmwareAtLeast281: Bool) -> Bool {
		firmwareKnown && !firmwareAtLeast281 && root.hasPrefix("msh") && !isFirmwareDefault(root, regionTopic: regionTopic)
	}

	/// Split on "/", each segment trimmed, empties dropped.
	static func segments(_ root: String) -> [String] {
		root.split(separator: "/", omittingEmptySubsequences: true)
			.map { $0.trimmingCharacters(in: .whitespaces) }
			.filter { !$0.isEmpty }
	}

	/// Segment-wise, case-insensitive prefix: "msh/US/WA" is a prefix of "msh/US/WA/seattle" but not of "msh/US/WAX".
	static func root(_ root: String, hasPrefix prefix: String) -> Bool {
		let rootSegments = segments(root)
		let prefixSegments = segments(prefix)
		guard prefixSegments.count <= rootSegments.count else { return false }
		return zip(rootSegments, prefixSegments).allSatisfy { $0.caseInsensitiveCompare($1) == .orderedSame }
	}

	/// Case-insensitive equality.
	static func rootsMatch(_ a: String, _ b: String) -> Bool {
		a.caseInsensitiveCompare(b) == .orderedSame
	}
}

/// Broker topic strings and map-report payloads turned into per-root activity.
enum MqttTopicDiscovery {
	enum Kind: Equatable {
		/// <root>/2/e/<channel>/!<hex>
		case packet(channel: String, gateway: String)
		/// <root>/2/map/
		case mapReport
	}

	struct Observation: Equatable {
		let root: String
		let kind: Kind
	}

	/// meshmap.net's filter with capture groups for the root, channel and gateway.
	static let topicPattern: NSRegularExpression = {
		// The pattern is a literal, so this cannot fail at runtime.
		// swiftlint:disable:next force_try
		try! NSRegularExpression(pattern: "^(msh(?:/[^/]+)+)/2/(?:e/([^/]+)/(![0-9a-f]+)|map/)$")
	}()

	/// Trim the whole string; split on "/"; trim each segment; drop empty segments; rejoin; re-append
	/// the trailing "/" that map topics carry. A root with a trailing slash or space cannot be saved,
	/// so its traffic is credited to the spelling that can. Repeated or doubled segments are kept as
	/// they are: "msh/US/US/FL" and "msh/US/msh/US" are real roots with their own traffic.
	static func normalizedTopic(_ topic: String) -> String {
		let trimmed = topic.trimmingCharacters(in: .whitespacesAndNewlines)
		let joined = MqttRootTopic.segments(trimmed).joined(separator: "/")
		return trimmed.hasSuffix("/") ? joined + "/" : joined
	}

	/// nil for anything that is not a 2/e or 2/map topic (uppercase hex, /1/c/, /2/json/, foreign roots).
	static func observation(fromTopic topic: String) -> Observation? {
		let normalized = normalizedTopic(topic)
		let range = NSRange(normalized.startIndex..., in: normalized)
		guard let match = topicPattern.firstMatch(in: normalized, range: range),
			  let rootRange = Range(match.range(at: 1), in: normalized) else { return nil }
		let root = String(normalized[rootRange])
		if let channelRange = Range(match.range(at: 2), in: normalized),
		   let gatewayRange = Range(match.range(at: 3), in: normalized) {
			return Observation(root: root, kind: .packet(channel: String(normalized[channelRange]), gateway: String(normalized[gatewayRange])))
		}
		return Observation(root: root, kind: .mapReport)
	}

	/// "!%08x" of a node number, the spelling the topic suffix and `UInt32.toHex()` use.
	static func nodeID(_ num: UInt32) -> String {
		String(format: "!%08x", num)
	}

	struct MapReportSummary: Equatable {
		/// envelope.gatewayID, or nodeID(packet.from) when empty
		let reporter: String
		/// nil when latitudeI == 0 && longitudeI == 0
		let latitude: Double?
		let longitude: Double?
		let onlineLocalNodes: Int
	}

	/// Plaintext MapReport out of an envelope. nil for encrypted packets, other portnums, parse errors.
	static func mapReport(from envelope: ServiceEnvelope) -> MapReportSummary? {
		guard envelope.hasPacket,
			  case .decoded(let data) = envelope.packet.payloadVariant,
			  data.portnum == .mapReportApp,
			  let report = try? MapReport(serializedBytes: data.payload) else { return nil }
		let reporter = envelope.gatewayID.isEmpty ? nodeID(envelope.packet.from) : envelope.gatewayID
		let hasPosition = !(report.latitudeI == 0 && report.longitudeI == 0)
		return MapReportSummary(
			reporter: reporter,
			latitude: hasPosition ? Double(report.latitudeI) / 1e7 : nil,
			longitude: hasPosition ? Double(report.longitudeI) / 1e7 : nil,
			onlineLocalNodes: Int(report.numOnlineLocalNodes)
		)
	}

	struct Rung: Identifiable, Equatable {
		enum Level: Equatable { case region, state, city }
		let level: Level
		/// "msh/US/WA"
		let topic: String
		/// "Washington", or whatever the geocoder gave
		let placeName: String
		var id: String { topic }
	}

	/// [region] + [state if segment(state) != nil] + [city if the state rung exists and segment(city) != nil].
	/// Each rung is trimmed from the end of its last segment until it fits the byte cap; a rung whose last
	/// segment empties is dropped together with anything below it.
	static func ladder(regionTopic: String, regionName: String, state: String?, city: String?) -> [Rung] {
		var rungs = [Rung(level: .region, topic: regionTopic, placeName: regionName)]
		guard let state, let stateSegment = segment(from: state, lowercased: false),
			  let stateTopic = fitted(regionTopic, lastSegment: stateSegment) else { return rungs }
		rungs.append(Rung(level: .state, topic: stateTopic, placeName: state))
		guard let city, let citySegment = segment(from: city, lowercased: true),
			  let cityTopic = fitted(stateTopic, lastSegment: citySegment) else { return rungs }
		rungs.append(Rung(level: .city, topic: cityTopic, placeName: city))
		return rungs
	}

	private static func fitted(_ base: String, lastSegment: String) -> String? {
		var segment = lastSegment
		while !segment.isEmpty, (base + "/" + segment).utf8.count > MqttRootTopic.byteCap {
			segment.removeLast()
		}
		return segment.isEmpty ? nil : base + "/" + segment
	}

	/// The place name as the local mesh would write it: letters and digits in any script kept as
	/// they are (æ, ø, å, ü, 東京), "_" and "-" kept, anything else dropped, lowercased when asked.
	/// States keep the geocoder's case ("WA"); cities follow the community's lowercase convention.
	/// nil when nothing is left.
	/// "St. John's" -> "stjohns", "Coeur d'Alene" -> "coeurdalene", "Ørsta" -> "ørsta", "東京都" -> "東京都".
	static func segment(from place: String, lowercased: Bool) -> String? {
		let kept = place.precomposedStringWithCanonicalMapping.unicodeScalars.filter { scalar in
			scalar.properties.isAlphabetic || scalar.properties.numericType != nil || scalar == "_" || scalar == "-"
		}
		let result = String(String.UnicodeScalarView(kept))
		if result.isEmpty { return nil }
		return lowercased ? result.lowercased() : result
	}

	/// Everything heard on one root during a sample.
	struct Activity {
		static let maxNodes = 256
		static let maxPositions = 32
		static let maxChannels = 32
		var packets = 0
		var mapReports = 0
		/// Sender ids from MeshPacket.from plus gateway ids, capped.
		var nodes: Set<String> = []
		/// Channel names from the topic, capped; the row shows the first three.
		var channels: Set<String> = []
		/// By reporter, last report wins, capped.
		var positions: [String: CLLocationCoordinate2D] = [:]
		/// Max MapReport.numOnlineLocalNodes seen.
		var onlineLocalNodes = 0
		/// The region stream was unsubscribed at its cap.
		var truncated = false
		var nodeCount: Int { nodes.count }
		var messageCount: Int { packets + mapReports }

		func nearestDistance(from: CLLocationCoordinate2D?) -> CLLocationDistance? {
			guard let from else { return nil }
			let origin = CLLocation(latitude: from.latitude, longitude: from.longitude)
			return positions.values
				.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: origin) }
				.min()
		}

		mutating func record(_ kind: Kind, sender: String?) {
			switch kind {
			case .packet(let channel, let gateway):
				packets += 1
				if channels.contains(channel) || channels.count < Self.maxChannels {
					channels.insert(channel)
				}
				addNode(gateway)
				if let sender { addNode(sender) }
			case .mapReport:
				mapReports += 1
			}
		}

		mutating func record(_ report: MapReportSummary) {
			addNode(report.reporter)
			if let latitude = report.latitude, let longitude = report.longitude,
			   positions[report.reporter] != nil || positions.count < Self.maxPositions {
				positions[report.reporter] = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
			}
			onlineLocalNodes = max(onlineLocalNodes, report.onlineLocalNodes)
		}

		private mutating func addNode(_ id: String) {
			if nodes.contains(id) || nodes.count < Self.maxNodes {
				nodes.insert(id)
			}
		}
	}

	/// Bounded per-root tally. A new root past `maxRoots` is dropped and counted in `droppedRoots`.
	struct Tally {
		static let maxRoots = 400
		/// An envelope is well under this; anything bigger is not one.
		static let maxEnvelopeBytes = 1_024
		private(set) var activity: [String: Activity] = [:]
		private(set) var droppedRoots = 0

		/// Parses the topic (junk -> nil), credits the root, reads the plaintext sender from the envelope
		/// when it parses, decodes a map report on map topics. Returns the observation so the sampler can
		/// apply the region cap.
		@discardableResult
		mutating func record(topic: String, payload: Data) -> Observation? {
			guard let observation = observation(fromTopic: topic) else { return nil }
			if activity[observation.root] == nil, activity.count >= Self.maxRoots {
				droppedRoots += 1
				return observation
			}
			let envelope = payload.count <= Self.maxEnvelopeBytes ? try? ServiceEnvelope(serializedBytes: payload) : nil
			var sender: String?
			if let envelope, envelope.hasPacket, envelope.packet.from != 0 {
				sender = nodeID(envelope.packet.from)
			}
			var entry = activity[observation.root] ?? Activity()
			entry.record(observation.kind, sender: sender)
			if case .mapReport = observation.kind, let envelope, let report = mapReport(from: envelope) {
				entry.record(report)
			}
			activity[observation.root] = entry
			return observation
		}

		mutating func markTruncated(_ root: String) {
			activity[root, default: Activity()].truncated = true
		}
	}

	struct RankedRoot: Identifiable {
		let root: String
		let activity: Activity
		let ladderDepth: Int
		let distance: CLLocationDistance?
		var id: String { root }
	}

	/// Discovered roots that are not shown on a rung, ranked: more ladder rungs as a prefix first, then
	/// roots with a map-reported position by distance, then node count, message count and name. The
	/// view caps the list. Only the spelling a rung shows is left out; another case variant of the same
	/// root is a separate topic on the broker and keeps its own row here.
	static func ranked(_ activity: [String: Activity], ladder: [Rung], from: CLLocationCoordinate2D?) -> [RankedRoot] {
		let shown = Set(ladder.compactMap { self.activity(forRung: $0, in: activity)?.topic })
		var roots: [RankedRoot] = []
		for (root, entry) in activity {
			if shown.contains(root) { continue }
			if MqttRootTopic.problem(in: root) != nil { continue }
			let depth = ladder.filter { MqttRootTopic.root(root, hasPrefix: $0.topic) }.count
			roots.append(RankedRoot(root: root, activity: entry, ladderDepth: depth, distance: entry.nearestDistance(from: from)))
		}
		return roots.sorted(by: precedes)
	}

	private static func precedes(_ lhs: RankedRoot, _ rhs: RankedRoot) -> Bool {
		if lhs.ladderDepth != rhs.ladderDepth { return lhs.ladderDepth > rhs.ladderDepth }
		switch (lhs.distance, rhs.distance) {
		case let (near?, far?) where near != far: return near < far
		case (.some, .none): return true
		case (.none, .some): return false
		default: break
		}
		if lhs.activity.nodeCount != rhs.activity.nodeCount { return lhs.activity.nodeCount > rhs.activity.nodeCount }
		if lhs.activity.messageCount != rhs.activity.messageCount { return lhs.activity.messageCount > rhs.activity.messageCount }
		return lhs.root.caseInsensitiveCompare(rhs.root) == .orderedAscending
	}

	/// The activity recorded for a rung, with the spelling the broker used, so the row shows and fills
	/// the live topic. The rung's own spelling wins when the broker carries it; otherwise the lowest
	/// case-insensitive match ("msh/US/KS/Topeka" for the rung "msh/US/KS/topeka"), so the row does
	/// not flip between variants from one snapshot to the next.
	static func activity(forRung rung: Rung, in activity: [String: Activity]) -> (topic: String, activity: Activity)? {
		if let exact = activity[rung.topic] { return (rung.topic, exact) }
		guard let key = activity.keys.filter({ MqttRootTopic.rootsMatch($0, rung.topic) }).min(),
			  let entry = activity[key] else { return nil }
		return (key, entry)
	}
}
