//
//  MqttRootDirectoryTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 11/8/26.
//

import CoreLocation
import Foundation
@testable import Meshtastic
import Testing

@Suite("MQTT root directory")
struct MqttRootDirectoryTests {

	private typealias Discovery = MqttTopicDiscovery

	private func activity(packets: Int, nodes: Int = 1) -> Discovery.Activity {
		var activity = Discovery.Activity()
		for index in 0..<packets {
			activity.record(.packet(channel: "LongFast", gateway: "!0000000\(index % max(nodes, 1))"), sender: nil)
		}
		return activity
	}

	private func plan(
		_ regionTopic: String = "msh/US",
		country: String?,
		state: String?,
		city: String? = nil,
		at coordinate: CLLocationCoordinate2D? = nil,
		directory: MqttRootDirectory = MqttRootDirectory.bundled(),
		activity: [String: Discovery.Activity] = [:]
	) -> Discovery.Plan {
		Discovery.plan(
			regionTopic: regionTopic,
			regionName: regionTopic,
			place: Discovery.Place(countryCode: country, state: state, city: city),
			at: coordinate,
			directory: directory,
			activity: activity
		)
	}

	// MARK: Directory

	@Test func bundledCopyDecodes() {
		let directory = MqttRootDirectory.bundled()
		#expect(!directory.entries.isEmpty)
		#expect(directory.subdivisionSegment(countryCode: "us", name: "Washington") == "WA")
		#expect(directory.subdivisionSegment(countryCode: "US", name: "WASHINGTON") == "WA")
		#expect(directory.subdivisionSegment(countryCode: "US", name: "WA") == "WA")
		#expect(directory.subdivisionSegment(countryCode: nil, name: "Washington") == "Washington")
		#expect(directory.neighbors["US-TX"]?.contains("US-AR") == true)
	}

	@Test func degradedDocumentIsRejected() throws {
		#expect(MqttRootDirectory.decode(Data(#"{"entries": []}"#.utf8)) == nil)
		#expect(MqttRootDirectory.decode(Data(#"{"subdivisionSegments": {"US": {}}}"#.utf8)) == nil)
		#expect(MqttRootDirectory.decode(Data("not json".utf8)) == nil)
		let minimal = try #require(MqttRootDirectory.decode(Data(#"{"subdivisionSegments": {"us": {"Texas": "TX"}}}"#.utf8)))
		#expect(minimal.subdivisionSegment(countryCode: "US", name: "texas") == "TX")
		#expect(minimal.entries.isEmpty)
	}

	@Test func entryPlacesBySubdivisionOrRadius() {
		let entry = MqttRootDirectory.Entry(root: "msh/US/DMV", name: "DMV", subdivisions: ["US-VA"], center: [39.168, -76.897], radiusKm: 55)
		#expect(entry.serves(subdivision: "US-VA", at: nil))
		#expect(!entry.serves(subdivision: "US-TX", at: nil))
		#expect(entry.serves(subdivision: nil, at: CLLocationCoordinate2D(latitude: 38.9, longitude: -77.03)))
		#expect(!entry.serves(subdivision: nil, at: CLLocationCoordinate2D(latitude: 40.7, longitude: -74.0)))
		let badCenter = MqttRootDirectory.Entry(root: "msh/US/X", name: "X", center: [39.0], radiusKm: 5000)
		#expect(!badCenter.serves(subdivision: nil, at: CLLocationCoordinate2D(latitude: 39, longitude: -77)))
	}

	// MARK: Ladder

	@Test func subdivisionNameMapsThroughTheDirectory() {
		#expect(plan(country: "US", state: "Washington").rungs.map(\.topic) == ["msh/US", "msh/US/WA"])
		#expect(plan(country: "US", state: "WA").rungs.map(\.topic) == ["msh/US", "msh/US/WA"])
		#expect(plan(country: "US", state: "Washington").rungs.last?.placeName == "Washington")
	}

	@Test func neverOffersTheRegionTwice() {
		let heard = ["msh/US/US/MI": activity(packets: 4), "msh/US/US": activity(packets: 2)]
		let rungs = plan(country: "US", state: "Michigan", activity: heard).rungs
		#expect(rungs.map(\.topic) == ["msh/US", "msh/US/MI"])
	}

	@Test func countryLevelFollowsTheBroker() {
		let directory = MqttRootDirectory.empty
		// Nothing heard under DE: the state follows the region.
		#expect(plan("msh/EU_868", country: "DE", state: "Bayern", directory: directory).rungs.map(\.topic)
			== ["msh/EU_868", "msh/EU_868/Bayern"])
		// Roots under DE are in use and DE itself is quiet: offered before the state, which it prefixes.
		let inUse = ["msh/EU_868/DE/S-H": activity(packets: 12), "msh/EU_868/DE": activity(packets: 20)]
		let rungs = plan("msh/EU_868", country: "DE", state: "Bayern", city: "München", directory: directory, activity: inUse).rungs
		#expect(rungs.map(\.topic) == ["msh/EU_868", "msh/EU_868/DE", "msh/EU_868/DE/Bayern", "msh/EU_868/DE/Bayern/münchen"])
		#expect(rungs.map(\.level) == [.region, .country, .state, .city])
		// Another country's roots say nothing about DE.
		#expect(plan("msh/EU_868", country: "DE", state: "Bayern", directory: directory, activity: ["msh/EU_868/SE/AB": activity(packets: 3)])
			.rungs.map(\.topic) == ["msh/EU_868", "msh/EU_868/Bayern"])
	}

	@Test func floodedCountryPrefixesButIsNotOffered() {
		let flooded = ["msh/EU_868/DE": activity(packets: MqttTopicSampler.regionPacketCap)]
		let rungs = plan("msh/EU_868", country: "DE", state: "Bayern", directory: .empty, activity: flooded).rungs
		#expect(rungs.map(\.topic) == ["msh/EU_868", "msh/EU_868/DE/Bayern"])
	}

	@Test func communityRootsAppearUnheard() {
		let directory = MqttRootDirectory(
			entries: [
				MqttRootDirectory.Entry(root: "msh/US/DMV", name: "DMV", subdivisions: ["US-DC", "US-MD", "US-VA"]),
				MqttRootDirectory.Entry(root: "msh/US/MeshSTL", name: "St. Louis", center: [38.627, -90.199], radiusKm: 80),
				MqttRootDirectory.Entry(root: "msh/US/va", name: "Duplicate of the state rung", subdivisions: ["US-VA"])
			],
			subdivisionSegments: ["US": ["virginia": "VA", "missouri": "MO", "illinois": "IL"]])
		let virginia = plan(country: "US", state: "Virginia", directory: directory).rungs
		#expect(virginia.map(\.topic) == ["msh/US", "msh/US/VA", "msh/US/DMV"])
		#expect(virginia.last?.level == .community)
		#expect(virginia.last?.placeName == "DMV")
		// Across the river in Illinois, inside the radius.
		let eastStLouis = CLLocationCoordinate2D(latitude: 38.62, longitude: -90.15)
		#expect(plan(country: "US", state: "Illinois", at: eastStLouis, directory: directory).rungs.map(\.topic)
			== ["msh/US", "msh/US/IL", "msh/US/MeshSTL"])
	}

	@Test func communityRootsByRadiusNeedNoPlaceName() {
		let directory = MqttRootDirectory(
			entries: [MqttRootDirectory.Entry(root: "msh/US/MeshSTL", name: "St. Louis", center: [38.627, -90.199], radiusKm: 80)],
			subdivisionSegments: ["US": ["missouri": "MO"]])
		// The geocoder failed or hasn't answered yet: no place, but the coordinate is known.
		let rungs = Discovery.plan(
			regionTopic: "msh/US",
			regionName: "US",
			place: nil,
			at: CLLocationCoordinate2D(latitude: 38.62, longitude: -90.15),
			directory: directory
		).rungs
		#expect(rungs.map(\.topic) == ["msh/US", "msh/US/MeshSTL"])
	}

	// MARK: Ranking

	@Test func neighboringStateRanksAboveUnrelatedRoots() {
		let heard = [
			"msh/US/FL": activity(packets: 40, nodes: 9),
			"msh/US/AR": activity(packets: 3, nodes: 2),
			"msh/US/TX/dfw": activity(packets: 2, nodes: 1)
		]
		let topics = plan(country: "US", state: "Texas", city: "Texarkana", activity: heard)
		#expect(topics.neighborRoots.contains("msh/US/AR"))
		let ranked = Discovery.ranked(heard, plan: topics, from: nil)
		#expect(ranked.map(\.root) == ["msh/US/TX/dfw", "msh/US/AR", "msh/US/FL"])
		#expect(ranked.map(\.tier) == [.ownArea, .nearby, .elsewhere])
	}

	@Test func communityRootsRankInTheMiddleTier() {
		let directory = MqttRootDirectory(
			entries: [MqttRootDirectory.Entry(root: "msh/US/DMV", name: "DMV", subdivisions: ["US-VA"])],
			subdivisionSegments: ["US": ["virginia": "VA"]])
		let heard = [
			"msh/US/DMV": activity(packets: 5),
			"msh/US/DMV/annapolis": activity(packets: 2),
			"msh/US/CA": activity(packets: 50, nodes: 20)
		]
		let topics = plan(country: "US", state: "Virginia", directory: directory, activity: heard)
		let ranked = Discovery.ranked(heard, plan: topics, from: nil)
		// The DMV root itself is on its own row above.
		#expect(ranked.map(\.root) == ["msh/US/DMV/annapolis", "msh/US/CA"])
		#expect(ranked.map(\.tier) == [.nearby, .elsewhere])
	}

	@Test func countryIsOwnAreaWhenNothingFinerIsKnown() {
		let heard = ["msh/EU_868/DE/S-H": activity(packets: 4), "msh/EU_868/SE/AB": activity(packets: 9, nodes: 5)]
		let topics = plan("msh/EU_868", country: "DE", state: nil, directory: .empty, activity: heard)
		#expect(topics.rungs.map(\.level) == [.region, .country])
		#expect(Discovery.ranked(heard, plan: topics, from: nil).map(\.tier) == [.ownArea, .elsewhere])
	}
}
