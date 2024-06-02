import Foundation

class MeshLogger {

	static var logFile: URL? {
		guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
		let fileName = "mesh.log"
		return documentsDirectory.appendingPathComponent(fileName)
	}

	static func log(_ message: String) {
		guard let logFile = logFile else {
			return
		}
		let localeDateFormat = DateFormatter.dateFormat(fromTemplate: "yyMMddjmmssSSa", options: 0, locale: Locale.current)
		let dateFormatString = (localeDateFormat ?? "MM/dd/YY j:mm:ss.SS a")

		let formatter = DateFormatter()
		formatter.dateFormat = dateFormatString
		let timestamp = formatter.string(from: Date())
		guard let data = (message + " - " + timestamp + "\n").data(using: String.Encoding.utf8) else {
			logger.error("Unable to create log data")
			return
		}

		do {
			if FileManager.default.fileExists(atPath: logFile.path) {
				let fileHandle = try FileHandle(forWritingTo: logFile)
				fileHandle.seekToEndOfFile()
				fileHandle.write(data)
				fileHandle.closeFile()
			} else {
				try data.write(to: logFile, options: .atomicWrite)
			}
		} catch {
			logger.error("Error writing log data: \(error.localizedDescription)")
		}
	}
}
