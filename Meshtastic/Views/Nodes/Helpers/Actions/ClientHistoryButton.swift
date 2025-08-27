import SwiftUI
import OSLog
struct ClientHistoryButton: View {
	@EnvironmentObject var accessoryManager: AccessoryManager

	var connectedNode: NodeInfoEntity

	var node: NodeInfoEntity

	@State
	private var isPresentingAlert = false

    var body: some View {
		Button {
			Task {
				do {
					try await accessoryManager.requestStoreAndForwardClientHistory(
						fromUser: connectedNode.user!,
						toUser: node.user!
					)
					Task { @MainActor in
						isPresentingAlert = true
					}
				} catch {
					Logger.mesh.warning("Failed to send client history request: \(error)")
				}
			}
		} label: {
			Label(
				"Client History",
				systemImage: "envelope.arrow.triangle.branch"
			)
		}.alert(
			"Client History Request Sent",
			isPresented: $isPresentingAlert
		) {
			Button("OK") {  }.keyboardShortcut(.defaultAction)
		} message: {
			Text("Any missed messages will be delivered again.")
		}
    }
}
