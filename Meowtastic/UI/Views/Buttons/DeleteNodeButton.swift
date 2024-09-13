import CoreData
import OSLog
import SwiftUI

struct DeleteNodeButton: View {
	var node: NodeInfoEntity
	var nodeConfig: NodeConfig
	var connectedNode: NodeInfoEntity
	var context: NSManagedObjectContext

	private let coreDataTools = CoreDataTools()

	@State
	private var isPresentingAlert = false

	@ViewBuilder
	var body: some View {
		Button(role: .destructive) {
			isPresentingAlert = true
		} label: {
			Label {
				Text("Delete Node")
			} icon: {
				Image(systemName: "trash")
					.symbolRenderingMode(.monochrome)
			}
		}
		.confirmationDialog(
			"Are you sure?",
			isPresented: $isPresentingAlert,
			titleVisibility: .visible
		) {
			Button("Delete Node", role: .destructive) {
				guard let nodeToDelete = coreDataTools.getNodeInfo(id: node.num, context: context) else {
					return
				}

				nodeConfig.removeNode(
					node: nodeToDelete,
					connectedNodeNum: connectedNode.num
				)
			}
		}
	}
}
