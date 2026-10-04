// WifiOTAHandoffTests.swift
// MeshtasticTests

import Foundation
import Network
import Testing
@testable import Meshtastic

@Suite("Wi-Fi OTA handoff address")
struct WifiOTAHandoffAddressTests {

	@Test func anIPv4LiteralNeedsNoLookup() {
		// The debug Device IP field. A second address from the socket must not replace it.
		#expect(WifiOTAHandoffAddress.resolve(providedHost: "10.10.10.76", connectedPeerIPv4: "192.168.0.5") == "10.10.10.76")
		#expect(WifiOTAHandoffAddress.resolve(providedHost: " 192.168.1.100\n", connectedPeerIPv4: nil) == "192.168.1.100")
	}

	@Test func theLivePeerIsUsedWhenTheHostIsASharedName() {
		#expect(WifiOTAHandoffAddress.resolve(providedHost: "Meshtastic.local", connectedPeerIPv4: "10.10.10.76") == "10.10.10.76")
		#expect(WifiOTAHandoffAddress.resolve(providedHost: nil, connectedPeerIPv4: "10.10.10.76") == "10.10.10.76")
	}

	@Test func aNameIsNeverTheAddress() {
		#expect(WifiOTAHandoffAddress.resolve(providedHost: "Meshtastic.local", connectedPeerIPv4: nil) == nil)
		#expect(WifiOTAHandoffAddress.resolve(providedHost: "Meshtastic.local", connectedPeerIPv4: "Meshtastic.local") == nil)
		#expect(WifiOTAHandoffAddress.resolve(providedHost: nil, connectedPeerIPv4: nil) == nil)
		#expect(WifiOTAHandoffAddress.resolve(providedHost: "fe80::1", connectedPeerIPv4: "::1") == nil)
	}

	@Test func endpointReaderKeepsOnlyAnIPv4Peer() {
		guard let ipv4Address = Network.IPv4Address("10.10.10.76") else {
			Issue.record("10.10.10.76 should parse as IPv4")
			return
		}
		let ipv4 = NWEndpoint.hostPort(host: .ipv4(ipv4Address), port: 3232)
		#expect(TCPConnection.ipv4Address(of: ipv4) == "10.10.10.76")

		// The name the firmware advertises. Reading it back would dial the wrong radio.
		let name = NWEndpoint.hostPort(host: NWEndpoint.Host("Meshtastic.local"), port: 3232)
		#expect(TCPConnection.ipv4Address(of: name) == nil)

		guard let ipv6Address = Network.IPv6Address("2001:db8::1") else {
			Issue.record("2001:db8::1 should parse as IPv6")
			return
		}
		let ipv6 = NWEndpoint.hostPort(host: .ipv6(ipv6Address), port: 3232)
		#expect(TCPConnection.ipv4Address(of: ipv6) == nil)
	}

	/// The address has to be the peer of the socket that is up, not the host string the
	/// connection was opened with. Before connect and after disconnect the host string is
	/// still an IPv4 literal, and the answer is still nil.
	@Test func connectedIPv4AddressIsTheLivePeer() async throws {
		let listener = try NWListener(using: .tcp, on: .any)
		defer { listener.cancel() }
		let port = try await Self.port(of: listener)

		let tcp = try await TCPConnection(host: "127.0.0.1", port: Int(port))
		#expect(await tcp.connectedIPv4Address() == nil)

		let stream = try await tcp.connect()
		#expect(await tcp.connectedIPv4Address() == "127.0.0.1")
		#expect(await tcp.host.stringValue == "127.0.0.1")

		try await tcp.disconnect(withError: nil, shouldReconnect: false)
		#expect(await tcp.connectedIPv4Address() == nil)
		withExtendedLifetime(stream) {}
	}

	/// Opening the socket with a name leaves that name on the connection. The peer address
	/// is whatever the socket actually used, which is not the name.
	@Test func connectedIPv4AddressDoesNotReturnTheConfiguredName() async throws {
		let listener = try NWListener(using: .tcp, on: .any)
		defer { listener.cancel() }
		let port = try await Self.port(of: listener)

		let tcp = try await TCPConnection(host: "localhost", port: Int(port))
		let stream = try await tcp.connect()
		let address = await tcp.connectedIPv4Address()
		#expect(await tcp.host.stringValue == "localhost")
		#expect(address != "localhost")
		// localhost is ::1 on some machines and 127.0.0.1 on others. An IPv6 peer is not an answer.
		#expect(address == nil || address == "127.0.0.1")
		try await tcp.disconnect(withError: nil, shouldReconnect: false)
		withExtendedLifetime(stream) {}
	}

	private static func port(of listener: NWListener) async throws -> UInt16 {
		try await withCheckedThrowingContinuation { continuation in
			let gate = ResumeGate()
			listener.stateUpdateHandler = { state in
				switch state {
				case .ready:
					gate.resume {
						continuation.resume(returning: listener.port?.rawValue ?? 0)
					}
				case .failed(let error):
					gate.resume {
						continuation.resume(throwing: error)
					}
				default:
					break
				}
			}
			listener.newConnectionHandler = { incoming in
				incoming.start(queue: .global())
			}
			listener.start(queue: .global())
			Task {
				try? await Task.sleep(for: .seconds(5))
				gate.resume {
					continuation.resume(throwing: CancellationError())
				}
			}
		}
	}
}

/// One-shot resume for an `NWListener` state callback. The listener queue is serial with
/// itself, but the timeout task is not, so the flag is locked.
private final class ResumeGate: @unchecked Sendable {
	private let lock = NSLock()
	private var resumed = false

	func resume(_ body: () -> Void) {
		lock.lock()
		let first = !resumed
		resumed = true
		lock.unlock()
		if first { body() }
	}
}

@Suite("Wi-Fi OTA manual host")
@MainActor
struct WifiOTAManualHostTests {

	@Test func aHostnameIsRejectedBeforeTheProbe() async throws {
		let model = ESP32WifiOTAViewModel()
		let task = Task {
			await model.startUpdate(host: "Meshtastic.local", firmwareUrl: URL(fileURLWithPath: "/tmp/unused-ota.bin"))
		}
		let deadline = ContinuousClock.now.advanced(by: .seconds(2))
		while ContinuousClock.now < deadline, model.otaState != .error {
			try await Task.sleep(for: .milliseconds(20))
		}
		task.cancel()
		await task.value

		#expect(model.otaState == .error)
		#expect(model.statusMessage == OTAError.missingIPv4Address)
		#expect(model.errorMessage == OTAError.missingIPv4Address)
	}

	@Test func anIPv4LiteralIsNotRejectedAsAName() async {
		let model = ESP32WifiOTAViewModel()
		let missing = FileManager.default.temporaryDirectory
			.appendingPathComponent("wifi-ota-missing-\(UUID().uuidString).bin")
		await model.startUpdate(host: "10.10.10.76", firmwareUrl: missing)
		#expect(model.statusMessage != OTAError.missingIPv4Address)
		#expect(model.otaState == .error)
	}
}
