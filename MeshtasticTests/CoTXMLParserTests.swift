import Foundation
import Testing

@testable import Meshtastic

// MARK: - CoTXMLParser Full XML Parsing

@Suite("CoTXMLParser")
struct CoTXMLParserTests {

	@Test func parse_pliMessage() throws {
		let xml = """
		<?xml version='1.0' encoding='UTF-8' standalone='yes'?>
		<event version='2.0' uid='ANDROID-abc123' type='a-f-G-U-C' time='2025-01-01T12:00:00Z' start='2025-01-01T12:00:00Z' stale='2025-01-01T12:10:00Z' how='m-g'>
		<point lat='37.7749' lon='-122.4194' hae='100.0' ce='9999999.0' le='9999999.0'/>
		<detail>
		<contact callsign='TestUser' endpoint='0.0.0.0:4242:tcp'/>
		<__group name='Cyan' role='Team Member'/>
		<status battery='85'/>
		<track speed='5.0' course='180.0'/>
		</detail>
		</event>
		""".data(using: .utf8)!

		let msg = try CoTMessage.parseData(xml)
		#expect(msg.uid == "ANDROID-abc123")
		#expect(msg.type == "a-f-G-U-C")
		#expect(msg.how == "m-g")
		#expect(abs(msg.latitude - 37.7749) < 0.001)
		#expect(abs(msg.longitude - (-122.4194)) < 0.001)
		#expect(abs(msg.hae - 100.0) < 0.1)
		#expect(msg.contact?.callsign == "TestUser")
		#expect(msg.group?.name == "Cyan")
		#expect(msg.group?.role == "Team Member")
		#expect(msg.status?.battery == 85)
		#expect(msg.track?.speed == 5.0)
		#expect(msg.track?.course == 180.0)
	}

	@Test func parse_chatMessage() throws {
		let xml = """
		<?xml version='1.0' encoding='UTF-8' standalone='yes'?>
		<event version='2.0' uid='GeoChat.sender1.All Chat Rooms.msg-001' type='b-t-f' time='2025-01-01T12:00:00Z' start='2025-01-01T12:00:00Z' stale='2025-01-02T12:00:00Z' how='h-g-i-g-o'>
		<point lat='0' lon='0' hae='9999999.0' ce='9999999.0' le='9999999.0'/>
		<detail>
		<contact callsign='Alice' endpoint='0.0.0.0:4242:tcp'/>
		<__chat senderCallsign='Alice' chatroom='All Chat Rooms'>
		<chatgrp uid0='sender1' uid1='All Chat Rooms'/>
		</__chat>
		<remarks>Hello from ATAK!</remarks>
		</detail>
		</event>
		""".data(using: .utf8)!

		let msg = try CoTMessage.parseData(xml)
		#expect(msg.type == "b-t-f")
		#expect(msg.chat?.senderCallsign == "Alice")
		#expect(msg.chat?.message == "Hello from ATAK!")
	}

	@Test func parse_minimalEvent() throws {
		let xml = """
		<?xml version='1.0' encoding='UTF-8'?>
		<event version='2.0' uid='test' type='a-f-G' time='2025-01-01T12:00:00Z' start='2025-01-01T12:00:00Z' stale='2025-01-01T12:10:00Z' how='m-g'>
		<point lat='0' lon='0' hae='0' ce='0' le='0'/>
		<detail/>
		</event>
		""".data(using: .utf8)!

		let msg = try CoTMessage.parseData(xml)
		#expect(msg.uid == "test")
		#expect(msg.contact == nil)
		#expect(msg.group == nil)
		#expect(msg.status == nil)
	}

	@Test func parse_emptyData_throws() {
		#expect(throws: CoTParseError.self) {
			try CoTMessage.parseData(Data())
		}
	}

	@Test func parse_invalidXml_throws() {
		let xml = "not xml at all".data(using: .utf8)!
		#expect(throws: (any Error).self) {
			try CoTMessage.parseData(xml)
		}
	}

	@Test func parse_withFractionalSeconds() throws {
		let xml = """
		<?xml version='1.0' encoding='UTF-8'?>
		<event version='2.0' uid='frac-test' type='a-f-G' time='2025-06-15T10:30:45.123Z' start='2025-06-15T10:30:45.123Z' stale='2025-06-15T10:40:45.123Z' how='m-g'>
		<point lat='37.0' lon='-122.0' hae='0' ce='0' le='0'/>
		<detail/>
		</event>
		""".data(using: .utf8)!

		let msg = try CoTMessage.parseData(xml)
		#expect(msg.uid == "frac-test")
		// Verify date was parsed (not defaulting to now)
		let calendar = Calendar.current
		#expect(calendar.component(.year, from: msg.time) == 2025)
	}

	@Test func parse_rawDetailXML_preserved() throws {
		let xml = """
		<?xml version='1.0' encoding='UTF-8'?>
		<event version='2.0' uid='detail-test' type='a-u-G' time='2025-01-01T12:00:00Z' start='2025-01-01T12:00:00Z' stale='2025-01-01T12:10:00Z' how='h-e'>
		<point lat='37.0' lon='-122.0' hae='0' ce='0' le='0'/>
		<detail>
		<contact callsign='Marker1'/>
		<usericon iconsetpath='some/path/icon.png'/>
		<precisionlocation geopointsrc='GPS' altsrc='GPS'/>
		</detail>
		</event>
		""".data(using: .utf8)!

		let msg = try CoTMessage.parseData(xml)
		#expect(msg.rawDetailXML != nil)
		#expect(msg.rawDetailXML?.contains("usericon") == true)
		#expect(msg.rawDetailXML?.contains("precisionlocation") == true)
	}

	@Test func parse_statusBattery() throws {
		let xml = """
		<?xml version='1.0' encoding='UTF-8'?>
		<event version='2.0' uid='bat-test' type='a-f-G' time='2025-01-01T12:00:00Z' start='2025-01-01T12:00:00Z' stale='2025-01-01T12:10:00Z' how='m-g'>
		<point lat='0' lon='0' hae='0' ce='0' le='0'/>
		<detail>
		<status battery='42'/>
		</detail>
		</event>
		""".data(using: .utf8)!

		let msg = try CoTMessage.parseData(xml)
		#expect(msg.status?.battery == 42)
	}

	@Test func parse_trackSpeedCourse() throws {
		let xml = """
		<?xml version='1.0' encoding='UTF-8'?>
		<event version='2.0' uid='track-test' type='a-f-G' time='2025-01-01T12:00:00Z' start='2025-01-01T12:00:00Z' stale='2025-01-01T12:10:00Z' how='m-g'>
		<point lat='0' lon='0' hae='0' ce='0' le='0'/>
		<detail>
		<track speed='25.5' course='90.0'/>
		</detail>
		</event>
		""".data(using: .utf8)!

		let msg = try CoTMessage.parseData(xml)
		#expect(msg.track?.speed == 25.5)
		#expect(msg.track?.course == 90.0)
	}
}

// MARK: - CoTParseError

@Suite("CoTParseError")
struct CoTParseErrorTests {

	@Test func parseFailed_description() {
		let error = CoTParseError.parseFailed("bad xml")
		#expect(error.errorDescription?.contains("bad xml") == true)
	}

	@Test func invalidMessage_description() {
		let error = CoTParseError.invalidMessage
		#expect(error.errorDescription?.contains("Invalid") == true)
	}

	@Test func emptyData_description() {
		let error = CoTParseError.emptyData
		#expect(error.errorDescription?.contains("Empty") == true)
	}
}
