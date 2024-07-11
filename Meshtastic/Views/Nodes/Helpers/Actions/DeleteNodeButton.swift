import CoreData
import OSLog
import SwiftUI

struct DeleteNodeButton: View {
	var bleManager: BLEManager

	var context: NSManagedObjectContext

	var connectedNode: NodeInfoEntity

	var node: NodeInfoEntity
	
	@EnvironmentObject
	var queryCoreDataController: QueryCoreDataController

	@State
	private var isPresentingAlert = false

    var body: some View {
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
		.confirmationDialog(
			"are.you.sure",
			isPresented: $isPresentingAlert,
			titleVisibility: .visible
		) {
			Button("Delete Node", role: .destructive) {
				guard let deleteNode = queryCoreDataController.getNodeInfo(id: node.num) else {
					Logger.data.error("Unable to find node info to delete node \(node.num)")
					return
				}
				let success = bleManager.removeNode(
					node: deleteNode,
					connectedNodeNum: connectedNode.num
				)
				if !success {
					Logger.data.error("Failed to delete node \(deleteNode.user?.longName ?? "unknown".localized)")
				}
			}
		}
    }
}
