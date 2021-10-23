import SwiftUI
import Foundation
import UniformTypeIdentifiers

struct MeshLog: View {
	let logFile = Logger.logFile
	var text = ""
	@State private var logs = [String]()
	@State private var isExporting: Bool = false
	@State private var document: LogDocument = LogDocument(logFile: "")
		
	var body: some View {

		List(logs, id: \.self, rowContent: Text.init)
			.task {
				do {
					
					let url = logFile!
					logs.removeAll()
					for try await log in url.lines {
						logs.append(log)
						document.logFile.append(log)
					}
					logs.reverse()
				} catch {
					// Stop adding logs when an error is thrown
				}
		}
		.fileExporter(isPresented: $isExporting,
					  document: document,
					  contentType: UTType.plainText,
					  defaultFilename: "mesh-activity-log"
		)
		{
			result in
			if case .success = result {
				print("Upload was ok")
			}
			else{
				print("Something went wrong")
			}
		}
		
		
		.textSelection(.enabled)
		.font(.caption2)
	
		HStack (alignment: .center) {
			Spacer()
			Button(action: {
				let text = ""
				do {
					 try text.write(to: logFile!, atomically: false, encoding: .utf8)
					 logs.removeAll()
				   } catch {
					 print(error)
				   }
				
			}) {
				Image(systemName: "trash").imageScale(.large).foregroundColor(.gray)
				Text("Clear Log").font(.caption)
				.font(.caption)
					.foregroundColor(.gray)
			}
			.padding()
			.background(Color(.systemGray6))
			.clipShape(Capsule())
			
			Spacer()
			
			Button(action: {
				isExporting = true
			}) {
				Image(systemName: "arrow.down.circle.fill").imageScale(.large).foregroundColor(.gray)
				Text("Download Log")
				.font(.caption)
				.foregroundColor(.gray)
			}
			.padding()
			.background(Color(.systemGray6))
			.clipShape(Capsule())
			
			Spacer()
			
		}
		.padding(.bottom, 10)
		.navigationTitle("Mesh Activity Log")
	}
}
