import SwiftUI
import Foundation
import UniformTypeIdentifiers

struct MeshLog: View {
	let logFile = MeshLogger.logFile
	var text = ""
	@State private var logs = [String]()
	@State private var isExporting: Bool = false
	@State private var document: LogDocument = LogDocument(logFile: "MESHTASTIC MESH ACTIVITY LOG\n")

	var body: some View {

		List(logs, id: \.self, rowContent: Text.init)
			.task {
				do {

					let url = logFile!
					logs.removeAll()
					
					var lineCount = 0
					let lineLimit = 500
					
					// Get the number of lines
					for try await _ in url.lines {
						lineCount += 1
					}
					
					var startingLog = 0
					// Set the record to start with if we have more lines than the limit
					if lineCount > lineLimit {
						startingLog = lineCount - lineLimit
					}
					
					var lineNumber = 0
					
					for try await log in url.lines {
						if lineNumber >= startingLog {
							
							logs.append(log)
							document.logFile.append("\(log) \n")
					   }
					   lineNumber += 1
				   }
				   logs.reverse()

				} catch {
					// Stop adding logs when an error is thrown
				}
		}
		.fileExporter(
			isPresented: $isExporting,
			document: document,
			contentType: UTType.plainText,
			defaultFilename: "mesh-activity-log",
			onCompletion: { result in

				if case .success = result {
					print("Mesh activity log download: success.")
				} else {
					print("Mesh activity log download \(result).")
				}
			}
		)

		.textSelection(.enabled)
		.font(.caption)

		HStack(alignment: .center) {
			Spacer()
			
			Button(role: .destructive) {
							
				let text = ""
				do {
					 try text.write(to: logFile!, atomically: false, encoding: .utf8)
					 logs.removeAll()
				   } catch {
					 print(error)
				   }
				
			} label: {
				
				Label("Clear Log", systemImage: "trash.fill")
			}
			.buttonStyle(.bordered)
			.buttonBorderShape(.capsule)
			.controlSize(.large)
			.padding()

			Spacer()
			
			Button {
							
				isExporting = true
				
			} label: {
				
				Label("Save Log", systemImage: "square.and.arrow.down")
			}
			.buttonStyle(.bordered)
			.buttonBorderShape(.capsule)
			.controlSize(.large)
			.padding()
			
			Spacer()

		}
		.padding(.bottom, 10)
		.navigationTitle("Mesh Activity Log")
	}
}
