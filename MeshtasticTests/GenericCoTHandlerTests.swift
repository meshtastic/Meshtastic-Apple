import Foundation
import Testing

@testable import Meshtastic

// MARK: - GenericCoTHandler Send Method Classification

@Suite("GenericCoTHandler classifySendMethod")
struct GenericCoTHandlerTests {

	@Test @MainActor func pli_returnsTPLI() {
		let cot = CoTMessage(uid: "test", type: "a-f-G-U-C")
		let method = GenericCoTHandler.shared.classifySendMethod(for: cot)
		#expect(method == .takPacketPLI)
	}

	@Test @MainActor func pli_lowercase_returnsTPLI() {
		let cot = CoTMessage(uid: "test", type: "a-f-g-u-c")
		let method = GenericCoTHandler.shared.classifySendMethod(for: cot)
		#expect(method == .takPacketPLI)
	}

	@Test @MainActor func chat_returnsTChat() {
		let cot = CoTMessage(uid: "test", type: "b-t-f")
		let method = GenericCoTHandler.shared.classifySendMethod(for: cot)
		#expect(method == .takPacketChat)
	}

	@Test @MainActor func marker_returnsExi() {
		let cot = CoTMessage(uid: "test", type: "a-u-G")
		let method = GenericCoTHandler.shared.classifySendMethod(for: cot)
		// Should be either exiDirect or exiFountain depending on size
		#expect(method == .exiDirect || method == .exiFountain)
	}

	@Test @MainActor func unknownType_returnsExi() {
		let cot = CoTMessage(uid: "test", type: "z-x-y")
		let method = GenericCoTHandler.shared.classifySendMethod(for: cot)
		#expect(method == .exiDirect || method == .exiFountain)
	}
}

// MARK: - TAK Port Numbers

@Suite("TAKPortNum")
struct TAKPortNumTests {

	@Test func atakPlugin_is72() {
		#expect(TAKPortNum.atakPlugin.rawValue == 72)
	}

	@Test func atakForwarder_is257() {
		#expect(TAKPortNum.atakForwarder.rawValue == 257)
	}
}
