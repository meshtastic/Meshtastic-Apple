// MARK: NetworkConfigIPConversionTests

import Foundation
import Testing

import MeshtasticProtobufs
@testable import Meshtastic

/// Verifies the IPv4 <-> UInt32 conversion in `IPv4Address` uses little-endian
/// octet order (first octet = least-significant byte), matching the firmware's
/// Arduino IPAddress storage and the Meshtastic Android app. A big-endian
/// implementation would display and write addresses byte-reversed.
@Suite("NetworkConfig IPv4 conversion")
struct NetworkConfigIPConversionTests {

	/// The message the form holds, built the way the address rows build it: text that
	/// does not parse becomes 0, which reads as unset.
	private func staticConfig(mode: Int, ip: String, gateway: String, subnet: String, dns: String) -> Config.NetworkConfig {
		var config = Config.NetworkConfig()
		config.addressMode = mode == 1 ? .static : .dhcp
		var ipv4 = Config.NetworkConfig.IpV4Config()
		ipv4.ip = IPv4Address.toUInt32(ip)
		ipv4.gateway = IPv4Address.toUInt32(gateway)
		ipv4.subnet = IPv4Address.toUInt32(subnet)
		ipv4.dns = IPv4Address.toUInt32(dns)
		config.ipv4Config = ipv4
		return config
	}

	// MARK: - Known little-endian mapping

	@Test func stringToUInt32IsLittleEndian() {
		// 192.168.1.1 -> 192 | 168<<8 | 1<<16 | 1<<24 == 0x0101A8C0
		#expect(IPv4Address.toUInt32("192.168.1.1") == 0x0101_A8C0)
	}

	@Test func uint32ToStringIsLittleEndian() {
		#expect(IPv4Address.toString(0x0101_A8C0) == "192.168.1.1")
	}

	@Test func octetOrderIsNotReversed() {
		// Asymmetric address catches an accidental byte swap that a palindrome wouldn't.
		let value = IPv4Address.toUInt32("10.20.30.40")
		#expect(IPv4Address.toString(value) == "10.20.30.40")
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
		let value = IPv4Address.toUInt32(address)
		#expect(IPv4Address.toString(value) == address)
	}

	@Test func subnetMaskRoundTrips() {
		let value = IPv4Address.toUInt32("255.255.255.0")
		#expect(IPv4Address.toString(value) == "255.255.255.0")
		// Each octet maps to a distinct byte; 0 only in the high byte.
		#expect(value == 0x00FF_FFFF)
	}

	// MARK: - Edge cases

	@Test func zeroValueMapsToEmptyString() {
		#expect(IPv4Address.toString(0) == "")
	}

	@Test func emptyAndUnsetAddressesMapToZero() {
		#expect(IPv4Address.toUInt32("") == 0)
		#expect(IPv4Address.toUInt32("0.0.0.0") == 0)
	}

	@Test(arguments: [
		"192.168.1",         // too few octets
		"192.168.1.1.1",     // too many octets
		"192.168.1.256",     // octet out of range
		"192.168.1.x",       // non-numeric octet
		"not an ip"
	])
	func malformedAddressesMapToZero(_ address: String) {
		#expect(IPv4Address.toUInt32(address) == 0)
	}

	// MARK: - Field validation

	// An empty field is intentionally valid — it means "unset" and is stored as 0.0.0.0.
	@Test func emptyFieldIsValid() {
		#expect(IPv4Address.isFieldValid("") == true)
	}

	@Test(arguments: [
		"0.0.0.0",
		"192.168.1.1",
		"10.0.0.138",
		"255.255.255.255",
		"255.255.255.0"
	])
	func wellFormedAddressesAreValid(_ address: String) {
		#expect(IPv4Address.isFieldValid(address) == true)
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
		#expect(IPv4Address.isFieldValid(address) == false)
	}

	// MARK: - Save gating (canSave)

	// `canSave` is the logic behind the Save button, so its behavior — DHCP bypass,
	// blocking malformed input, requiring IP/gateway/subnet, allowing blank DNS — is
	// exercised directly here rather than only through the lower-level field helper.
	// It reads the message the form holds rather than four pieces of view state, which
	// is what lets it be tested at all.

	// DHCP mode (addressMode 0) ignores the static fields entirely, even garbage.
	@Test func dhcpModeBypassesStaticValidation() {
		#expect(NetworkConfig.canSave(staticConfig(mode: 0, ip: "not an ip", gateway: "garbage", subnet: "", dns: "")) == true)
	}

	@Test func staticModeWithWellFormedFieldsIsValid() {
		#expect(NetworkConfig.canSave(staticConfig(mode: 1, ip: "192.168.1.10", gateway: "192.168.1.1", subnet: "255.255.255.0", dns: "8.8.8.8")) == true)
	}

	// DNS is the one optional field: blank means "unset" (written as 0.0.0.0) and stays saveable
	// when the three required fields are filled and well-formed.
	@Test func staticModeWithBlankDNSIsValid() {
		#expect(NetworkConfig.canSave(staticConfig(mode: 1, ip: "192.168.1.10", gateway: "192.168.1.1", subnet: "255.255.255.0", dns: "")) == true)
	}

	// A static config without IP, gateway, and subnet is non-functional — saving it would write
	// 0.0.0.0 for the missing fields, the same silent-broken-config this change exists to block.
	@Test func staticModeWithBlankFieldsBlocksSave() {
		#expect(NetworkConfig.canSave(staticConfig(mode: 1, ip: "", gateway: "", subnet: "", dns: "")) == false)
	}

	@Test func staticModeWithBlankIPBlocksSave() {
		#expect(NetworkConfig.canSave(staticConfig(mode: 1, ip: "", gateway: "192.168.1.1", subnet: "255.255.255.0", dns: "")) == false)
	}

	@Test func staticModeWithBlankGatewayBlocksSave() {
		#expect(NetworkConfig.canSave(staticConfig(mode: 1, ip: "192.168.1.10", gateway: "", subnet: "255.255.255.0", dns: "")) == false)
	}

	@Test func staticModeWithBlankSubnetBlocksSave() {
		#expect(NetworkConfig.canSave(staticConfig(mode: 1, ip: "192.168.1.10", gateway: "192.168.1.1", subnet: "", dns: "")) == false)
	}

	// A non-empty typo in any one field blocks the save — the core purpose of the change.
	@Test(arguments: ["192.168.1", "192.168.1.300", "192.168.1.x"])
	func staticModeWithMalformedIPBlocksSave(_ badIP: String) {
		#expect(NetworkConfig.canSave(staticConfig(mode: 1, ip: badIP, gateway: "192.168.1.1", subnet: "255.255.255.0", dns: "")) == false)
	}

	@Test func staticModeWithMalformedGatewayBlocksSave() {
		#expect(NetworkConfig.canSave(staticConfig(mode: 1, ip: "192.168.1.10", gateway: "192.168.1.300", subnet: "255.255.255.0", dns: "")) == false)
	}

	// DNS is the one field where a typo no longer blocks the save. The gate reads the
	// stored address, and a malformed DNS entry stores as 0, which is indistinguishable
	// from the blank that DNS is allowed to be. The field still shows red while the text
	// is malformed, so the typo is visible; it saves as unset rather than as itself.
	@Test func staticModeWithMalformedDNSSavesAsUnset() {
		let config = staticConfig(mode: 1, ip: "192.168.1.10", gateway: "192.168.1.1", subnet: "255.255.255.0", dns: "8.8.8")
		#expect(config.ipv4Config.dns == 0, "the malformed entry did not become an address")
		#expect(NetworkConfig.canSave(config) == true)
	}

	// The field-tint helper treats blank as invalid for the three required fields (red + hint),
	// while a well-formed value stays gray.
	@Test func requiredFieldTintTreatsBlankAsInvalid() {
		#expect(IPv4Address.isRequiredFieldValid("") == false)
		#expect(IPv4Address.isRequiredFieldValid("192.168.1.10") == true)
		#expect(IPv4Address.isRequiredFieldValid("192.168.1") == false)
	}
}
