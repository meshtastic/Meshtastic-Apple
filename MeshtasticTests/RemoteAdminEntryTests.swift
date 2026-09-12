import Foundation
import Testing

@testable import Meshtastic

@Suite("Remote admin entry")
struct RemoteAdminEntryTests {

	@Test @MainActor func orchestrator_disabledSendsZero() async {
		var sends = 0
		let result = await RemoteAdminSessionOrchestrator.establish(allowed: { false }, attemptIsCurrent: { true }, fresh: { false }, request: { sends += 1 }, wait: { .active })
		#expect(result == .requestFailed)
		#expect(sends == 0)
	}

	@Test @MainActor func orchestrator_freshSessionSendsZero() async {
		var sends = 0
		let result = await RemoteAdminSessionOrchestrator.establish(allowed: { true }, attemptIsCurrent: { true }, fresh: { true }, request: { sends += 1 }, wait: { .active })
		#expect(result == .active)
		#expect(sends == 0)
	}

	@Test @MainActor func orchestrator_staleSessionSendsAndWaits() async {
		var sends = 0
		var waits = 0
		var fresh = false
		let result = await RemoteAdminSessionOrchestrator.establish(allowed: { true }, attemptIsCurrent: { true }, fresh: { fresh }, request: { sends += 1; fresh = true }, wait: { waits += 1; return fresh ? .active : .timedOut })
		#expect(result == .active)
		#expect(sends == 1)
		#expect(waits == 1)
	}

	@Test @MainActor func orchestrator_identityChangeAfterSendCannotActivate() async {
		var current = true
		let result = await RemoteAdminSessionOrchestrator.establish(allowed: { true }, attemptIsCurrent: { current }, fresh: { false }, request: { current = false }, wait: { .active })
		#expect(result == .targetChanged)
	}

	@Test @MainActor func orchestrator_sendErrorIsRequestFailed() async {
		struct SendError: Error {}
		let result = await RemoteAdminSessionOrchestrator.establish(allowed: { true }, attemptIsCurrent: { true }, fresh: { false }, request: { throw SendError() }, wait: { .active })
		#expect(result == .requestFailed)
	}

	@Test @MainActor func orchestrator_cancelledSendDoesNotActivate() async {
		let result = await RemoteAdminSessionOrchestrator.establish(allowed: { true }, attemptIsCurrent: { true }, fresh: { false }, request: { throw CancellationError() }, wait: { .active })
		#expect(result == .cancelled)
	}

	@Test @MainActor func orchestrator_postWaitIdentityChangeCannotActivate() async {
		var current = true
		let result = await RemoteAdminSessionOrchestrator.establish(allowed: { true }, attemptIsCurrent: { current }, fresh: { false }, request: {}, wait: { current = false; return .active })
		#expect(result == .targetChanged)
	}

	@Test @MainActor func orchestrator_postWaitDisableCannotActivate() async {
		var allowed = true
		let result = await RemoteAdminSessionOrchestrator.establish(allowed: { allowed }, attemptIsCurrent: { true }, fresh: { false }, request: {}, wait: { allowed = false; return .active })
		#expect(result == .requestFailed)
	}

	@Test @MainActor func sameRadioWithReplacementConnectionCannotActivate() async {
		let initial = NSObject()
		let replacement = NSObject()
		let capturedID = ObjectIdentifier(initial)
		var connectionID = capturedID
		let radioNum = 42
		let result = await RemoteAdminSessionOrchestrator.establish(
			allowed: { true },
			attemptIsCurrent: { radioNum == 42 && connectionID == capturedID },
			fresh: { false },
			request: { connectionID = ObjectIdentifier(replacement) },
			wait: { .active }
		)
		#expect(result == .targetChanged)
	}

	@Test func sessionFreshness_requiresPasskeyAndFutureExpiration() {
		let now = Date(timeIntervalSince1970: 100)
		#expect(RemoteAdminSessionFreshness.isFresh(passkey: Data([1]), expiration: now.addingTimeInterval(1), now: now))
		#expect(!RemoteAdminSessionFreshness.isFresh(passkey: nil, expiration: now.addingTimeInterval(1), now: now))
		#expect(!RemoteAdminSessionFreshness.isFresh(passkey: Data(), expiration: now.addingTimeInterval(1), now: now))
		#expect(!RemoteAdminSessionFreshness.isFresh(passkey: Data([1]), expiration: now, now: now.addingTimeInterval(1)))
	}

	@Test func sessionWaiter_timesOutWhenResponseNeverArrives() async {
		let result = await RemoteAdminSessionWaiter.wait(
			timeout: .milliseconds(1),
			pollInterval: .milliseconds(1),
			isLive: { false },
			isConnected: { true },
			targetIsCurrent: { true },
			sleep: { _ in }
		)
		#expect(result == .timedOut)
	}

	@Test func sessionWaiter_stopsWhenConnectionDrops() async {
		let result = await RemoteAdminSessionWaiter.wait(
			timeout: .seconds(30),
			pollInterval: .milliseconds(1),
			isLive: { false },
			isConnected: { false },
			targetIsCurrent: { true }
		)
		#expect(result == .disconnected)
	}

	@Test func sessionWaiter_stopsWhenTargetChanges() async {
		let result = await RemoteAdminSessionWaiter.wait(
			timeout: .seconds(30),
			pollInterval: .milliseconds(1),
			isLive: { false },
			isConnected: { true },
			targetIsCurrent: { false }
		)
		#expect(result == .targetChanged)
	}

	@Test func sessionWaiter_rejectsNonPositivePollInterval() async {
		let result = await RemoteAdminSessionWaiter.wait(
			timeout: .seconds(30),
			pollInterval: .zero,
			isLive: { false },
			isConnected: { true },
			targetIsCurrent: { true }
		)
		#expect(result == .timedOut)
	}

	@Test @MainActor func remoteSettingsSelectionRequiresActiveDevice() {
		#expect(Settings.remoteSettingsSelection(
			requestedNodeNum: 42,
			activeDeviceNum: nil,
			availableNodeNums: [42],
			isConnected: true
		) == nil)
		#expect(Settings.remoteSettingsSelection(
			requestedNodeNum: 42,
			activeDeviceNum: 7,
			availableNodeNums: [42],
			isConnected: true
		)?.preferredNodeNum == 7)
	}
	@Test func remoteSettingsDestinationRejectsSourceReplacement() {
		let connection = NSObject()
		let replacement = NSObject()
		let destination = RemoteAdminSettingsDestination(nodeNum: 42, radioNum: 7, connectionID: ObjectIdentifier(connection))
		#expect(destination.isCurrent(radioNum: 7, connectionID: ObjectIdentifier(connection), isConnected: true))
		#expect(!destination.isCurrent(radioNum: 8, connectionID: ObjectIdentifier(connection), isConnected: true))
		#expect(!destination.isCurrent(radioNum: 7, connectionID: ObjectIdentifier(replacement), isConnected: true))
		#expect(!destination.isCurrent(radioNum: 7, connectionID: ObjectIdentifier(connection), isConnected: false))
	}
}
