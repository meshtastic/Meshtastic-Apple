import SwiftUI
import Foundation

struct MeshLog: View {
	let logFile = Logger.logFile
	var text = ""
	@State private var logs = [String]()
		
	var body: some View {

		List(logs, id: \.self, rowContent: Text.init)
			.task {
				do {
					
					let url = logFile!
					logs.removeAll()
					for try await log in url.lines {
						logs.append(log)
					}
					logs.reverse()
				} catch {
					// Stop adding logs when an error is thrown
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
				
			}) {
				Image(systemName: "arrow.down.circle.fill").imageScale(.large).foregroundColor(.gray)
				Text("Download Log")
				.font(.caption)
				.foregroundColor(.gray)
			}
			.padding()
			.background(Color(.systemGray6))
			.clipShape(Capsule())
			.hidden()
			
			Spacer()
			
		}
		.padding(.bottom, 10)
		.navigationTitle("Mesh Activity Log")
	}
}
