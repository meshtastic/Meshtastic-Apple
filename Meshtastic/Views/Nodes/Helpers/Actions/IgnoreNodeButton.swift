import CoreData
import OSLog
import SwiftUI

struct IgnoreNodeButton: View {
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var accessoryManager: AccessoryManager

	@ObservedObject
	var node: NodeInfoEntity

	var body: some View {
		Button(role: .destructive) {
			guard let connectedNodeNum = accessoryManager.activeDeviceNum else { return }
			Task {
				do {
					if node.ignored {
						try await accessoryManager.removeIgnoredNode(
							node: node,
							connectedNodeNum: Int64(connectedNodeNum)
						)
					} else {
						try await accessoryManager.setIgnoredNode(
							node: node,
							connectedNodeNum: Int64(connectedNodeNum)
						)
					}
					Task {@MainActor in
						// CoreData Stuff
						node.ignored = !node.ignored
						do {
							try context.save()
						} catch {
							context.rollback()
							Logger.data.error("Save Ignored Node Error")
						}
					}
					Logger.data.debug("Ignored a node")
				} catch {
					Logger.mesh.error("Faile to Ignored/Un-ignore a node")
				}
			}
		} label: {
			Label {
				Text(node.ignored ? "Remove from ignored" : "Ignore Node")
			} icon: {
				Image(systemName: node.ignored ? "minus.circle.fill" : "minus.circle")
					.symbolRenderingMode(.multicolor)
			}
			// Accessibility: Label for VoiceOver
		}
	}
}
