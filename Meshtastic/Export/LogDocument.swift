import SwiftUI
import UniformTypeIdentifiers

struct LogDocument: FileDocument {
	static var readableContentTypes: [UTType] {[.plainText]}

	var logFile: String

	init(logFile: String) {
		self.logFile = logFile
	}

	init(configuration: ReadConfiguration) throws {
		guard let data = configuration.file.regularFileContents else {
			throw CocoaError(.fileReadCorruptFile)
		}
		logFile = String(decoding: data, as: UTF8.self)
	}

	func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
		return FileWrapper(regularFileWithContents: logFile.data(using: .utf8)!)
	}
}
