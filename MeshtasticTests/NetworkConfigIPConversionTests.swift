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

	// MARK: - Field validation

	// An empty field is intentionally valid — it means "unset" and is stored as 0.0.0.0.
	@Test func emptyFieldIsValid() {
		#expect(NetworkConfig.isValidIPv4Field("") == true)
	}

	@Test(arguments: [
		"0.0.0.0",
		"192.168.1.1",
		"10.0.0.138",
		"255.255.255.255",
		"255.255.255.0"
	])
	func wellFormedAddressesAreValid(_ address: String) {
		#expect(NetworkConfig.isValidIPv4Field(address) == true)
	}

	@Test(arguments: [
		"192.168.1",         // too few octets
		"192.168.1.1.1",     // too many octets
		"192.168.1.300",     // octet out of range
		"192.168.1.256",     // octet just out of range
		"192.168.1.",        // trailing dot / empty octet
		"192.168..1",        // empty interior octet
		"192.168.1.x",       // non-numeric octet
		"192.168.1.+1",      // sign character UInt32 would otherwise accept
		"192.168.1. 1",      // embedded whitespace
		"192.168.1.0000",    // more than three digits
		"not an ip"
	])
	func malformedAddressesAreInvalid(_ address: String) {
		#expect(NetworkConfig.isValidIPv4Field(address) == false)
	}

	// MARK: - Save gating (isStaticConfigValid)

	// `isStaticConfigValid` is the pure logic behind the Save button's `.disabled`, so its
	// behavior — DHCP bypass, blocking malformed input, requiring IP/gateway/subnet, allowing
	// blank DNS — is exercised directly here rather than only through the lower-level field
	// helper. It takes plain parameters (no @State), which is also why the gating logic was
	// extracted from the view: @State values can't be set outside a live SwiftUI render context.

	// DHCP mode (addressMode 0) ignores the static fields entirely, even garbage.
	@Test func dhcpModeBypassesStaticValidation() {
		#expect(NetworkConfig.isStaticConfigValid(addressMode: 0, ip: "not an ip", gateway: "garbage", subnet: "", dns: "") == true)
	}

	@Test func staticModeWithWellFormedFieldsIsValid() {
		#expect(NetworkConfig.isStaticConfigValid(addressMode: 1, ip: "192.168.1.10", gateway: "192.168.1.1", subnet: "255.255.255.0", dns: "8.8.8.8") == true)
	}

	// DNS is the one optional field: blank means "unset" (written as 0.0.0.0) and stays saveable
	// when the three required fields are filled and well-formed.
	@Test func staticModeWithBlankDNSIsValid() {
		#expect(NetworkConfig.isStaticConfigValid(addressMode: 1, ip: "192.168.1.10", gateway: "192.168.1.1", subnet: "255.255.255.0", dns: "") == true)
	}

	// A static config without IP, gateway, and subnet is non-functional — saving it would write
	// 0.0.0.0 for the missing fields, the same silent-broken-config this change exists to block.
	@Test func staticModeWithBlankFieldsBlocksSave() {
		#expect(NetworkConfig.isStaticConfigValid(addressMode: 1, ip: "", gateway: "", subnet: "", dns: "") == false)
	}

	@Test func staticModeWithBlankIPBlocksSave() {
		#expect(NetworkConfig.isStaticConfigValid(addressMode: 1, ip: "", gateway: "192.168.1.1", subnet: "255.255.255.0", dns: "") == false)
	}

	@Test func staticModeWithBlankGatewayBlocksSave() {
		#expect(NetworkConfig.isStaticConfigValid(addressMode: 1, ip: "192.168.1.10", gateway: "", subnet: "255.255.255.0", dns: "") == false)
	}

	@Test func staticModeWithBlankSubnetBlocksSave() {
		#expect(NetworkConfig.isStaticConfigValid(addressMode: 1, ip: "192.168.1.10", gateway: "192.168.1.1", subnet: "", dns: "") == false)
	}

	// A non-empty typo in any one field blocks the save — the core purpose of the change.
	@Test(arguments: ["192.168.1", "192.168.1.300", "192.168.1.x"])
	func staticModeWithMalformedIPBlocksSave(_ badIP: String) {
		#expect(NetworkConfig.isStaticConfigValid(addressMode: 1, ip: badIP, gateway: "192.168.1.1", subnet: "255.255.255.0", dns: "") == false)
	}

	@Test func staticModeWithMalformedGatewayBlocksSave() {
		#expect(NetworkConfig.isStaticConfigValid(addressMode: 1, ip: "192.168.1.10", gateway: "192.168.1.300", subnet: "255.255.255.0", dns: "") == false)
	}

	@Test func staticModeWithMalformedDNSBlocksSave() {
		#expect(NetworkConfig.isStaticConfigValid(addressMode: 1, ip: "192.168.1.10", gateway: "192.168.1.1", subnet: "255.255.255.0", dns: "8.8.8") == false)
	}

	// The field-tint helper treats blank as invalid for the three required fields (red + hint),
	// while a well-formed value stays gray.
	@Test func requiredFieldTintTreatsBlankAsInvalid() {
		#expect(NetworkConfig.isRequiredIPv4FieldValid("") == false)
		#expect(NetworkConfig.isRequiredIPv4FieldValid("192.168.1.10") == true)
		#expect(NetworkConfig.isRequiredIPv4FieldValid("192.168.1") == false)
	}
}
