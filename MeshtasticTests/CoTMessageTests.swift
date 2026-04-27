import Foundation
import Testing

@testable import Meshtastic

// MARK: - CoTMessage Initialization

@Suite("CoTMessage")
struct CoTMessageTests {

	@Test func init_setsAllProperties() {
		let msg = CoTMessage(uid: "test-uid", type: "a-f-G-U-C")
		#expect(msg.uid == "test-uid")
		#expect(msg.type == "a-f-G-U-C")
		#expect(msg.how == "m-g")
		#expect(msg.latitude == 0)
		#expect(msg.longitude == 0)
		#expect(msg.hae == 9999999.0)
	}

	@Test func init_customValues() {
		let msg = CoTMessage(
			uid: "custom",
			type: "b-t-f",
			how: "h-g-i-g-o",
			latitude: 37.7749,
			longitude: -122.4194,
			hae: 100.0,
			remarks: "Test remark"
		)
		#expect(msg.latitude == 37.7749)
		#expect(msg.longitude == -122.4194)
		#expect(msg.hae == 100.0)
		#expect(msg.remarks == "Test remark")
	}

	@Test func pli_createsCorrectType() {
		let msg = CoTMessage.pli(
			uid: "node-1",
			callsign: "TestUser",
			latitude: 37.0,
			longitude: -122.0
		)
		#expect(msg.type == "a-f-G-U-C")
		#expect(msg.how == "m-g")
		#expect(msg.latitude == 37.0)
		#expect(msg.longitude == -122.0)
		#expect(msg.contact?.callsign == "TestUser")
		#expect(msg.group != nil)
		#expect(msg.status?.battery == 100)
	}

	@Test func pli_customTeamAndRole() {
		let msg = CoTMessage.pli(
			uid: "node-2",
			callsign: "Leader",
			latitude: 0,
			longitude: 0,
			team: "Red",
			role: "Team Lead"
		)
		#expect(msg.group?.name == "Red")
		#expect(msg.group?.role == "Team Lead")
	}

	@Test func chat_createsCorrectType() {
		let msg = CoTMessage.chat(
			senderUid: "sender-1",
			senderCallsign: "Alice",
			message: "Hello World"
		)
		#expect(msg.type == "b-t-f")
		#expect(msg.how == "h-g-i-g-o")
		#expect(msg.remarks == "Hello World")
		#expect(msg.chat?.message == "Hello World")
		#expect(msg.uid.hasPrefix("GeoChat."))
	}

	@Test func chat_customChatroom() {
		let msg = CoTMessage.chat(
			senderUid: "s1",
			senderCallsign: "Bob",
			message: "Test",
			chatroom: "Team Alpha"
		)
		#expect(msg.uid.contains("Team Alpha"))
	}

	@Test func toXML_containsRequiredElements() {
		let msg = CoTMessage(
			uid: "xml-test",
			type: "a-f-G-U-C",
			latitude: 37.0,
			longitude: -122.0,
			contact: CoTContact(callsign: "TestCS")
		)
		let xml = msg.toXML()
		#expect(xml.contains("<?xml"))
		#expect(xml.contains("event"))
		#expect(xml.contains("uid='xml-test'"))
		#expect(xml.contains("type='a-f-G-U-C'"))
		#expect(xml.contains("<point"))
		#expect(xml.contains("lat='37.0'"))
		#expect(xml.contains("lon='-122.0'"))
	}

	@Test func toXML_includesContact() {
		let msg = CoTMessage(
			uid: "test",
			type: "a-f-G-U-C",
			contact: CoTContact(callsign: "MyCall", endpoint: "1.2.3.4:4242:tcp")
		)
		let xml = msg.toXML()
		#expect(xml.contains("callsign='MyCall'"))
		#expect(xml.contains("endpoint='1.2.3.4:4242:tcp'"))
	}

	@Test func toXML_includesGroup() {
		let msg = CoTMessage(
			uid: "test",
			type: "a-f-G-U-C",
			group: CoTGroup(name: "Blue", role: "Team Lead")
		)
		let xml = msg.toXML()
		#expect(xml.contains("__group"))
		#expect(xml.contains("name='Blue'"))
		#expect(xml.contains("role='Team Lead'"))
	}

	@Test func toXML_includesRemarks() {
		let msg = CoTMessage(
			uid: "test",
			type: "a-f-G-U-C",
			remarks: "Hello & Goodbye"
		)
		let xml = msg.toXML()
		#expect(xml.contains("<remarks>"))
	}

	@Test func identifiable_hasUniqueId() {
		let msg1 = CoTMessage(uid: "a", type: "t")
		let msg2 = CoTMessage(uid: "b", type: "t")
		#expect(msg1.id != msg2.id)
	}
}

// MARK: - CoTContact

@Suite("CoTContact")
struct CoTContactTests {

	@Test func init_setsCallsign() {
		let contact = CoTContact(callsign: "Alpha")
		#expect(contact.callsign == "Alpha")
	}
}

// MARK: - CoTGroup

@Suite("CoTGroup")
struct CoTGroupTests {

	@Test func init_setsNameAndRole() {
		let group = CoTGroup(name: "Cyan", role: "Team Member")
		#expect(group.name == "Cyan")
		#expect(group.role == "Team Member")
	}
}
