import SwiftData
import SwiftUI
import OSLog

struct ExchangeUserInfoButton: View {
	var node: NodeInfoEntity
	var connectedNode: NodeInfoEntity

	@EnvironmentObject var accessoryManager: AccessoryManager

	@State private var isPresentingUserInfoSentAlert: Bool = false
	@State private var isPresentingUserInfoFailedAlert: Bool = false

	var body: some View {
		Button {
			Task {
				if let fromUser = connectedNode.user, let toUser = node.user {
					do {
						_ = try await accessoryManager.exchangeUserInfo(fromUser: fromUser, toUser: toUser)
						Task { @MainActor in
							isPresentingUserInfoSentAlert = true
							DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
								isPresentingUserInfoSentAlert = false
							}
						}
					} catch {
						Logger.mesh.warning("Failed to exchange user info")
						Task { @MainActor in
							isPresentingUserInfoFailedAlert = true
							DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
								isPresentingUserInfoFailedAlert = false
							}
						}
					}
				}
			}

		} label: {
			Label {
				Text("Exchange User Info")
			} icon: {
				Image(systemName: "person.2.badge.gearshape")
					.symbolRenderingMode(.hierarchical)
			}
		}.alert(
			"User Info Sent",
			isPresented: $isPresentingUserInfoSentAlert
		) {
			Button("OK") {	}.keyboardShortcut(.defaultAction)
		} message: {
			Text("Your user info has been sent with a request for a response with their user info.")
		}.alert(
			"User Info Exchange Failed",
			isPresented: $isPresentingUserInfoFailedAlert
		) {
			Button("OK") {	}.keyboardShortcut(.defaultAction)
		} message: {
			Text("Failed to exchange user info.")
		}
	}
}

// TODO: Fix preview for SwiftData
/*
#Preview {
	let node = NodeInfoEntity()
	node.num = 123456789
	let connectedNode = NodeInfoEntity()
	connectedNode.num = 987654321
	ExchangeUserInfoButton(node: node, connectedNode: connectedNode)
		.environmentObject(AccessoryManager.shared)
}
*/
