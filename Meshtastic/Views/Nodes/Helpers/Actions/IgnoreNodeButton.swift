import CoreData
import OSLog
import SwiftUI

struct IgnoreNodeButton: View {
	var bleManager: BLEManager
	var context: NSManagedObjectContext

	@ObservedObject
	var node: NodeInfoEntity

	var body: some View {
		Button(role: .destructive) {
			guard let connectedNodeNum = bleManager.connectedPeripheral?.num else { return }
			let success = if node.ignored {
				bleManager.removeIgnoredNode(
					node: node,
					connectedNodeNum: Int64(connectedNodeNum)
				)
			} else {
				bleManager.setIgnoredNode(
					node: node,
					connectedNodeNum: Int64(connectedNodeNum)
				)
			}
			if success {
				node.ignored = !node.ignored
				do {
					try context.save()
				} catch {
					context.rollback()
					Logger.data.error("Save Ignored Node Error")
				}
				Logger.data.debug("Ignored a node")
			}
		} label: {
			Label {
				Text(node.ignored ? "Remove from ignored" : "Ignore Node")
			} icon: {
				Image(systemName: node.ignored ? "minus.circle.fill" : "minus.circle")
					.symbolRenderingMode(.multicolor)
			}
		}
	}
}
