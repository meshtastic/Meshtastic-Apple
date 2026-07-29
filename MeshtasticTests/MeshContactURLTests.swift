import Foundation
import MeshtasticProtobufs
import Testing

@testable import Meshtastic

@Suite("Meshtastic contact URLs")
struct MeshContactURLTests {

	@Test func canonicalExchangeURLRoundTrips() throws {
		let contact = makeContact()

		let value = try MeshContactURL.urlString(for: contact, exchangeRequested: true)
		let parsed = try MeshContactURL.parse(value)

		#expect(parsed.exchangeRequested)
		#expect(parsed.contact.nodeNum == contact.nodeNum)
		#expect(parsed.contact.user.publicKey == contact.user.publicKey)
	}

	@Test func legacyURLRemainsSupported() throws {
		let value = try MeshContactURL.urlString(for: makeContact())

		#expect(try !MeshContactURL.parse(value).exchangeRequested)
	}

	@Test func acceptsWWWAndCustomSchemeForms() throws {
		let payload = try MeshContactURL.payloadString(for: makeContact())

		#expect(try MeshContactURL.parse("https://www.meshtastic.org/v/#\(payload)").contact.nodeNum == 0x01020304)
		#expect(try MeshContactURL.parse("meshtastic:///v#\(payload)").contact.nodeNum == 0x01020304)
		#expect(try MeshContactURL.parse("meshtastic://v#\(payload)").contact.nodeNum == 0x01020304)
	}

	@Test func rejectsWrongHost() {
		#expect(throws: MeshContactURL.ParseError.notContactURL) {
			_ = try MeshContactURL.parse("https://example.com/v/#abc")
		}
	}

	@Test func rejectsEmptyAndOversizedPayloads() throws {
		#expect(throws: MeshContactURL.ParseError.missingPayload) {
			_ = try MeshContactURL.parse("https://meshtastic.org/v/#")
		}
		#expect(throws: MeshContactURL.ParseError.payloadTooLarge) {
			_ = try MeshContactURL.parse(
				"https://meshtastic.org/v/#\(String(repeating: "a", count: MeshContactURL.maximumPayloadCharacters + 1))"
			)
		}
	}

	@Test func rejectsContactWithoutIdentity() throws {
		var contact = SharedContact()
		contact.manuallyVerified = true
		let payload = try MeshContactURL.payloadString(for: contact)

		#expect(throws: MeshContactURL.ParseError.invalidContact) {
			_ = try MeshContactURL.parse("https://meshtastic.org/v/#\(payload)")
		}
	}

	private func makeContact() -> SharedContact {
		var user = User()
		user.id = "!01020304"
		user.longName = "Chirpy"
		user.shortName = "CHRP"
		user.publicKey = Data(repeating: 7, count: 32)

		var contact = SharedContact()
		contact.nodeNum = 0x01020304
		contact.user = user
		contact.manuallyVerified = false
		return contact
	}
}
