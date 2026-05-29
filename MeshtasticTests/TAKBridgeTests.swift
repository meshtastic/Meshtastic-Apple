import Foundation
import Testing

@testable import Meshtastic

// MARK: - parseReceipt

@Suite("TAKMeshtasticBridge parseReceipt")
struct TAKBridgeReceiptTests {

	@Test func delivered_receipt() {
		let receipt = TAKMeshtasticBridge.parseReceipt(from: "ACK:D:msg-123")
		#expect(receipt != nil)
		#expect(receipt?.messageId == "msg-123")
		if case .delivered = receipt?.type {} else {
			#expect(Bool(false), "Expected delivered")
		}
	}

	@Test func read_receipt() {
		let receipt = TAKMeshtasticBridge.parseReceipt(from: "ACK:R:msg-456")
		#expect(receipt != nil)
		#expect(receipt?.messageId == "msg-456")
		if case .read = receipt?.type {} else {
			#expect(Bool(false), "Expected read")
		}
	}

	@Test func not_a_receipt() {
		#expect(TAKMeshtasticBridge.parseReceipt(from: "Hello World") == nil)
	}

	@Test func empty_string() {
		#expect(TAKMeshtasticBridge.parseReceipt(from: "") == nil)
	}

	@Test func ack_prefix_only() {
		#expect(TAKMeshtasticBridge.parseReceipt(from: "ACK:") == nil)
	}

	@Test func ack_unknown_type() {
		#expect(TAKMeshtasticBridge.parseReceipt(from: "ACK:X:msg-789") == nil)
	}

	@Test func ack_empty_messageId() {
		#expect(TAKMeshtasticBridge.parseReceipt(from: "ACK:D:") == nil)
	}

	@Test func messageId_with_colons() {
		let receipt = TAKMeshtasticBridge.parseReceipt(from: "ACK:D:part1:part2:part3")
		#expect(receipt != nil)
		#expect(receipt?.messageId == "part1:part2:part3")
	}
}

// MARK: - parseDeviceCallsign

@Suite("TAKMeshtasticBridge parseDeviceCallsign")
struct TAKBridgeCallsignTests {

	@Test func simple_callsign() {
		let (callsign, messageId) = TAKMeshtasticBridge.parseDeviceCallsign("ANDROID-abc123")
		#expect(callsign == "ANDROID-abc123")
		#expect(messageId == nil)
	}

	@Test func callsign_with_messageId() {
		let (callsign, messageId) = TAKMeshtasticBridge.parseDeviceCallsign("ANDROID-abc|msg-42")
		#expect(callsign == "ANDROID-abc")
		#expect(messageId == "msg-42")
	}

	@Test func empty_string() {
		let (callsign, messageId) = TAKMeshtasticBridge.parseDeviceCallsign("")
		#expect(callsign == "")
		#expect(messageId == nil)
	}

	@Test func nil_input() {
		let (callsign, messageId) = TAKMeshtasticBridge.parseDeviceCallsign(nil)
		#expect(callsign == "")
		#expect(messageId == nil)
	}

	@Test func pipe_at_end_empty_messageId() {
		let (callsign, messageId) = TAKMeshtasticBridge.parseDeviceCallsign("ANDROID-abc|")
		#expect(callsign == "ANDROID-abc")
		#expect(messageId == nil)
	}

	@Test func pipe_at_start() {
		let (callsign, messageId) = TAKMeshtasticBridge.parseDeviceCallsign("|msg-42")
		#expect(callsign == "")
		#expect(messageId == "msg-42")
	}

	@Test func multiple_pipes() {
		let (callsign, messageId) = TAKMeshtasticBridge.parseDeviceCallsign("abc|def|ghi")
		#expect(callsign == "abc")
		#expect(messageId == "def|ghi")
	}
}

// MARK: - createSmuggledDeviceCallsign

@Suite("TAKMeshtasticBridge createSmuggledDeviceCallsign")
struct TAKBridgeSmuggledTests {

	@Test func creates_combined_string() {
		let result = TAKMeshtasticBridge.createSmuggledDeviceCallsign(
			deviceCallsign: "ANDROID-abc",
			messageId: "msg-42"
		)
		#expect(result == "ANDROID-abc|msg-42")
	}

	@Test func roundTrip() {
		let original = "DEVICE-123"
		let messageId = "uuid-456"
		let smuggled = TAKMeshtasticBridge.createSmuggledDeviceCallsign(
			deviceCallsign: original,
			messageId: messageId
		)
		let (parsed, parsedId) = TAKMeshtasticBridge.parseDeviceCallsign(smuggled)
		#expect(parsed == original)
		#expect(parsedId == messageId)
	}

	@Test func empty_callsign() {
		let result = TAKMeshtasticBridge.createSmuggledDeviceCallsign(
			deviceCallsign: "",
			messageId: "msg"
		)
		#expect(result == "|msg")
	}
}
