// CoTMessageDetailedTests.swift
// MeshtasticTests

import Testing
import Foundation
import MeshtasticProtobufs
@testable import Meshtastic

// MARK: - CoTMessage Init Tests

@Suite("CoTMessage Initialization")
struct CoTMessageInitTests {

	@Test func defaultInit() {
		let msg = CoTMessage(uid: "test-uid", type: "a-f-G-U-C")
		#expect(msg.uid == "test-uid")
		#expect(msg.type == "a-f-G-U-C")
		#expect(msg.how == "m-g")
		#expect(msg.latitude == 0)
		#expect(msg.longitude == 0)
		#expect(msg.hae == 9999999.0)
		#expect(msg.ce == 9999999.0)
		#expect(msg.le == 9999999.0)
		#expect(msg.contact == nil)
		#expect(msg.group == nil)
		#expect(msg.status == nil)
		#expect(msg.track == nil)
		#expect(msg.chat == nil)
		#expect(msg.remarks == nil)
	}

	@Test func fullInit() {
		let msg = CoTMessage(
			uid: "uid-1",
			type: "a-f-G",
			latitude: 37.0,
			longitude: -122.0,
			hae: 100.0,
			contact: CoTContact(callsign: "Alpha"),
			group: CoTGroup(name: "Cyan", role: "Team Member"),
			status: CoTStatus(battery: 85),
			track: CoTTrack(speed: 5.0, course: 90.0),
			remarks: "Test remark"
		)
		#expect(msg.latitude == 37.0)
		#expect(msg.longitude == -122.0)
		#expect(msg.hae == 100.0)
		#expect(msg.contact?.callsign == "Alpha")
		#expect(msg.group?.name == "Cyan")
		#expect(msg.status?.battery == 85)
		#expect(msg.track?.speed == 5.0)
		#expect(msg.remarks == "Test remark")
	}
}

// MARK: - CoTMessage Factory Tests

@Suite("CoTMessage Factory Methods")
struct CoTMessageFactoryTests {

	@Test func pli_basic() {
		let msg = CoTMessage.pli(
			uid: "ANDROID-test",
			callsign: "TestUser",
			latitude: 37.7749,
			longitude: -122.4194
		)
		#expect(msg.type == "a-f-G-U-C")
		#expect(msg.how == "m-g")
		#expect(msg.latitude == 37.7749)
		#expect(msg.longitude == -122.4194)
		#expect(msg.contact?.callsign == "TestUser")
		#expect(msg.group?.name == "Cyan")
		#expect(msg.group?.role == "Team Member")
		#expect(msg.status?.battery == 100)
	}

	@Test func pli_withCustomParams() {
		let msg = CoTMessage.pli(
			uid: "DEV-001",
			callsign: "Alpha1",
			latitude: 40.0,
			longitude: -74.0,
			altitude: 500.0,
			speed: 10.0,
			course: 180.0,
			team: "Red",
			role: "Team Lead",
			battery: 50,
			staleMinutes: 5,
			remarks: "Moving south"
		)
		#expect(msg.hae == 500.0)
		#expect(msg.track?.speed == 10.0)
		#expect(msg.track?.course == 180.0)
		#expect(msg.group?.name == "Red")
		#expect(msg.group?.role == "Team Lead")
		#expect(msg.status?.battery == 50)
		#expect(msg.remarks == "Moving south")
	}

	@Test func chat_basic() {
		let msg = CoTMessage.chat(
			senderUid: "ANDROID-sender",
			senderCallsign: "Sender1",
			message: "Hello World"
		)
		#expect(msg.type == "b-t-f")
		#expect(msg.how == "h-g-i-g-o")
		#expect(msg.uid.hasPrefix("GeoChat.ANDROID-sender.All Chat Rooms."))
		#expect(msg.chat?.message == "Hello World")
		#expect(msg.chat?.senderCallsign == "Sender1")
		#expect(msg.chat?.chatroom == "All Chat Rooms")
		#expect(msg.remarks == "Hello World")
	}

	@Test func chat_directMessage() {
		let msg = CoTMessage.chat(
			senderUid: "DEV-A",
			senderCallsign: "UserA",
			message: "Private message",
			chatroom: "UserB"
		)
		#expect(msg.uid.contains("UserB"))
		#expect(msg.chat?.chatroom == "UserB")
	}
}

// MARK: - CoTMessage.toXML Tests

@Suite("CoTMessage XML Generation")
struct CoTMessageToXMLTests {

	@Test func basicPLI_containsRequiredElements() {
		let msg = CoTMessage.pli(
			uid: "test-uid",
			callsign: "Test",
			latitude: 37.0,
			longitude: -122.0
		)
		let xml = msg.toXML()
		#expect(xml.contains("<?xml version="))
		#expect(xml.contains("<event"))
		#expect(xml.contains("uid='test-uid'"))
		#expect(xml.contains("type='a-f-G-U-C'"))
		#expect(xml.contains("<point"))
		#expect(xml.contains("lat='37.0'"))
		#expect(xml.contains("lon='-122.0'"))
		#expect(xml.contains("<detail>"))
		#expect(xml.contains("</detail></event>"))
	}

	@Test func contactElement() {
		let msg = CoTMessage(
			uid: "uid-1",
			type: "a-f-G",
			contact: CoTContact(callsign: "Alpha", endpoint: "1.2.3.4:4242:tcp")
		)
		let xml = msg.toXML()
		#expect(xml.contains("<contact"))
		#expect(xml.contains("callsign='Alpha'"))
		#expect(xml.contains("endpoint='1.2.3.4:4242:tcp'"))
	}

	@Test func groupElement() {
		let msg = CoTMessage(
			uid: "uid-1",
			type: "a-f-G",
			group: CoTGroup(name: "Red", role: "Team Lead")
		)
		let xml = msg.toXML()
		#expect(xml.contains("<__group"))
		#expect(xml.contains("name='Red'"))
		#expect(xml.contains("role='Team Lead'"))
	}

	@Test func statusElement() {
		let msg = CoTMessage(
			uid: "uid-1",
			type: "a-f-G",
			status: CoTStatus(battery: 75)
		)
		let xml = msg.toXML()
		#expect(xml.contains("<status battery='75'/>"))
	}

	@Test func trackElement() {
		let msg = CoTMessage(
			uid: "uid-1",
			type: "a-f-G",
			track: CoTTrack(speed: 5.0, course: 90.0)
		)
		let xml = msg.toXML()
		#expect(xml.contains("<track"))
		#expect(xml.contains("speed='5.0'"))
		#expect(xml.contains("course='90.0'"))
	}

	@Test func xmlEscaping() {
		let msg = CoTMessage(
			uid: "uid&<>\"'",
			type: "a-f-G",
			contact: CoTContact(callsign: "Test & <User>")
		)
		let xml = msg.toXML()
		#expect(xml.contains("uid='uid&amp;&lt;&gt;&quot;&apos;'"))
		#expect(xml.contains("callsign='Test &amp; &lt;User&gt;'"))
	}

	@Test func chatMessage_containsChatElements() {
		let msg = CoTMessage.chat(
			senderUid: "SENDER",
			senderCallsign: "SenderName",
			message: "Hello"
		)
		let xml = msg.toXML()
		#expect(xml.contains("<__chat"))
		#expect(xml.contains("chatroom='All Chat Rooms'"))
		#expect(xml.contains("senderCallsign='SenderName'"))
		#expect(xml.contains("</__chat>"))
		#expect(xml.contains("<remarks"))
		#expect(xml.contains("Hello"))
	}

	@Test func remarks_withoutChat() {
		let msg = CoTMessage(
			uid: "uid-1",
			type: "a-f-G",
			remarks: "Just a note"
		)
		let xml = msg.toXML()
		#expect(xml.contains("<remarks>Just a note</remarks>"))
	}

	@Test func rawDetailXML_included() {
		let msg = CoTMessage(
			uid: "uid-1",
			type: "a-f-G",
			rawDetailXML: "<color argb=\"-1\"/>"
		)
		let xml = msg.toXML()
		#expect(xml.contains("<color argb=\"-1\"/>"))
	}
}

// MARK: - CoTMessage.fromTAKPacket Tests

@Suite("CoTMessage fromTAKPacket")
struct CoTMessageFromTAKPacketTests {

	@Test func pliPacket() {
		var packet = TAKPacket()
		var pli = PLI()
		pli.latitudeI = 377749000
		pli.longitudeI = -1224194000
		pli.altitude = 100
		pli.speed = 5
		pli.course = 90
		packet.pli = pli

		var contact = Contact()
		contact.callsign = "TestUser"
		contact.deviceCallsign = "ANDROID-123"
		packet.contact = contact

		var group = Group()
		group.team = .cyan
		group.role = .teamMember
		packet.group = group

		var status = Status()
		status.battery = 80
		packet.status = status

		let msg = CoTMessage.fromTAKPacket(packet)
		#expect(msg != nil)
		#expect(msg!.type == "a-f-G-U-C")
		#expect(msg!.uid == "ANDROID-123")
		#expect(abs(msg!.latitude - 37.7749) < 0.001)
		#expect(abs(msg!.longitude - (-122.4194)) < 0.001)
		#expect(msg!.hae == 100.0)
		#expect(msg!.contact?.callsign == "TestUser")
		#expect(msg!.track?.speed == 5.0)
	}

	@Test func pliPacket_zeroCoords_returnsNil() {
		var packet = TAKPacket()
		var pli = PLI()
		pli.latitudeI = 0
		pli.longitudeI = 0
		packet.pli = pli

		var contact = Contact()
		contact.callsign = "Test"
		contact.deviceCallsign = "DEV"
		packet.contact = contact

		let msg = CoTMessage.fromTAKPacket(packet)
		#expect(msg == nil)
	}

	@Test func chatPacket() {
		var packet = TAKPacket()
		var geoChat = GeoChat()
		geoChat.message = "Hello"
		geoChat.to = "All Chat Rooms"
		packet.chat = geoChat

		var contact = Contact()
		contact.callsign = "Sender"
		contact.deviceCallsign = "DEV-001|msg-123"
		packet.contact = contact

		let msg = CoTMessage.fromTAKPacket(packet)
		#expect(msg != nil)
		#expect(msg!.type == "b-t-f")
		#expect(msg!.chat?.message == "Hello")
		#expect(msg!.uid.contains("GeoChat"))
		#expect(msg!.uid.contains("DEV-001"))
		#expect(msg!.uid.contains("msg-123"))
	}

	@Test func unknownPayload_returnsNil() {
		let packet = TAKPacket()
		let msg = CoTMessage.fromTAKPacket(packet)
		#expect(msg == nil)
	}

	@Test func deviceUid_fallback() {
		var packet = TAKPacket()
		var pli = PLI()
		pli.latitudeI = 100000000
		pli.longitudeI = 200000000
		packet.pli = pli

		var contact = Contact()
		contact.callsign = "Test"
		contact.deviceCallsign = ""
		packet.contact = contact

		let msg = CoTMessage.fromTAKPacket(packet, deviceUid: "fallback-uid")
		#expect(msg != nil)
		#expect(msg!.uid == "fallback-uid")
	}
}

// MARK: - CoTContact Tests

@Suite("CoTContact Detailed")
struct CoTContactDetailedTests {

	@Test func equatable() {
		let a = CoTContact(callsign: "Alpha")
		let b = CoTContact(callsign: "Alpha")
		let c = CoTContact(callsign: "Beta")
		#expect(a == b)
		#expect(a != c)
	}

	@Test func withEndpoint() {
		let contact = CoTContact(callsign: "Test", endpoint: "1.2.3.4:4242:tcp")
		#expect(contact.endpoint == "1.2.3.4:4242:tcp")
	}
}

// MARK: - CoTGroup Tests

@Suite("CoTGroup Detailed")
struct CoTGroupDetailedTests {

	@Test func equatable() {
		let a = CoTGroup(name: "Cyan", role: "Team Member")
		let b = CoTGroup(name: "Cyan", role: "Team Member")
		let c = CoTGroup(name: "Red", role: "Team Lead")
		#expect(a == b)
		#expect(a != c)
	}
}

// MARK: - CoTChat Tests

@Suite("CoTChatStruct")
struct CoTChatStructTests {

	@Test func defaults() {
		let chat = CoTChat(message: "Hello")
		#expect(chat.chatroom == "All Chat Rooms")
		#expect(chat.senderCallsign == nil)
	}

	@Test func equatable() {
		let a = CoTChat(message: "Hi", chatroom: "Room1")
		let b = CoTChat(message: "Hi", chatroom: "Room1")
		#expect(a == b)
	}
}

// MARK: - XML Escaping Tests

@Suite("XML Escaping Detailed")
struct XMLEscapingDetailedTests {

	@Test func ampersand() {
		#expect("A&B".xmlEscaped == "A&amp;B")
	}

	@Test func lessThan() {
		#expect("A<B".xmlEscaped == "A&lt;B")
	}

	@Test func greaterThan() {
		#expect("A>B".xmlEscaped == "A&gt;B")
	}

	@Test func doubleQuote() {
		#expect("A\"B".xmlEscaped == "A&quot;B")
	}

	@Test func singleQuote() {
		#expect("A'B".xmlEscaped == "A&apos;B")
	}

	@Test func multipleSpecialChars() {
		#expect("<&>".xmlEscaped == "&lt;&amp;&gt;")
	}

	@Test func noSpecialChars() {
		#expect("Hello World".xmlEscaped == "Hello World")
	}

	@Test func emptyString() {
		#expect("".xmlEscaped == "")
	}
}

// MARK: - Team Extension Tests

@Suite("Team Extension")
struct TeamExtensionTests {

	@Test func cotColorName_knownValues() {
		#expect(Team.cyan.cotColorName == "Cyan")
		#expect(Team.red.cotColorName == "Red")
		#expect(Team.green.cotColorName == "Green")
		#expect(Team.blue.cotColorName == "Blue")
		#expect(Team.white.cotColorName == "White")
	}

	@Test func fromColorName_knownValues() {
		#expect(Team.fromColorName("Cyan") == .cyan)
		#expect(Team.fromColorName("Red") == .red)
		#expect(Team.fromColorName("cyan") == .cyan)
		#expect(Team.fromColorName("CYAN") == .cyan)
	}

	@Test func fromColorName_unknown_defaultsCyan() {
		#expect(Team.fromColorName("Unknown") == .cyan)
		#expect(Team.fromColorName("") == .cyan)
	}

	@Test func fromColorName_darkBlue() {
		#expect(Team.fromColorName("Dark Blue") == .darkBlue)
		#expect(Team.fromColorName("darkblue") == .darkBlue)
	}
}

// MARK: - MemberRole Extension Tests

@Suite("MemberRole Extension")
struct MemberRoleExtensionTests {

	@Test func cotRoleName_knownValues() {
		#expect(MemberRole.teamMember.cotRoleName == "Team Member")
		#expect(MemberRole.teamLead.cotRoleName == "Team Lead")
		#expect(MemberRole.hq.cotRoleName == "HQ")
		#expect(MemberRole.sniper.cotRoleName == "Sniper")
		#expect(MemberRole.medic.cotRoleName == "Medic")
	}

	@Test func fromRoleName_knownValues() {
		#expect(MemberRole.fromRoleName("Team Member") == .teamMember)
		#expect(MemberRole.fromRoleName("team member") == .teamMember)
		#expect(MemberRole.fromRoleName("Team Lead") == .teamLead)
		#expect(MemberRole.fromRoleName("HQ") == .hq)
	}

	@Test func fromRoleName_unknown_defaultsTeamMember() {
		#expect(MemberRole.fromRoleName("Unknown") == .teamMember)
		#expect(MemberRole.fromRoleName("") == .teamMember)
	}
}
