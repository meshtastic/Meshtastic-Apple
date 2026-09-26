//
//  SettingsSearchEngineTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 9/13/26.
//
import Testing
@testable import Meshtastic

@Suite("Settings search ranking and matching")
struct SettingsSearchEngineTests {

	private func entry(
		_ label: String,
		destination: SettingsNavigationState = .lora,
		section: SettingsListSection = .radioConfiguration,
		subtitle: String? = nil,
		keywords: [String] = []
	) -> SettingsSearchEntry {
		SettingsSearchEntry(
			destination: destination, screenTitle: "LoRa", listSection: section,
			label: label, subtitle: subtitle, keywords: keywords, requiresConnection: false)
	}

	private let connected = SettingsSearchEngine.Availability(
		isConnected: true, isDIYHardware: false, isManaged: false)

	@Test("A match in the label outranks a keyword or description hit")
	func fieldWeighting() throws {
		let index = [
			entry("Number of hops"),
			entry("Rebroadcast Mode", keywords: ["hops"]),
			entry("Channel", subtitle: "Controls how many hops a packet takes.")
		]
		let results = SettingsSearchEngine.search("hops", in: index, availability: connected)
		#expect(results.count == 3)
		#expect(results[0].entry.label == "Number of hops")
		#expect(results[1].entry.label == "Rebroadcast Mode")
		#expect(results[2].entry.label == "Channel")
	}

	@Test("An exact label beats a prefix, which beats a substring")
	func labelPrecision() throws {
		let index = [entry("Region Code"), entry("Region"), entry("Set Region Here")]
		let results = SettingsSearchEngine.search("Region", in: index, availability: connected)
		#expect(results.map(\.entry.label) == ["Region", "Region Code", "Set Region Here"])
	}

	@Test("Equal scores order by section, then label, so the list never reshuffles")
	func deterministicTiebreak() throws {
		// Same match kind on every entry, so only the tiebreak decides.
		let index = [
			entry("Zulu", destination: .mqtt, section: .configure),
			entry("Alpha", destination: .device, section: .deviceConfiguration),
			entry("Alpha", destination: .lora, section: .radioConfiguration),
			entry("Beta", destination: .lora, section: .radioConfiguration)
		]
		let first = SettingsSearchEngine.search("a", in: index, availability: connected)
		let second = SettingsSearchEngine.search("a", in: index.reversed(), availability: connected)
		#expect(first.map(\.id) == second.map(\.id), "order must not depend on index order")
	}

	@Test("Matching ignores case and diacritics")
	func diacriticInsensitive() throws {
		let index = [entry("Réseau")]
		#expect(!SettingsSearchEngine.search("reseau", in: index, availability: connected).isEmpty)
		#expect(!SettingsSearchEngine.search("RÉSEAU", in: index, availability: connected).isEmpty)
	}

	@Test("A one-character query returns nothing rather than everything")
	func minimumQueryLength() throws {
		let index = [entry("Region"), entry("Rebroadcast")]
		#expect(SettingsSearchEngine.search("r", in: index, availability: connected).isEmpty)
		#expect(SettingsSearchEngine.search("  ", in: index, availability: connected).isEmpty)
		#expect(!SettingsSearchEngine.search("re", in: index, availability: connected).isEmpty)
	}

	@Test("Radio settings stay visible while disconnected, marked as needing a radio")
	func disconnectedIsDimmedNotHidden() throws {
		let radio = SettingsSearchEntry(
			destination: .lora, screenTitle: "LoRa", listSection: .radioConfiguration,
			label: "Number of hops", requiresConnection: true)
		let results = SettingsSearchEngine.search(
			"hops", in: [radio], availability: .disconnected)
		#expect(results.count == 1, "a disconnected radio setting is dimmed, never hidden")
		guard case .deEmphasised = results[0].visibility else {
			Issue.record("expected the result to be de-emphasised, got \(results[0].visibility)")
			return
		}
	}

	@Test("Keywords are split on the pipe the schema uses, not on commas")
	func keywordSplitting() throws {
		#expect(SettingsSearchIndex.keywords(from: "hops|ttl| range ") == ["hops", "ttl", "range"])
		#expect(SettingsSearchIndex.keywords(from: "one, two|three") == ["one, two", "three"])
		#expect(SettingsSearchIndex.keywords(from: nil).isEmpty)
		#expect(SettingsSearchIndex.keywords(from: "").isEmpty)
	}

	@Test("The query corpus reaches the control a user would be looking for")
	func queryCorpus() throws {
		// SC-002: findability is measured by terms a user would plausibly type, not
		// by requiring every entry to carry a keyword. Grow this whenever a search
		// that should have worked did not.
		let corpus: [(query: String, expectedLabel: String)] = [
			("hops", "Hop Limit"),
			("psk", "Channels"),
			("transmit power", "Transmit Power"),
			("region", "Region")
		]
		for (query, expected) in corpus {
			let results = SettingsSearchEngine.search(
				query, in: SettingsSearchIndex.entries, availability: connected)
			#expect(
				results.prefix(5).contains { $0.entry.label == expected },
				"\"\(query)\" should surface \"\(expected)\"; got \(results.prefix(5).map(\.entry.label))"
			)
		}
	}
}

@Suite("Documentation search")
struct DocumentationSearchTests {

	@MainActor
	@Test("The bundled documentation index loads")
	func indexLoads() throws {
		// Generated by build-docs.sh from the pages themselves, so an empty index
		// means the bundle is missing rather than that there is nothing to find.
		#expect(!DocumentationSearch.pages.isEmpty, "docs/index.json did not load")
	}

	@MainActor
	@Test("A title match outranks a keyword match, and ties order by title")
	func ranking() throws {
		// Require the fixture rather than skipping when it is absent: a guard that
		// returns success here would also pass if documentation loading broke
		// entirely, which is the failure most worth catching.
		let titled = DocumentationSearch.pages.filter { $0.title.localizedStandardContains("mqtt") }
		try #require(!titled.isEmpty, "the bundled docs have no MQTT page to rank")

		let results = DocumentationSearch.search("mqtt")
		#expect(
			results[0].title.localizedStandardContains("mqtt"),
			"a page whose title matches should come first, got \(results[0].title)")
	}

	@MainActor
	@Test("Short queries return nothing, matching the settings side")
	func minimumQueryLength() throws {
		#expect(DocumentationSearch.search("m").isEmpty)
		#expect(DocumentationSearch.search(" ").isEmpty)
	}

	@MainActor
	@Test("Result order does not depend on the order pages were read")
	func deterministic() throws {
		// Calling twice with the same input only proves the function is not random.
		// Ties break by title, so a reversed input must produce the same order.
		let forward = DocumentationSearch.search("radio")
		try #require(forward.count > 1, "need at least two matches to test ordering")
		let reversed = DocumentationSearch.rank("radio", in: DocumentationSearch.pages.reversed())
		#expect(forward.map(\.id) == reversed.map(\.id))
	}
}

@Suite("DIY hardware lookup")
struct DIYHardwareTests {

	@Test("A missing catalogue never hides anything")
	func unknownCatalogueIsNotNotDIY() throws {
		// "We do not know" and "not DIY" must not give the same answer: the engine hides
		// DIY-only settings when this is false, so unknown has to read as true.
		#expect(DIYHardware.isDIY(slug: "HELTEC_V3", in: nil))
		#expect(DIYHardware.isDIY(slug: nil, in: nil))
	}

	@Test("A known catalogue answers by tag, and an absent slug is not DIY")
	func knownCatalogue() throws {
		let catalogue: Set<String> = ["DIY_V1", "RAK4631"]
		#expect(DIYHardware.isDIY(slug: "diy_v1", in: catalogue), "lookup is case-insensitive")
		#expect(!DIYHardware.isDIY(slug: "HELTEC_V3", in: catalogue))
		#expect(!DIYHardware.isDIY(slug: nil, in: catalogue))
		#expect(!DIYHardware.isDIY(slug: "", in: catalogue))
	}
}
