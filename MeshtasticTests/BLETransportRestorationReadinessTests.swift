import Testing

@testable import Meshtastic

private actor RestorationCompletionRecorder {
	private(set) var didComplete = false

	func recordCompletion() {
		didComplete = true
	}
}

private actor RestorationReadinessGate {
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

	@Test("Restoration remains suspended until persistence is ready")
	func restorationWaitsForPersistence() async {
		let gate = RestorationReadinessGate()
		let completionRecorder = RestorationCompletionRecorder()
		let transport = BLETransport(
			createCentralManagerImmediately: false,
			persistenceReadiness: { await gate.wait() }
		)
		let restoration = Task {
			let result = await transport.waitForPersistenceBeforeRestoration()
			await completionRecorder.recordCompletion()
			return result
		}

		while !(await gate.isWaiting) {
			await Task.yield()
		}
		#expect(await gate.isWaiting)
		#expect(!(await completionRecorder.didComplete))

		await gate.open()
		#expect(await restoration.value)
		#expect(await completionRecorder.didComplete)
	}

	@Test("Restoration stops after a terminal persistence failure")
	func restorationStopsAfterFailure() async {
		struct TestError: Error {}
		let transport = BLETransport(
			createCentralManagerImmediately: false,
			persistenceReadiness: { throw TestError() }
		)

		#expect(!(await transport.waitForPersistenceBeforeRestoration()))
	}
}
