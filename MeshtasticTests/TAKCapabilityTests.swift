import Testing

@testable import Meshtastic

@MainActor
@Suite("TAK firmware capability")
struct TAKCapabilityTests {

	@Test func unknownFirmwareUsesLegacyTAKProtocol() {
		#expect(AccessoryManager.isTAKv2Supported(firmwareVersion: nil) == false)
	}

	@Test func malformedFirmwareUsesLegacyTAKProtocol() {
		#expect(AccessoryManager.isTAKv2Supported(firmwareVersion: "unknown") == false)
		#expect(AccessoryManager.isTAKv2Supported(firmwareVersion: "-2.8.0") == false)
		#expect(AccessoryManager.isTAKv2Supported(firmwareVersion: "2.-8.0") == false)
		#expect(AccessoryManager.isTAKv2Supported(firmwareVersion: "2.9.-1.abcdef0") == false)
		#expect(AccessoryManager.isTAKv2Supported(firmwareVersion: "2.8.0-alpha") == false)
		#expect(AccessoryManager.isTAKv2Supported(firmwareVersion: "2.8.0.") == false)
		#expect(AccessoryManager.isTAKv2Supported(firmwareVersion: "2.8.0.x") == false)
	}

	@Test func legacyFirmwareUsesLegacyTAKProtocol() {
		#expect(AccessoryManager.isTAKv2Supported(firmwareVersion: "2.7.9") == false)
	}

	@Test func supportedFirmwareUsesTAKV2Protocol() {
		#expect(AccessoryManager.isTAKv2Supported(firmwareVersion: "2.8.0") == true)
		#expect(AccessoryManager.isTAKv2Supported(firmwareVersion: "2.8.0.3a0c08b") == true)
	}
}
