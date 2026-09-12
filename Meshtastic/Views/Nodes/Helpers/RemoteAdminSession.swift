//
//  RemoteAdminSession.swift
//  Meshtastic
//
//  Coordinates remote administration session state and confirmation waits.
//

import Foundation

// MARK: - Session State

enum RemoteAdminSessionState: Equatable {
	case stale
	case establishing
	case active
	case failed(RemoteAdminSessionWaiter.Result)
}

// MARK: - Session Freshness

enum RemoteAdminSessionFreshness {
	static func isFresh(passkey: Data?, expiration: Date?, now: Date = Date()) -> Bool {
		guard let passkey, !passkey.isEmpty, let expiration else { return false }
		return expiration >= now
	}
}

// MARK: - Session Waiter

enum RemoteAdminSessionWaiter {
	enum Result: Equatable {
		case active
		case timedOut
		case disconnected
		case targetChanged
		case cancelled
		case requestFailed
	}

	static func description(for result: Result) -> String {
		switch result {
		case .active: return "active"
		case .timedOut: return "timed out"
		case .disconnected: return "disconnected"
		case .targetChanged: return "target changed"
		case .cancelled: return "cancelled"
		case .requestFailed: return "request failed"
		}
	}

	@MainActor static func wait(
		timeout: Duration = .seconds(30),
		pollInterval: Duration = .milliseconds(200),
		isLive: @escaping @MainActor () -> Bool,
		isConnected: @escaping @MainActor () -> Bool,
		targetIsCurrent: @escaping @MainActor () -> Bool,
		sleep: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
	) async -> Result {
		guard pollInterval > .zero else { return .timedOut }
		var elapsed = Duration.zero
		while true {
			if Task.isCancelled { return .cancelled }
			if !isConnected() { return .disconnected }
			if !targetIsCurrent() { return .targetChanged }
			if isLive() { return .active }
			if elapsed >= timeout { return .timedOut }
			do {
				let delay = min(pollInterval, timeout - elapsed)
				try await sleep(delay)
				elapsed += delay
			} catch {
				return .cancelled
			}
		}
	}
}

// MARK: - Session Orchestration

enum RemoteAdminSessionOrchestrator {
	@MainActor
	static func establish(
		allowed: @escaping @MainActor () -> Bool,
		attemptIsCurrent: @escaping @MainActor () -> Bool,
		fresh: @escaping @MainActor () -> Bool,
		request: @escaping @MainActor () async throws -> Void,
		wait: @escaping @MainActor () async -> RemoteAdminSessionWaiter.Result
	) async -> RemoteAdminSessionWaiter.Result {
		guard allowed() else { return .requestFailed }
		guard !fresh() else { return .active }
		guard attemptIsCurrent() else { return .targetChanged }
		do {
			try await request()
		} catch is CancellationError {
			return .cancelled
		} catch {
			return .requestFailed
		}
		guard attemptIsCurrent() else { return .targetChanged }
		let result = await wait()
		guard result == .active else { return result }
		guard allowed() else { return .requestFailed }
		guard attemptIsCurrent() else { return .targetChanged }
		return .active
	}
}

// MARK: - Settings Destination

struct RemoteAdminSettingsDestination {
	let nodeNum: Int64
	let radioNum: Int64
	let connectionID: ObjectIdentifier

	func isCurrent(radioNum: Int64?, connectionID: ObjectIdentifier?, isConnected: Bool) -> Bool {
		isConnected && radioNum == self.radioNum && connectionID == self.connectionID
	}
}
