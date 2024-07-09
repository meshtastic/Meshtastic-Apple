import SwiftUI

struct ClientHistoryButton: View {
	var bleManager: BLEManager

	var connectedNode: NodeInfoEntity

	var node: NodeInfoEntity

	@State
	private var isPresentingAlert = false

    var body: some View {
		Button {
			isPresentingAlert = bleManager.requestStoreAndForwardClientHistory(
				fromUser: connectedNode.user!,
				toUser: node.user!
			)
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
