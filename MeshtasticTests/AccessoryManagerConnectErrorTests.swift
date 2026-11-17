//
//  AccessoryManagerConnectErrorTests.swift
//  MeshtasticTests
//
//  A connection error goes to the connect process while it is running, and closes the
//  connection otherwise. Before #3029, an error that arrived after the connect steps finished,
//  but before the process was cleared, went to a process that no longer acted on it, and the
//  app stayed Subscribed on a dropped link.
//

import Foundation
import Testing

@testable import Meshtastic
import MeshtasticProtobufs

private actor StubConnection: Connection {
	let type: TransportType = .ble
	var isConnected = true

	func send(_ data: ToRadio) async throws {}
	func connect() async throws -> AsyncStream<ConnectionEvent> { AsyncStream { $0.finish() } }
	func disconnect(withError: Error?, shouldReconnect: Bool) async throws { isConnected = false }
	func drainPendingPackets() async throws {}
	func startDrainPendingPackets() throws {}
	func appDidEnterBackground() {}
	func appDidBecomeActive() {}
}

private actor StepLog {
	private(set) var entries: [String] = []

	func add(_ entry: String) {
		entries.append(entry)
	}
}

private struct LinkLost: Error {}

@MainActor
@Suite("AccessoryManager connect errors", .serialized, .timeLimit(.minutes(1)))
struct AccessoryManagerConnectErrorTests {
	private func makeManager() -> AccessoryManager {
		let manager = AccessoryManager(transports: [])
		let device = Device(
			id: UUID(),
			name: "Connect Error Test Radio",
			transportType: .ble,
			identifier: "connect-error-test-radio",
			connectionState: .connected
		)
		manager.activeConnection = (device: device, connection: StubConnection())
		// Keeps closeConnection() from restarting discovery.
		manager.isSwitchingDevices = true
		manager.context = PersistenceController.shared.context
		manager.updateState(.subscribed)
		return manager
	}

	/// didReceive handles the error in a Task of its own, so wait for what it does.
	private func waitUntil(_ condition: () async -> Bool) async {
		for _ in 0..<500 {
			if await condition() { return }
			try? await Task.sleep(for: .milliseconds(10))
		}
	}

	@Test func errorAfterTheStepsFinishedClosesTheConnection() async throws {
		let manager = makeManager()
		let stepper = SequentialSteps(maxRetries: 1, retryDelay: .milliseconds(1)) {
			Step { _ in }
		}
		try await stepper.run()
		// Finished, but not yet cleared by connect(to:).
		manager.connectionStepper = stepper

		await manager.didReceive(.error(LinkLost()))
		await waitUntil { manager.activeConnection == nil && manager.state == .discovering }

		#expect(manager.activeConnection == nil)
		#expect(manager.state == .discovering)
	}

	/// Passes before the fix too. Kept so the new close in didReceive never takes a connection
	/// from a connect process that is still retrying.
	@Test func errorWhileTheStepsRunGoesToTheConnectProcess() async throws {
		let manager = makeManager()
		let log = StepLog()
		let stepper = SequentialSteps(maxRetries: 2, retryDelay: .milliseconds(1)) {
			Step { attempt in
				await log.add("\(attempt):start")
				if attempt == 0 {
					// Waits for the link to drop; the error cancels the sleep.
					try await Task.sleep(for: .seconds(30))
				}
			}
		}
		manager.connectionStepper = stepper
		let run = Task { try await stepper.run() }
		await waitUntil { await log.entries == ["0:start"] }

		await manager.didReceive(.error(LinkLost()))
		try await run.value

		// The connect process retried, and the connection it owns was left to it.
		#expect(await log.entries == ["0:start", "1:start"])
		#expect(manager.activeConnection != nil)
	}
}
