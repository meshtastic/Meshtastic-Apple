// TAKBridgeDetailedTests.swift
// MeshtasticTests

import Testing
import Foundation
import MeshtasticProtobufs
@testable import Meshtastic

// MARK: - TAKMeshtasticBridge.parseReceipt Tests

@Suite("TAKMeshtasticBridge parseReceipt")
struct TAKBridgeParseReceiptTests {

	@Test func deliveredReceipt() {
		let result = TAKMeshtasticBridge.parseReceipt(from: "ACK:D:msg-123")
		#expect(result != nil)
		if case .delivered = result!.type {} else {
			Issue.record("Expected .delivered type")
		}
		#expect(result!.messageId == "msg-123")
	}

	@Test func readReceipt() {
		let result = TAKMeshtasticBridge.parseReceipt(from: "ACK:R:msg-456")
		#expect(result != nil)
		if case .read = result!.type {} else {
			Issue.record("Expected .read type")
		}
		#expect(result!.messageId == "msg-456")
	}

	@Test func notAReceipt_returnsNil() {
		let result = TAKMeshtasticBridge.parseReceipt(from: "Hello world")
		#expect(result == nil)
	}

	@Test func emptyMessage_returnsNil() {
		let result = TAKMeshtasticBridge.parseReceipt(from: "")
		#expect(result == nil)
	}

	@Test func invalidReceiptType_returnsNil() {
		let result = TAKMeshtasticBridge.parseReceipt(from: "ACK:X:msg-789")
		#expect(result == nil)
	}

	@Test func missingMessageId_returnsNil() {
		let result = TAKMeshtasticBridge.parseReceipt(from: "ACK:D:")
		#expect(result == nil)
	}

	@Test func onlyPrefix_returnsNil() {
		let result = TAKMeshtasticBridge.parseReceipt(from: "ACK:")
		#expect(result == nil)
	}

	@Test func messageIdWithColons() {
		let result = TAKMeshtasticBridge.parseReceipt(from: "ACK:D:uuid:with:colons")
		#expect(result != nil)
		#expect(result!.messageId == "uuid:with:colons")
	}
}

// MARK: - TAKMeshtasticBridge.parseDeviceCallsign Tests

@Suite("TAKMeshtasticBridge parseDeviceCallsign")
struct TAKBridgeParseDeviceCallsignTests {

	@Test func simpleCallsign() {
		let (callsign, msgId) = TAKMeshtasticBridge.parseDeviceCallsign("ANDROID-abc123")
		#expect(callsign == "ANDROID-abc123")
		#expect(msgId == nil)
	}

	@Test func smuggledMessageId() {
		let (callsign, msgId) = TAKMeshtasticBridge.parseDeviceCallsign("ANDROID-abc123|msg-456")
		#expect(callsign == "ANDROID-abc123")
		#expect(msgId == "msg-456")
	}

	@Test func emptyString() {
		let (callsign, msgId) = TAKMeshtasticBridge.parseDeviceCallsign("")
		#expect(callsign == "")
		#expect(msgId == nil)
	}

	@Test func nilInput() {
		let (callsign, msgId) = TAKMeshtasticBridge.parseDeviceCallsign(nil)
		#expect(callsign == "")
		#expect(msgId == nil)
	}

	@Test func pipeOnly() {
		let (callsign, msgId) = TAKMeshtasticBridge.parseDeviceCallsign("|")
		#expect(callsign == "")
		#expect(msgId == nil)
	}

	@Test func pipeWithEmpty() {
		let (callsign, msgId) = TAKMeshtasticBridge.parseDeviceCallsign("device|")
		#expect(callsign == "device")
		#expect(msgId == nil)
	}

	@Test func multiplePipes_onlyFirstSplit() {
		let (callsign, msgId) = TAKMeshtasticBridge.parseDeviceCallsign("device|msg|extra")
		#expect(callsign == "device")
		#expect(msgId == "msg|extra")
	}
}

// MARK: - TAKMeshtasticBridge.createSmuggledDeviceCallsign Tests

@Suite("TAKMeshtasticBridge createSmuggledDeviceCallsign")
struct TAKBridgeCreateSmuggledCallsignTests {

	@Test func basicSmuggle() {
		let result = TAKMeshtasticBridge.createSmuggledDeviceCallsign(
			deviceCallsign: "ANDROID-abc",
			messageId: "msg-123"
		)
		#expect(result == "ANDROID-abc|msg-123")
	}

	@Test func roundTrip() {
		let smuggled = TAKMeshtasticBridge.createSmuggledDeviceCallsign(
			deviceCallsign: "DEV-001",
			messageId: "uuid-xyz"
		)
		let (callsign, msgId) = TAKMeshtasticBridge.parseDeviceCallsign(smuggled)
		#expect(callsign == "DEV-001")
		#expect(msgId == "uuid-xyz")
	}

	@Test func emptyCallsign() {
		let result = TAKMeshtasticBridge.createSmuggledDeviceCallsign(
			deviceCallsign: "",
			messageId: "msg"
		)
		#expect(result == "|msg")
	}
}

// MARK: - TAKMeshtasticBridge.isReceipt Tests

@Suite("TAKMeshtasticBridge isReceipt")
struct TAKBridgeIsReceiptTests {

	@Test func chatWithACK_isReceipt() {
		var packet = TAKPacket()
		var geoChat = GeoChat()
		geoChat.message = "ACK:D:msg-123"
		packet.chat = geoChat
		#expect(TAKMeshtasticBridge.isReceipt(packet) == true)
	}

	@Test func chatWithoutACK_isNotReceipt() {
		var packet = TAKPacket()
		var geoChat = GeoChat()
		geoChat.message = "Hello"
		packet.chat = geoChat
		#expect(TAKMeshtasticBridge.isReceipt(packet) == false)
	}

	@Test func pliPacket_isNotReceipt() {
		var packet = TAKPacket()
		var pli = PLI()
		pli.latitudeI = 374000000
		packet.pli = pli
		#expect(TAKMeshtasticBridge.isReceipt(packet) == false)
	}
}
