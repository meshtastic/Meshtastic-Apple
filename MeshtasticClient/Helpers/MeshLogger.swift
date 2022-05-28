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

		let formatter = DateFormatter()
		formatter.dateFormat = "M/d/yy h:mm:ss.SSSS"
		let timestamp = formatter.string(from: Date())
		guard let data = (message + " - " + timestamp + "\n").data(using: String.Encoding.utf8) else { return }
		print(message)

		if FileManager.default.fileExists(atPath: logFile.path) {
			if let fileHandle = try? FileHandle(forWritingTo: logFile) {
				fileHandle.seekToEndOfFile()
				fileHandle.write(data)
				fileHandle.closeFile()
			}
		} else {
			try? data.write(to: logFile, options: .atomicWrite)
		}
	}
}
