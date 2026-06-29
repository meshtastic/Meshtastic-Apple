// MARK: NetworkConfigIPConversionTests

import Foundation
import Testing

@testable import Meshtastic

/// Verifies the IPv4 <-> UInt32 conversion in `NetworkConfig` uses little-endian
/// octet order (first octet = least-significant byte), matching the firmware's
/// Arduino IPAddress storage and the Meshtastic Android app. A big-endian
/// implementation would display and write addresses byte-reversed.
@Suite("NetworkConfig IPv4 conversion")
struct NetworkConfigIPConversionTests {

	private let view = NetworkConfig(node: nil)

	// MARK: - Known little-endian mapping

	@Test func stringToUInt32IsLittleEndian() {
		// 192.168.1.1 -> 192 | 168<<8 | 1<<16 | 1<<24 == 0x0101A8C0
		#expect(view.ipStringToUInt32("192.168.1.1") == 0x0101_A8C0)
	}

	@Test func uint32ToStringIsLittleEndian() {
		#expect(view.uint32ToIpString(0x0101_A8C0) == "192.168.1.1")
	}

	@Test func octetOrderIsNotReversed() {
		// Asymmetric address catches an accidental byte swap that a palindrome wouldn't.
		let value = view.ipStringToUInt32("10.20.30.40")
		#expect(view.uint32ToIpString(value) == "10.20.30.40")
		#expect(value == (10 | (20 << 8) | (30 << 16) | (40 << 24)))
	}

	// MARK: - Round trips

	@Test(arguments: [
		"0.0.0.1",
		"1.2.3.4",
		"10.0.0.138",
		"172.16.254.1",
		"192.168.50.100",
		"255.255.255.0",
		"255.255.255.255"
	])
	func roundTripsPreserveAddress(_ address: String) {
		let value = view.ipStringToUInt32(address)
		#expect(view.uint32ToIpString(value) == address)
	}

	@Test func subnetMaskRoundTrips() {
		let value = view.ipStringToUInt32("255.255.255.0")
		#expect(view.uint32ToIpString(value) == "255.255.255.0")
		// Each octet maps to a distinct byte; 0 only in the high byte.
		#expect(value == 0x00FF_FFFF)
	}

	// MARK: - Edge cases

	@Test func zeroValueMapsToEmptyString() {
		#expect(view.uint32ToIpString(0) == "")
	}

	@Test func emptyAndUnsetAddressesMapToZero() {
		#expect(view.ipStringToUInt32("") == 0)
		#expect(view.ipStringToUInt32("0.0.0.0") == 0)
	}

	@Test(arguments: [
		"192.168.1",         // too few octets
		"192.168.1.1.1",     // too many octets
		"192.168.1.256",     // octet out of range
		"192.168.1.x",       // non-numeric octet
		"not an ip"
	])
	func malformedAddressesMapToZero(_ address: String) {
		#expect(view.ipStringToUInt32(address) == 0)
	}
}
