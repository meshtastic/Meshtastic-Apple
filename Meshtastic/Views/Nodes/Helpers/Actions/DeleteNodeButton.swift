import SwiftData
import OSLog
import SwiftUI

struct DeleteNodeButton: View {

	@Environment(\.modelContext) private var context
	@EnvironmentObject var accessoryManager: AccessoryManager

	var connectedNode: NodeInfoEntity
	var node: NodeInfoEntity
	@Environment(\.dismiss) private var dismiss
	@State private var isPresentingAlert = false

	var body: some View {
		if node.num != connectedNode.num {
			Button(role: .destructive) {
				isPresentingAlert = true
			} label: {
				Label {
					Text("Delete Node")
				} icon: {
					Image(systemName: "trash")
						.symbolRenderingMode(.multicolor)
				}
			}
			.alert(
				"Are you sure?",
				isPresented: $isPresentingAlert
			) {
				Button("OK") {	}.keyboardShortcut(.defaultAction)
			} message: {
				Text("Delete Node?")
			}
			.confirmationDialog(
				"Are you sure?",
				isPresented: $isPresentingAlert,
				titleVisibility: .visible
			) {
				Button("Delete Node", role: .destructive) {
					guard let deleteNode = getNodeInfo(
						id: node.num,
						context: context
					) else {
						Logger.data.error("Unable to find node info to delete node \(node.num, privacy: .public)")
						return
					}

					Task {
						do {
							try await accessoryManager.removeNode(
								node: deleteNode,
								connectedNodeNum: connectedNode.num
							)
							Task {@MainActor in
								dismiss()
							}
						} catch {
							Logger.data.error("Failed to delete node \(deleteNode.user?.longName ?? "Unknown".localized, privacy: .public)")
						}
					}
				}
			}
		}
	}
}

// TODO: Fix preview for SwiftData
/*
#Preview {
	let connectedNode = NodeInfoEntity()
	connectedNode.num = 987654321
	let node = NodeInfoEntity()
	node.num = 123456789
	DeleteNodeButton(connectedNode: connectedNode, node: node)
		.environmentObject(AccessoryManager.shared)
		.modelContainer(PersistenceController.preview.container)
}
*/
