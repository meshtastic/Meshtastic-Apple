import Foundation

struct RemoteAdminActionTarget: Equatable {
	let nodeNum: Int64
	let name: String
	let radioNum: Int64
	let connectionID: ObjectIdentifier
}

@MainActor
enum RemoteAdminActionGuard {
	static func run(
		target: RemoteAdminActionTarget,
		activeRadioNum: @escaping @MainActor () -> Int64?,
		activeConnectionID: @escaping @MainActor () -> ObjectIdentifier?,
		isConnected: @escaping @MainActor () -> Bool,
		hasLiveSession: @escaping @MainActor () -> Bool,
		action: @escaping @MainActor () async throws -> Void
	) async -> String? {
		guard isConnected(), activeRadioNum() == target.radioNum,
			  activeConnectionID() == target.connectionID else { return "Connection changed. Please try again." }
		guard hasLiveSession() else { return "Session expired for \(target.name). Refresh device metadata first." }
		do {
			try await action()
			return nil
		} catch {
			return error.localizedDescription
		}
	}
}
