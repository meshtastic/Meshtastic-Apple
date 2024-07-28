import SwiftUI
import UniformTypeIdentifiers

struct LogDocument: FileDocument {
	static var readableContentTypes: [UTType] {[.plainText]}

	var logFile: String

	init(logFile: String) {
		self.logFile = logFile
	}

	init(configuration: ReadConfiguration) throws {
		guard let data = configuration.file.regularFileContents,
			  let string = String(data: data, encoding: .utf8)
		else {
			throw CocoaError(.fileReadCorruptFile)
		}
		logFile = string
	}

	func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
		return FileWrapper(regularFileWithContents: logFile.data(using: .utf8)!)
	}
}
