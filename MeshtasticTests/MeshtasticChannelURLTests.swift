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

	@Test func acceptsAndroidCompatibleWWWChannelURL() throws {
		let payload = try MeshtasticChannelURL.payloadString(for: makeChannelSet())
		let parsed = try MeshtasticChannelURL.parse("https://www.meshtastic.org/e/?add=true#\(payload)")

		#expect(parsed.addChannels)
		#expect(parsed.channelSet.settings.first?.name == "Alpha")
		#expect(!parsed.channelSet.hasLoraConfig)
	}

	@Test func decodesAndroidChannelReplaceAndAddVectors() throws {
		let replace = try MeshtasticChannelURL.parse("https://meshtastic.org/e/#CgMSAQESBggBQANIAQ")
		let add = try MeshtasticChannelURL.parse("https://meshtastic.org/e/?add=true#CgMSAQESBggBQANIAQ")

		#expect(replace.channelSet.settings.count == 1)
		#expect(replace.channelSet.hasLoraConfig)
		#expect(add.channelSet.settings.count == 1)
		#expect(add.addChannels)
		#expect(!add.channelSet.hasLoraConfig)
	}

	@Test(arguments: 1 ... 8)
	func allSupportedChannelCountsPreserveSettingsForReplaceAndAdd(channelCount: Int) throws {
		let channelSet = makeChannelSet(channelCount: channelCount)
		let replace = try MeshtasticChannelURL.parse(MeshtasticChannelURL.urlString(for: channelSet))
		let add = try MeshtasticChannelURL.parse(MeshtasticChannelURL.urlString(for: channelSet, addChannels: true))

		#expect(replace.channelSet.settings == channelSet.settings, "\(channelCount)-channel replace settings")
		#expect(replace.channelSet.loraConfig == channelSet.loraConfig, "\(channelCount)-channel replace LoRa config")
		#expect(add.channelSet.settings == channelSet.settings, "\(channelCount)-channel add settings")
		#expect(!add.channelSet.hasLoraConfig, "\(channelCount)-channel add must not retune")
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

	private func makeChannelSet(channelCount: Int = 1) -> ChannelSet {
		var lora = Config.LoRaConfig()
		lora.hopLimit = 5
		lora.modemPreset = .longFast
		lora.region = .us
		lora.channelNum = 13
		lora.txPower = 20
		lora.usePreset = true

		var channelSet = ChannelSet()
		channelSet.loraConfig = lora
		channelSet.settings = (0 ..< channelCount).map { index in
			var settings = ChannelSettings()
			settings.name = index == 0 ? "Alpha" : "Conference-\(index)"
			settings.psk = Data([UInt8(index), UInt8(index + 16)])
			settings.id = UInt32(index + 1)
			settings.moduleSettings.positionPrecision = UInt32(index)
			return settings
		}
		return channelSet
	}
}
