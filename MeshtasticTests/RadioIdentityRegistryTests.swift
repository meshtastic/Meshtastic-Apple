// RadioIdentityRegistryTests.swift
// MeshtasticTests

import Foundation
import SwiftData
import Testing
@testable import Meshtastic

@Suite("Radio identity registry", .serialized)
@MainActor
struct RadioIdentityRegistryTests {
	private let deviceA = "0011223344556677"
	private let deviceB = "8899aabbccddeeff"

	@Test("firmware device IDs use Android-compatible validation")
	func validatesDeviceIDs() {
		#expect(RadioIdentityObservation.normalizedDeviceID(" 001122AABBCCDDEE ") == "001122aabbccddee")
		#expect(RadioIdentityObservation.normalizedDeviceID("unknown") == nil)
		#expect(RadioIdentityObservation.normalizedDeviceID("001122") == nil)
		#expect(RadioIdentityObservation.normalizedDeviceID("00112233445566zz") == nil)
		#expect(RadioIdentityObservation.normalizedDeviceID(String(repeating: "a", count: 65)) == nil)
	}

	@Test("first observation creates immutable random store identity")
	func createsProfile() throws {
		let registry = try makeRegistry()
		let observation = bleObservation(alias: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", deviceID: deviceA, nodeNum: 1)

		let result = try registry.record(observation)
		let profile = try #require(try registry.profiles().first)
		#expect(result == .resolved(profile.id))
		#expect(profile.deviceID == deviceA)
		#expect(profile.nodeNum == 1)
		#expect(profile.storeKey != profile.id)
		#expect(profile.storeKey.uuidString.lowercased() != deviceA)
		#expect(profile.aliases.map(\.key) == [observation.aliasKey])
	}

	@Test("device identity converges multiple transport aliases")
	func convergesAliasesByDeviceID() throws {
		let registry = try makeRegistry()
		let ble = bleObservation(alias: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", deviceID: deviceA, nodeNum: 1)
		let tcp = tcpObservation(identifier: "Mesh.Local", deviceID: deviceA.uppercased(), nodeNum: 1)

		let first = try registry.record(ble)
		let second = try registry.record(tcp)

		#expect(second == first)
		let profile = try #require(try registry.profiles().first)
		#expect(profile.aliases.map(\.key).sorted() == [ble.aliasKey, tcp.aliasKey].sorted())
	}

	@Test("stable device identity survives node renumbering")
	func convergesAfterNodeRenumbering() throws {
		let registry = try makeRegistry()
		let beforeErase = bleObservation(
			alias: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
			deviceID: deviceA,
			nodeNum: 1
		)
		let afterErase = serialObservation(
			identifier: "/dev/cu.usbmodem7",
			deviceID: deviceA,
			nodeNum: 2
		)

		let first = try registry.record(beforeErase)
		let second = try registry.record(afterErase)
		let profile = try #require(try registry.profiles().first)

		#expect(second == first)
		#expect(try registry.profiles().count == 1)
		#expect(profile.nodeNum == 2)
		#expect(profile.aliases.count == 2)
	}

	@Test("node fallback converges aliases when device ID is unavailable")
	func convergesByNodeFallback() throws {
		let registry = try makeRegistry()
		let ble = bleObservation(alias: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", deviceID: "unknown", nodeNum: 7)
		let serial = serialObservation(identifier: "/dev/cu.usbmodem7", deviceID: "", nodeNum: 7)

		let first = try registry.record(ble)
		let second = try registry.record(serial)

		#expect(second == first)
		let profile = try #require(try registry.profiles().first)
		#expect(profile.deviceID == nil)
		#expect(profile.aliases.count == 2)
	}

	@Test("matching alias corroborates fallback promotion")
	func promotesFallbackWithAliasEvidence() throws {
		let registry = try makeRegistry()
		let fallback = bleObservation(alias: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", deviceID: "unknown", nodeNum: 7)
		let identified = bleObservation(alias: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", deviceID: deviceA, nodeNum: 7)

		let first = try registry.record(fallback)
		let promoted = try registry.record(identified)

		#expect(promoted == first)
		let profile = try #require(try registry.profiles().first)
		#expect(profile.deviceID == deviceA)
		#expect(profile.quarantineReason == nil)
	}

	@Test("reassignable TCP alias cannot corroborate fallback promotion")
	func tcpAliasCannotPromoteFallback() throws {
		let registry = try makeRegistry()
		let fallback = tcpObservation(identifier: "mesh.local:4403", deviceID: "unknown", nodeNum: 7)
		let identified = tcpObservation(identifier: "mesh.local:4403", deviceID: deviceA, nodeNum: 7)
		_ = try registry.record(fallback)

		let result = try registry.record(identified)
		let profiles = try registry.profiles()

		#expect(profiles.count == 2)
		#expect(profiles.allSatisfy { $0.quarantineReason != nil })
		#expect(result.quarantinedProfileIDs == Set(profiles.map(\.id)))
	}

	@Test("uncorroborated fallback promotion is quarantined")
	func quarantinesAmbiguousPromotion() throws {
		let registry = try makeRegistry()
		let fallback = bleObservation(alias: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", deviceID: "unknown", nodeNum: 7)
		let identified = tcpObservation(identifier: "mesh.local:4403", deviceID: deviceA, nodeNum: 7)
		_ = try registry.record(fallback)

		let result = try registry.record(identified)
		let profiles = try registry.profiles()

		#expect(profiles.count == 2)
		#expect(profiles.allSatisfy { $0.quarantineReason != nil })
		#expect(result.quarantinedProfileIDs == Set(profiles.map(\.id)))
	}

	@Test("disagreeing device and node claims are quarantined")
	func quarantinesClaimConflict() throws {
		let registry = try makeRegistry()
		let first = bleObservation(alias: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", deviceID: deviceA, nodeNum: 1)
		let second = bleObservation(alias: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB", deviceID: deviceB, nodeNum: 2)
		_ = try registry.record(first)
		_ = try registry.record(second)

		let conflicting = serialObservation(identifier: "/dev/cu.conflict", deviceID: deviceA, nodeNum: 2)
		let result = try registry.record(conflicting)
		let profiles = try registry.profiles()

		#expect(profiles.count == 2)
		#expect(profiles.allSatisfy { $0.quarantineReason != nil })
		#expect(result.quarantinedProfileIDs == Set(profiles.map(\.id)))
	}

	@Test("alias evidence alone cannot create a profile")
	func ignoresAliasWithoutRadioIdentity() throws {
		let registry = try makeRegistry()
		let observation = RadioIdentityObservation(
			transport: .tcp,
			transportDeviceID: UUID(),
			identifier: "mesh.local",
			deviceID: "unknown",
			nodeNum: nil
		)

		#expect(try registry.record(observation) == .ignored)
		#expect(try registry.profiles().isEmpty)
		#expect(try registry.aliases().isEmpty)
	}

	private func makeRegistry() throws -> RadioIdentityRegistry {
		try RadioIdentityRegistry(container: RadioRegistryController.makeContainer(inMemory: true))
	}

	private func bleObservation(alias: String, deviceID: String, nodeNum: Int64) -> RadioIdentityObservation {
		RadioIdentityObservation(
			transport: .ble,
			transportDeviceID: UUID(uuidString: alias)!,
			identifier: alias,
			deviceID: deviceID,
			nodeNum: nodeNum
		)
	}

	private func tcpObservation(identifier: String, deviceID: String, nodeNum: Int64) -> RadioIdentityObservation {
		RadioIdentityObservation(
			transport: .tcp,
			transportDeviceID: UUID(),
			identifier: identifier,
			deviceID: deviceID,
			nodeNum: nodeNum
		)
	}

	private func serialObservation(identifier: String, deviceID: String, nodeNum: Int64) -> RadioIdentityObservation {
		RadioIdentityObservation(
			transport: .serial,
			transportDeviceID: UUID(),
			identifier: identifier,
			deviceID: deviceID,
			nodeNum: nodeNum
		)
	}
}

private extension RadioIdentityResolution {
	var quarantinedProfileIDs: Set<UUID> {
		guard case .quarantined(let profileIDs) = self else { return [] }
		return Set(profileIDs)
	}
}
