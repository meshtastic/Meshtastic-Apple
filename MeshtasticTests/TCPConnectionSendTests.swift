// TCPConnectionSendTests.swift
// MeshtasticTests

import Testing
import Foundation
import MeshtasticProtobufs
@testable import Meshtastic

/// Records whether the task under test ever finished, so the test can time out and fail
/// instead of hanging when the task never resumes.
private actor CompletionFlag {
	private var finished = false
	func markFinished() { finished = true }
	func isFinished() -> Bool { finished }
}

@Suite("TCPConnection send when not connected")
struct TCPConnectionSendTests {

	/// `TCPConnection.send` used to call `connection?.send(...)` inside the continuation body.
	/// With `connection == nil` (any time after `disconnect()`, which nils it) that whole
	/// statement was a no-op: the continuation was created, never handed to a completion
	/// handler, and never resumed. There is no cancellation handler on that continuation
	/// either, so the caller parked forever and could not be cancelled out of it. Both real
	/// callers run with `timeout: nil`, so the connect sequence never returned.
	///
	/// Against the unfixed code this test times out at the 3s deadline and fails. Against the
	/// fixed code `send` throws `AccessoryError.disconnected` promptly.
	@Test func send_whenNotConnected_throwsPromptlyInsteadOfHanging() async throws {
		// Never connected, so `connection` is nil — the same state `disconnect()` leaves behind.
		let connection = try await TCPConnection(host: "127.0.0.1", port: 4403)

		var toRadio = ToRadio()
		toRadio.wantConfigID = 1

		let flag = CompletionFlag()
		let sendTask = Task { () -> Error? in
			do {
				try await connection.send(toRadio)
				await flag.markFinished()
				return nil
			} catch {
				await flag.markFinished()
				return error
			}
		}

		let deadline = Date().addingTimeInterval(3)
		var finished = false
		while Date() < deadline {
			if await flag.isFinished() {
				finished = true
				break
			}
			try await Task.sleep(for: .milliseconds(25))
		}

		guard finished else {
			// Leave the task parked; the process is about to end anyway. Cancelling it would
			// not help — a continuation with no cancellation handler ignores cancellation.
			Issue.record("send() never returned when connection was nil; it is hanging on an unresumed continuation")
			return
		}

		let thrown = await sendTask.value
		guard let accessoryError = thrown as? AccessoryError, case .disconnected = accessoryError else {
			Issue.record("Expected AccessoryError.disconnected, got \(String(describing: thrown))")
			return
		}
	}
}
