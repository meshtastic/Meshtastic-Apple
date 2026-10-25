//
//  MqttTopicDiscoveryTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/11/26.
//

import CoreLocation
import Foundation
@testable import Meshtastic
import MeshtasticProtobufs
import Testing

@Suite("MQTT topic discovery")
struct MqttTopicDiscoveryTests {

	private typealias Discovery = MqttTopicDiscovery

	private func makeEnvelope(
		gatewayID: String = "!aabbccdd",
		channelID: String = "LongFast",
		from: UInt32 = 0,
		payload: MeshPacket.OneOf_PayloadVariant? = nil
	) -> ServiceEnvelope {
		var env = ServiceEnvelope()
		env.gatewayID = gatewayID
		env.channelID = channelID
		var packet = MeshPacket()
		packet.from = from
		if let payload { packet.payloadVariant = payload }
		env.packet = packet
		return env
	}

	private func mapReportPayload(latitudeI: Int32, longitudeI: Int32, online: UInt32) throws -> MeshPacket.OneOf_PayloadVariant {
		var report = MapReport()
		report.latitudeI = latitudeI
		report.longitudeI = longitudeI
		report.numOnlineLocalNodes = online
		var data = DataMessage()
		data.portnum = .mapReportApp
		data.payload = try report.serializedData()
		return .decoded(data)
	}

	private let seattle = CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321)

	// MARK: Topic parsing

	@Test func packetTopicParses() {
		let wa = Discovery.observation(fromTopic: "msh/US/WA/2/e/LongFast/!a1b2c3d4")
		#expect(wa == Discovery.Observation(root: "msh/US/WA", kind: .packet(channel: "LongFast", gateway: "!a1b2c3d4")))
		let pki = Discovery.observation(fromTopic: "msh/US/2/e/PKI/!deadbeef")
		#expect(pki == Discovery.Observation(root: "msh/US", kind: .packet(channel: "PKI", gateway: "!deadbeef")))
	}

	@Test func mapTopicParses() {
		let norway = Discovery.observation(fromTopic: "msh/NO/Møre_og_Romsdal/2/e/LongFast/!a1b2c3d4")
		#expect(norway?.root == "msh/NO/Møre_og_Romsdal")
		#expect(Discovery.observation(fromTopic: "msh/US/2/map/") == Discovery.Observation(root: "msh/US", kind: .mapReport))
		#expect(Discovery.observation(fromTopic: "msh/EU_868/2/map/") == Discovery.Observation(root: "msh/EU_868", kind: .mapReport))
	}

	@Test func junkIsRejected() {
		let junk = [
			"msh/US/1/c/x", "msh/US/2/json/LongFast/!ab12cd34", "HQ-Gateway-1/node/!0a1b2c3d", "secmesh/v2/box/1",
			"70AAC001CC9C/status", "msh/US/2/e/LongFast/!ABCD1234", "msh/US/2/e/LongFast/abcd1234", "msh/US/2/e//!ab",
			"msh/2/map/", "msh/#", ""
		]
		for topic in junk {
			#expect(Discovery.observation(fromTopic: topic) == nil, "\(topic) should not parse")
		}
	}

	@Test func slashesAndSpacesAreTolerated() {
		#expect(Discovery.observation(fromTopic: "msh/US/KY//2/e/LongFast/!ab12cd34")?.root == "msh/US/KY")
		#expect(Discovery.observation(fromTopic: "msh/US /2/map/")?.root == "msh/US")
		#expect(Discovery.observation(fromTopic: " msh/US/2/map/ ")?.root == "msh/US")
		#expect(Discovery.observation(fromTopic: "msh/US/2/map//")?.root == "msh/US")
	}

	@Test func repeatedSegmentsAreKept() {
		#expect(Discovery.observation(fromTopic: "msh/US/US/FL/2/map/")?.root == "msh/US/US/FL")
		#expect(Discovery.observation(fromTopic: "msh/US/msh/US/2/map/")?.root == "msh/US/msh/US")
		#expect(Discovery.observation(fromTopic: "msh/US/2/2/e/LongFast/!ab12cd34")?.root == "msh/US/2")
	}

	@Test func regexMatchesMeshmap() throws {
		let meshmap = try NSRegularExpression(pattern: "^msh(?:/[^/]+)+/2/(?:e/[^/]+/![0-9a-f]+|map/)$")
		let topics = [
			"msh/US/2/map/", "msh/US/WA/2/map/", "msh/US/WA/seattle/2/e/LongFast/!ab12cd34", "msh/US/2/e/PKI/!00000001",
			"msh/EU_868/DE/2/e/MediumFast/!ffffffff", "msh/US/CA/socalmesh/2/e/LongFast/!1a2b3c4d", "msh/US/IL/Chi/2/map/",
			"msh/US/2/json/LongFast/!ab12cd34", "msh/US/1/c/LongFast/!ab12cd34", "msh/US/2/e/LongFast/!AB12CD34",
			"msh/US/2/e/LongFast/ab12cd34", "msh/2/map/", "msh/US/2/map", "msh/US/2/e/LongFast/", "msh/US//2/e/LongFast/!ab12cd34",
			"msh/US /2/map/", " msh/US/2/map/", "msh/US/US/FL/2/e/LongFast/!ab12cd34", "HQ-Gateway-1/node/!0a1b2c3d", "msh/US/2/e/!ab12cd34",
			"msh", "", "msh/#"
		]
		for topic in topics {
			let normalized = Discovery.normalizedTopic(topic)
			let direct = meshmap.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)) != nil
			#expect((Discovery.observation(fromTopic: topic) != nil) == direct, "\(topic) disagrees with the meshmap filter")
		}
	}

	// MARK: Root topic rules

	@Test func rootProblems() {
		#expect(MqttRootTopic.problem(in: "") == .empty)
		#expect(MqttRootTopic.problem(in: "msh US") == .whitespace)
		#expect(MqttRootTopic.problem(in: "msh/a\u{00A0}b") == .whitespace)
		#expect(MqttRootTopic.problem(in: "msh/a\u{2003}b") == .whitespace)
		#expect(MqttRootTopic.problem(in: "msh/a\u{200B}b") == .whitespace)
		#expect(MqttRootTopic.problem(in: "msh/Zürich") == nil)
		#expect(MqttRootTopic.problem(in: "msh/Norge/Møre og Romsdal".replacingOccurrences(of: " ", with: "_")) == nil)
		// 16 two-byte letters plus "msh/" is 36 bytes, though only 20 characters.
		#expect(MqttRootTopic.problem(in: "msh/" + String(repeating: "Ø", count: 16)) == .tooLong)
		#expect(MqttRootTopic.problem(in: "msh/#") == .wildcard)
		#expect(MqttRootTopic.problem(in: "msh/+") == .wildcard)
		#expect(MqttRootTopic.problem(in: "/msh") == .leadingSlash)
		#expect(MqttRootTopic.problem(in: "msh/") == .trailingSlash)
		#expect(MqttRootTopic.problem(in: "msh//US") == .emptySegment)
		#expect(MqttRootTopic.problem(in: "msh/US/2") == .endsWithVersion)
		let thirtyTwo = "msh/US/" + String(repeating: "a", count: 25)
		#expect(thirtyTwo.utf8.count == 32)
		#expect(MqttRootTopic.problem(in: thirtyTwo) == .tooLong)
		let thirtyOne = "msh/US/" + String(repeating: "a", count: 24)
		#expect(thirtyOne.utf8.count == 31)
		for ok in ["msh", "msh/US/WA/seattle", "mymesh", thirtyOne] {
			#expect(MqttRootTopic.problem(in: ok) == nil, "\(ok) should be accepted")
		}
	}

	@Test func rootSanitize() {
		#expect(MqttRootTopic.sanitized("  msh/US/WA/ ") == "msh/US/WA")
		#expect(MqttRootTopic.sanitized("msh//US") == "msh/US")
		#expect(MqttRootTopic.sanitized("msh") == "msh")
		#expect(MqttRootTopic.sanitized("/msh") == "/msh")
	}

	@Test func firmwareDefaultRoots() {
		#expect(MqttRootTopic.isFirmwareDefault("", regionTopic: "msh/US"))
		#expect(MqttRootTopic.isFirmwareDefault("msh", regionTopic: "msh/US"))
		#expect(MqttRootTopic.isFirmwareDefault("msh/US", regionTopic: "msh/US"))
		#expect(!MqttRootTopic.isFirmwareDefault("msh/US/WA", regionTopic: "msh/US"))
		#expect(!MqttRootTopic.isFirmwareDefault("msh/EU_868", regionTopic: "msh/US"))
		#expect(!MqttRootTopic.isFirmwareDefault("msh/us", regionTopic: "msh/US"))
	}

	@Test func olderFirmwareWarning() {
		func warns(_ root: String, known: Bool = true, atLeast: Bool = false) -> Bool {
			MqttRootTopic.olderFirmwareReplaces(root: root, regionTopic: "msh/US", firmwareKnown: known, firmwareAtLeast281: atLeast)
		}
		#expect(warns("msh/US/WA", known: true, atLeast: false))
		#expect(!warns("msh/US/WA", known: true, atLeast: true))
		#expect(!warns("msh/US/WA", known: false, atLeast: false))
		#expect(!warns("msh/US/WA", known: false, atLeast: true))
		for root in ["msh/US", "msh", "", "mymesh"] {
			#expect(!warns(root), "\(root) should never warn")
		}
	}

	@Test func prefixIsSegmentWise() {
		#expect(MqttRootTopic.root("msh/US/WA/seattle", hasPrefix: "msh/US/WA"))
		#expect(!MqttRootTopic.root("msh/US/WAX", hasPrefix: "msh/US/WA"))
		#expect(MqttRootTopic.root("msh/us/wa", hasPrefix: "msh/US/WA"))
	}

	// MARK: Ladder

	@Test func ladderHasThreeRungs() {
		let ladder = Discovery.ladder(regionTopic: "msh/US", regionName: "United States", state: "WA", city: "Seattle")
		#expect(ladder.map(\.topic) == ["msh/US", "msh/US/WA", "msh/US/WA/seattle"])
		#expect(ladder.map(\.level) == [.region, .state, .city])
		#expect(ladder.map(\.placeName) == ["United States", "WA", "Seattle"])
	}

	@Test func ladderDropsMissingRungs() {
		#expect(Discovery.ladder(regionTopic: "msh/US", regionName: "United States", state: nil, city: nil).count == 1)
		#expect(Discovery.ladder(regionTopic: "msh/US", regionName: "United States", state: "WA", city: nil).count == 2)
		#expect(Discovery.ladder(regionTopic: "msh/US", regionName: "United States", state: nil, city: "Seattle").count == 1)
	}

	@Test func ladderKeepsLettersInAnyScript() {
		let bayern = Discovery.ladder(regionTopic: "msh/EU_868", regionName: "EU 868", state: "Bayern", city: "München")
		#expect(bayern.last?.topic == "msh/EU_868/Bayern/münchen")
		#expect(Discovery.segment(from: "St. John's", lowercased: true) == "stjohns")
		#expect(Discovery.segment(from: "Coeur d'Alene", lowercased: true) == "coeurdalene")
		#expect(Discovery.segment(from: "Łódź", lowercased: true) == "łódź")
		#expect(Discovery.segment(from: "Straße", lowercased: true) == "straße")
		#expect(Discovery.segment(from: "Ørsta", lowercased: true) == "ørsta")
		#expect(Discovery.segment(from: "Møre og Romsdal", lowercased: false) == "MøreogRomsdal")
		// Decomposed input (u + combining diaeresis) is composed first.
		#expect(Discovery.segment(from: "Zu\u{0308}rich", lowercased: true) == "zürich")
		let longCity = String(repeating: "x", count: 40)
		let trimmed = Discovery.ladder(regionTopic: "msh/US", regionName: "United States", state: "WA", city: longCity)
		#expect(trimmed.count == 3)
		#expect(trimmed.last?.topic.utf8.count == 31)
		let tokyo = Discovery.ladder(regionTopic: "msh/JP", regionName: "Japan", state: "東京都", city: "渋谷区")
		#expect(tokyo.map(\.level) == [.region, .state, .city])
		#expect(tokyo.last?.topic == "msh/JP/東京都/渋谷区")
		#expect(Discovery.segment(from: "!?.", lowercased: true) == nil)
	}

	// MARK: Tally

	@Test func tallyCountsSendersAndGateways() {
		var tally = Discovery.Tally()
		let packets: [(String, UInt32)] = [
			("msh/US/WA/2/e/LongFast/!000000a1", 0x11),
			("msh/US/WA/2/e/PKI/!000000b2", 0x22),
			("msh/US/WA/2/e/LongFast/!000000a1", 0x11)
		]
		for (topic, from) in packets {
			let payload = (try? makeEnvelope(from: from, payload: .encrypted(Data([1, 2, 3]))).serializedData()) ?? Data()
			tally.record(topic: topic, payload: payload)
		}
		let activity = tally.activity["msh/US/WA"]
		#expect(activity?.packets == 3)
		#expect(activity?.nodes == ["!000000a1", "!000000b2", "!00000011", "!00000022"])
		#expect(activity?.channels == ["LongFast", "PKI"])
	}

	@Test func tallyIgnoresJunk() {
		var tally = Discovery.Tally()
		#expect(tally.record(topic: "HQ-Gateway-1/node/!x", payload: Data([1, 2, 3])) == nil)
		#expect(tally.activity.isEmpty)
		let observation = tally.record(topic: "msh/US/WA/2/e/LongFast/!000000a1", payload: Data([0xFF, 0xFF, 0xFF]))
		#expect(observation?.root == "msh/US/WA")
		#expect(tally.activity["msh/US/WA"]?.packets == 1)
		#expect(tally.activity["msh/US/WA"]?.nodes == ["!000000a1"])
	}

	@Test func tallyIsBounded() {
		var tally = Discovery.Tally()
		for i in 0..<(Discovery.Tally.maxRoots + 1) {
			tally.record(topic: "msh/US/r\(i)/2/map/", payload: Data())
		}
		#expect(tally.activity.count == Discovery.Tally.maxRoots)
		#expect(tally.droppedRoots == 1)

		var crowded = Discovery.Tally()
		for i in 0..<(Discovery.Activity.maxNodes + 1) {
			crowded.record(topic: "msh/US/2/e/LongFast/!\(String(format: "%08x", i + 1))", payload: Data())
		}
		#expect(crowded.activity["msh/US"]?.packets == Discovery.Activity.maxNodes + 1)
		#expect(crowded.activity["msh/US"]?.nodeCount == Discovery.Activity.maxNodes)

		var noisy = Discovery.Tally()
		for i in 0..<(Discovery.Activity.maxChannels + 1) {
			noisy.record(topic: "msh/US/2/e/ch\(i)/!00000001", payload: Data())
		}
		#expect(noisy.activity["msh/US"]?.packets == Discovery.Activity.maxChannels + 1)
		#expect(noisy.activity["msh/US"]?.channels.count == Discovery.Activity.maxChannels)
	}

	// MARK: Map reports

	@Test func mapReportDecodes() throws {
		let payload = try mapReportPayload(latitudeI: 476_062_000, longitudeI: -1_223_321_000, online: 7)
		let summary = try #require(Discovery.mapReport(from: makeEnvelope(payload: payload)))
		#expect(summary.reporter == "!aabbccdd")
		#expect(abs((summary.latitude ?? 0) - 47.6062) < 0.000_001)
		#expect(abs((summary.longitude ?? 0) + 122.3321) < 0.000_001)
		#expect(summary.onlineLocalNodes == 7)

		#expect(Discovery.mapReport(from: makeEnvelope(payload: .encrypted(Data([1, 2])))) == nil)
		var position = DataMessage()
		position.portnum = .positionApp
		#expect(Discovery.mapReport(from: makeEnvelope(payload: .decoded(position))) == nil)

		let anonymous = Discovery.mapReport(from: makeEnvelope(gatewayID: "", from: 0x0a1b_2c3d, payload: payload))
		#expect(anonymous?.reporter == "!0a1b2c3d")

		let noPosition = try Discovery.mapReport(from: makeEnvelope(payload: mapReportPayload(latitudeI: 0, longitudeI: 0, online: 1)))
		#expect(noPosition?.latitude == nil)
		#expect(noPosition?.longitude == nil)
	}

	@Test func activityRecordsMapReport() {
		var activity = Discovery.Activity()
		activity.record(Discovery.MapReportSummary(reporter: "!aabbccdd", latitude: 47.6062, longitude: -122.3321, onlineLocalNodes: 7))
		#expect(activity.nodes.contains("!aabbccdd"))
		#expect(activity.positions["!aabbccdd"] != nil)
		#expect(activity.onlineLocalNodes == 7)
		let distance = activity.nearestDistance(from: seattle)
		#expect(distance != nil && distance! < 1_000)
		activity.record(Discovery.MapReportSummary(reporter: "!00000002", latitude: nil, longitude: nil, onlineLocalNodes: 3))
		#expect(activity.onlineLocalNodes == 7)
	}

	// MARK: Ranking

	private func activity(nodes: Int, position: CLLocationCoordinate2D? = nil) -> Discovery.Activity {
		var activity = Discovery.Activity()
		for i in 0..<nodes {
			activity.record(.packet(channel: "LongFast", gateway: "!0000000\(i)"), sender: nil)
		}
		if let position {
			activity.record(Discovery.MapReportSummary(reporter: "!0000000a", latitude: position.latitude, longitude: position.longitude, onlineLocalNodes: 0))
		}
		return activity
	}

	@Test func rankingPrefersLadderThenDistanceThenCount() {
		let ladder = Discovery.ladder(regionTopic: "msh/US", regionName: "United States", state: "WA", city: "Seattle")
		// Positions are points about 40 km and 7 km from Seattle; the names only label the roots.
		let tacoma = CLLocationCoordinate2D(latitude: 47.2529, longitude: -122.4443)
		let bellingham = CLLocationCoordinate2D(latitude: 47.65, longitude: -122.40)
		let activity: [String: Discovery.Activity] = [
			"msh/US/FL": self.activity(nodes: 10),
			"msh/US/WA/tacoma": self.activity(nodes: 1, position: tacoma),
			"msh/US/WA/bellingham": self.activity(nodes: 1, position: bellingham),
			"msh/US/WA/olympia": self.activity(nodes: 3),
			"msh/US/WA/seattle": self.activity(nodes: 5),
			"msh/US/WA/" + String(repeating: "z", count: 30): self.activity(nodes: 9)
		]
		let ranked = Discovery.ranked(activity, ladder: ladder, from: seattle)
		#expect(ranked.map(\.root) == ["msh/US/WA/bellingham", "msh/US/WA/tacoma", "msh/US/WA/olympia", "msh/US/FL"])
		#expect(ranked.first?.ladderDepth == 2)
		#expect(ranked.last?.ladderDepth == 1)
		let seattleRung = ladder[2]
		#expect(Discovery.activity(forRung: seattleRung, in: activity)?.activity.nodeCount == 5)
	}

	@Test func rungMatchIsCaseInsensitive() {
		let ladder = Discovery.ladder(regionTopic: "msh/US", regionName: "United States", state: "KS", city: "Topeka")
		let activity = ["msh/US/KS/Topeka": self.activity(nodes: 2)]
		let match = Discovery.activity(forRung: ladder[2], in: activity)
		#expect(match?.topic == "msh/US/KS/Topeka")
		#expect(match?.activity.nodeCount == 2)
		#expect(Discovery.ranked(activity, ladder: ladder, from: nil).isEmpty)
	}

	@Test func rungPrefersItsOwnSpellingAndKeepsTheOther() {
		let ladder = Discovery.ladder(regionTopic: "msh/US", regionName: "United States", state: "KS", city: "Topeka")
		let activity = [
			"msh/US/KS/Topeka": self.activity(nodes: 5),
			"msh/US/KS/topeka": self.activity(nodes: 2)
		]
		let match = Discovery.activity(forRung: ladder[2], in: activity)
		#expect(match?.topic == "msh/US/KS/topeka")
		#expect(match?.activity.nodeCount == 2)
		let ranked = Discovery.ranked(activity, ladder: ladder, from: nil)
		#expect(ranked.map(\.root) == ["msh/US/KS/Topeka"])
		#expect(ranked.first?.activity.nodeCount == 5)

		let variants = ["msh/US/KS/TOPEKA": self.activity(nodes: 1), "msh/US/KS/Topeka": self.activity(nodes: 3)]
		#expect(Discovery.activity(forRung: ladder[2], in: variants)?.topic == "msh/US/KS/TOPEKA")
		#expect(Discovery.ranked(variants, ladder: ladder, from: nil).map(\.root) == ["msh/US/KS/Topeka"])
	}
}
