import OSLog

final class MeshLogger {
	static func log(_ message: String) {
		Logger.mesh.notice("\(message, privacy: .public)")
	}
}
