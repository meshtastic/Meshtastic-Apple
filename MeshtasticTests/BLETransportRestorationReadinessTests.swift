import Testing

@testable import Meshtastic

private actor RestorationCompletionRecorder {
	private(set) var didComplete = false

	func recordCompletion() {
		didComplete = true
	}
}

private actor RestorationBootstrapGate {
	private var continuation: CheckedContinuation<Void, Never>?
	private(set) var isWaiting = false

	func wait() async {
		await withCheckedContinuation { continuation in
			isWaiting = true
			self.continuation = continuation
		}
	}

	func open() {
		continuation?.resume()
		continuation = nil
		isWaiting = false
	}
}

@Suite("BLE restoration readiness")
struct BLETransportRestorationReadinessTests {

	@Test("Restoration waits for persistence bootstrap")
	func restorationWaitsForPersistenceBootstrap() async {
		let gate = RestorationBootstrapGate()
		let completionRecorder = RestorationCompletionRecorder()
		let transport = BLETransport(
			createCentralManagerImmediately: false,
			persistenceBootstrap: { await gate.wait() }
		)
		let restoration = Task {
			await transport.handleWillRestoreState(dict: [:], central: nil)
			await completionRecorder.recordCompletion()
		}

		var bootstrapStarted = await gate.isWaiting
		for _ in 0..<1_000 where !bootstrapStarted {
			await Task.yield()
			bootstrapStarted = await gate.isWaiting
		}
		#expect(bootstrapStarted)
		#expect(!(await completionRecorder.didComplete))

		await gate.open()
		await restoration.value
		#expect(await completionRecorder.didComplete)
	}
}
