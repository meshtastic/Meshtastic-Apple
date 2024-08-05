import CoreData
import OSLog
import SwiftUI

struct DeleteNodeButton: View {

	var bleManager: BLEManager
	var context: NSManagedObjectContext
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
				"are.you.sure",
				isPresented: $isPresentingAlert
			) {
				Button("OK") {	}.keyboardShortcut(.defaultAction)
			} message: {
				Text("Delete Node?")
			}
			.confirmationDialog(
				"are.you.sure",
				isPresented: $isPresentingAlert,
				titleVisibility: .visible
			) {
				Button("Delete Node", role: .destructive) {
					guard let deleteNode = getNodeInfo(
						id: node.num,
						context: context
					) else {
						Logger.data.error("Unable to find node info to delete node \(node.num)")
						return
					}
					let success = bleManager.removeNode(
						node: deleteNode,
						connectedNodeNum: connectedNode.num
					)
					if !success {
						Logger.data.error("Failed to delete node \(deleteNode.user?.longName ?? "unknown".localized)")
					} else {
						dismiss()
					}
				}
			}
		}
	}
}
