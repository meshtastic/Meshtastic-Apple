import OSLog

extension Logger {

	/// The logger's subsystem.
	private static var subsystem = Bundle.main.bundleIdentifier!

	/// All logs related to data such as decoding error, parsing issues, etc.
	public static let data = Logger(subsystem: subsystem, category: "🗄️ Data")

	/// All logs related to the mesh
	public static let mesh = Logger(subsystem: subsystem, category: "🕸️ Mesh")

	/// All logs related to services such as network calls, location, etc.
	public static let services = Logger(subsystem: subsystem, category: "🍏 Services")

	/// All logs related to tracking and analytics.
	public static let statistics = Logger(subsystem: subsystem, category: "📈 Stats")
}
