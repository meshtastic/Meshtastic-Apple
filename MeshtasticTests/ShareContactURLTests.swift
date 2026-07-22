import Foundation
import MeshtasticProtobufs
import Testing

@testable import Meshtastic

// Note: named ShareContactURLTests because EntityTests.swift already declares
// a ShareContactQRTests suite in this module.
@Suite("Share contact URLs")
struct ShareContactURLTests {

	// The contact URL written to QR codes and NFC tags must encode the
	// manually_verified bit exactly as passed — never forced true or false.
	@Test(arguments: [true, false])
	func urlPreservesManuallyVerifiedBit(_ manuallyVerified: Bool) throws {
		let node = makeNodeInfo()
		let urlString = try #require(ShareContactQR.urlString(for: node, manuallyVerified: manuallyVerified))
		#expect(urlString.hasPrefix(ShareContactQR.urlPrefix))

		let payload = try #require(urlString.components(separatedBy: "#").last)
		let decodedData = try #require(Data(base64Encoded: payload.base64urlToBase64()))
		let contact = try SharedContact(serializedBytes: decodedData)

		#expect(contact.manuallyVerified == manuallyVerified)
		#expect(contact.nodeNum == node.num)
		#expect(contact.user.longName == "Bud")
		#expect(contact.user.publicKey == Data([9, 9, 9]))
	}

	@Test func unmessagableNodeIsNotShareable() {
		var node = makeNodeInfo()
		node.user.isUnmessagable = true
		#expect(ShareContactQR.urlString(for: node, manuallyVerified: false) == nil)
	}

	@Test(arguments: [
		"https://meshtastic.org/v/#Cg0aC0J1ZA",
		"https://www.meshtastic.org/v/#Cg0aC0J1ZA",
		"HTTPS://MESHTASTIC.ORG/V/#Cg0aC0J1ZA",
		"meshtastic://v#Cg0aC0J1ZA",
		"meshtastic:///v#Cg0aC0J1ZA"
	])
	func acceptsSupportedContactURLForms(_ value: String) throws {
		let url = try #require(URL(string: value))
		#expect(ContactURLHandler.canHandle(url))
	}

	// Guards against a foreign link merely embedding the contact prefix, which a
	// plain substring match would have routed into the import flow.
	@Test(arguments: [
		"https://example.com/?next=meshtastic.org/v/#Cg0aC0J1ZA",
		"https://meshtastic.org/e/#Cg0aC0J1ZA",
		"https://meshtastic.org/v/",
		"https://meshtastic.org/v/extra#Cg0aC0J1ZA",
		"https://notmeshtastic.org/v/#Cg0aC0J1ZA"
	])
	func rejectsNonContactURLs(_ value: String) throws {
		let url = try #require(URL(string: value))
		#expect(!ContactURLHandler.canHandle(url))
	}

	// A channel link with no payload passes MeshtasticChannelURL.canHandle (it only
	// checks host and path), so the NFC read path additionally requires a non-empty
	// fragment before reporting a successful scan.
	@Test(arguments: [
		"https://meshtastic.org/e/#",
		"https://meshtastic.org/e/",
		"https://meshtastic.org/v/#"
	])
	func payloadlessLinksHaveNoFragmentToImport(_ value: String) throws {
		let url = try #require(URL(string: value))
		let fragment = url.fragment ?? ""
		#expect(fragment.isEmpty)
		// The contact check rejects these outright; the channel check does not,
		// which is why the fragment guard exists in NFCReader.deliverFirstURL.
		#expect(!ContactURLHandler.canHandle(url))
	}

	// A payload that survives base64url decoding but is not a SharedContact must
	// be rejected, so the import sheet reports a failure instead of dismissing as
	// though it worked.
	@Test func undecodableContactPayloadIsRejected() {
		let notAContact = Data([0xFF, 0xFF, 0xFF, 0xFF]).base64EncodedString().base64ToBase64url()
		let decoded = Data(base64Encoded: notAContact.base64urlToBase64())
		#expect(decoded != nil)
		#expect(throws: (any Error).self) {
			_ = try SharedContact(serializedBytes: try #require(decoded))
		}
	}

	private func makeNodeInfo() -> NodeInfo {
		var user = User()
		user.id = "!1234"
		user.longName = "Bud"
		user.shortName = "Bud"
		user.publicKey = Data([9, 9, 9])

		var node = NodeInfo()
		node.num = 123456
		node.user = user
		return node
	}
}
