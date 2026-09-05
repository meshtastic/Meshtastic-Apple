import Foundation

struct RemoteAdminActionTarget: Equatable {
	let nodeNum: Int64
	let name: String
	let radioNum: Int64
	let connectionID: ObjectIdentifier

	var confirmationLabel: String { "\(name) (node \(nodeNum))" }

	func factoryResetConfirmationMessage(resetDevice: Bool) -> String {
		if resetDevice {
			return "This irreversibly erases \(confirmationLabel)'s configuration, identity, admin keys, channels, and Bluetooth bonds. This cannot be undone."
		}
		return "This irreversibly erases \(confirmationLabel)'s configuration. This cannot be undone."
	}

	func nodeDBResetConfirmationMessage(preserveFavorites: Bool) -> String {
		if preserveFavorites {
			return "This irreversibly resets \(confirmationLabel)'s node database while preserving favorites. This cannot be undone."
		}
		return "This irreversibly erases \(confirmationLabel)'s node database and favorites. This cannot be undone."
	}
}

enum RemoteAdminActionResult: Equatable {
	case acknowledged
	case verified
	case unconfirmed
	case failed(String)
}

@MainActor
enum RemoteAdminActionGuard {
	private static func validate(
		target: RemoteAdminActionTarget,
		activeRadioNum: @escaping @MainActor () -> Int64?,
		activeConnectionID: @escaping @MainActor () -> ObjectIdentifier?,
		isConnected: @escaping @MainActor () -> Bool,
		hasLiveSession: @escaping @MainActor () -> Bool
	) -> String? {
		guard isConnected(), activeRadioNum() == target.radioNum,
			  activeConnectionID() == target.connectionID else { return "Connection changed. Please try again." }
		guard hasLiveSession() else { return "Session expired for \(target.name). Refresh device metadata first." }
		return nil
	}

	static func run(
		target: RemoteAdminActionTarget,
		activeRadioNum: @escaping @MainActor () -> Int64?,
		activeConnectionID: @escaping @MainActor () -> ObjectIdentifier?,
		isConnected: @escaping @MainActor () -> Bool,
		hasLiveSession: @escaping @MainActor () -> Bool,
		action: @escaping @MainActor () async throws -> Void
	) async -> String? {
		if let error = validate(
			target: target,
			activeRadioNum: activeRadioNum,
			activeConnectionID: activeConnectionID,
			isConnected: isConnected,
			hasLiveSession: hasLiveSession) { return error }
		do {
			try await action()
			return nil
		} catch {
			return error.localizedDescription
		}
	}

	static func runOutcome(
		target: RemoteAdminActionTarget,
		activeRadioNum: @escaping @MainActor () -> Int64?,
		activeConnectionID: @escaping @MainActor () -> ObjectIdentifier?,
		isConnected: @escaping @MainActor () -> Bool,
		hasLiveSession: @escaping @MainActor () -> Bool,
		action: @escaping @MainActor () async throws -> RemoteAdminActionResult
	) async -> RemoteAdminActionResult {
		if let error = validate(
			target: target,
			activeRadioNum: activeRadioNum,
			activeConnectionID: activeConnectionID,
			isConnected: isConnected,
			hasLiveSession: hasLiveSession) { return .failed(error) }
		do {
			return try await action()
		} catch {
			return .failed(error.localizedDescription)
		}
	}
}
