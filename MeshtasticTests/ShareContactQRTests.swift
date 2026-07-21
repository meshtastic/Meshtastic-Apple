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
