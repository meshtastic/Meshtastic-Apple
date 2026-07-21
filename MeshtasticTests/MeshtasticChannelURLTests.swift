import Foundation
import MeshtasticProtobufs
import Testing

@testable import Meshtastic

@Suite("Meshtastic channel URLs")
struct MeshtasticChannelURLTests {

	@Test func canonicalURLRoundTrips() throws {
		let channelSet = makeChannelSet()
		let url = try MeshtasticChannelURL.urlString(for: channelSet)
		let parsed = try MeshtasticChannelURL.parse(url)

		#expect(parsed.addChannels == false)
		#expect(parsed.channelSet.settings.first?.name == "Alpha")
		#expect(parsed.channelSet.hasLoraConfig)
		#expect(parsed.channelSet.loraConfig.hopLimit == 5)
	}

	// The channel URL written to NFC tags (ShareChannels -> NFCWriteButton) is the
	// same MeshtasticChannelURL.urlString(for:addChannels:) output, so it must
	// round-trip through parse in both replace and add modes.
	@Test func nfcWritePayloadRoundTripsInBothModes() throws {
		let channelSet = makeChannelSet()

		let replaceUrl = try MeshtasticChannelURL.urlString(for: channelSet, addChannels: false)
		let replaceParsed = try MeshtasticChannelURL.parse(replaceUrl)
		#expect(replaceParsed.addChannels == false)
		#expect(replaceParsed.channelSet.settings.first?.name == "Alpha")
		#expect(replaceParsed.channelSet.settings.first?.psk == Data([1, 2, 3, 4]))
		#expect(replaceParsed.channelSet.hasLoraConfig)

		let addUrl = try MeshtasticChannelURL.urlString(for: channelSet, addChannels: true)
		let addParsed = try MeshtasticChannelURL.parse(addUrl)
		#expect(addParsed.addChannels)
		#expect(addParsed.channelSet.settings.first?.name == "Alpha")
		#expect(addParsed.channelSet.settings.first?.psk == Data([1, 2, 3, 4]))
		#expect(!addParsed.channelSet.hasLoraConfig)
	}

	@Test(arguments: [
		"HTTPS://MESHTASTIC.ORG/E/#",
		"https://meshtastic.org/e#",
		"meshtastic:///e/#",
		"meshtastic://e/#"
	])
	func acceptsSupportedChannelURLForms(_ prefix: String) throws {
		let payload = try MeshtasticChannelURL.payloadString(for: makeChannelSet())
		let parsed = try MeshtasticChannelURL.parse(prefix + payload)

		#expect(parsed.channelSet.settings.first?.name == "Alpha")
		#expect(parsed.channelSet.hasLoraConfig)
	}

	@Test func queryAddClearsLoraConfig() throws {
		let payload = try MeshtasticChannelURL.payloadString(for: makeChannelSet())
		let parsed = try MeshtasticChannelURL.parse("https://meshtastic.org/e/?add=true#\(payload)")

		#expect(parsed.addChannels)
		#expect(parsed.channelSet.settings.first?.name == "Alpha")
		#expect(!parsed.channelSet.hasLoraConfig)
	}

	@Test func fragmentAddClearsLoraConfig() throws {
		let payload = try MeshtasticChannelURL.payloadString(for: makeChannelSet())
		let parsed = try MeshtasticChannelURL.parse("https://meshtastic.org/e/#\(payload)?add=true")

		#expect(parsed.addChannels)
		#expect(parsed.channelSet.settings.first?.name == "Alpha")
		#expect(!parsed.channelSet.hasLoraConfig)
	}

	@Test func rawPayloadUsesDefaultAddMode() throws {
		let payload = try MeshtasticChannelURL.payloadString(for: makeChannelSet())
		let parsed = try MeshtasticChannelURL.parse(payload, defaultAddChannels: true)

		#expect(parsed.addChannels)
		#expect(!parsed.channelSet.hasLoraConfig)
	}

	@Test func rejectsWrongHost() {
		#expect(throws: (any Error).self) {
			_ = try MeshtasticChannelURL.parse("https://example.com/e/#abc")
		}
	}

	@Test func rejectsContactURLPath() throws {
		let payload = try MeshtasticChannelURL.payloadString(for: makeChannelSet())

		#expect(!MeshtasticChannelURL.canHandle(try #require(URL(string: "https://meshtastic.org/v/#\(payload)"))))
		#expect(throws: MeshtasticChannelURL.ParseError.notChannelURL) {
			_ = try MeshtasticChannelURL.parse("https://meshtastic.org/v/#\(payload)")
		}
	}

	@Test func rejectsNestedChannelPath() throws {
		let payload = try MeshtasticChannelURL.payloadString(for: makeChannelSet())

		#expect(!MeshtasticChannelURL.canHandle(try #require(URL(string: "https://meshtastic.org/channel/e/#\(payload)"))))
		#expect(throws: MeshtasticChannelURL.ParseError.notChannelURL) {
			_ = try MeshtasticChannelURL.parse("https://meshtastic.org/channel/e/#\(payload)")
		}
	}

	@Test func rejectsNestedCustomSchemeChannelPath() throws {
		let payload = try MeshtasticChannelURL.payloadString(for: makeChannelSet())

		#expect(!MeshtasticChannelURL.canHandle(try #require(URL(string: "meshtastic://anything/e/#\(payload)"))))
		#expect(throws: MeshtasticChannelURL.ParseError.notChannelURL) {
			_ = try MeshtasticChannelURL.parse("meshtastic://anything/e/#\(payload)")
		}
	}

	private func makeChannelSet() -> ChannelSet {
		var lora = Config.LoRaConfig()
		lora.hopLimit = 5
		lora.modemPreset = .longFast

		var settings = ChannelSettings()
		settings.name = "Alpha"
		settings.psk = Data([1, 2, 3, 4])

		var channelSet = ChannelSet()
		channelSet.loraConfig = lora
		channelSet.settings = [settings]
		return channelSet
	}
}
