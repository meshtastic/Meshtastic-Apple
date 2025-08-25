import CoreData
import OSLog
import SwiftUI

struct FavoriteNodeButton: View {

	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.managedObjectContext) var context

	@ObservedObject var node: NodeInfoEntity

	var body: some View {
		Button {
			guard let connectedNodeNum = accessoryManager.activeDeviceNum else { return }
			Task {
				do {
					if node.favorite {
						try await accessoryManager.removeFavoriteNode(
							node: node,
							connectedNodeNum: Int64(connectedNodeNum)
						)
					} else {
						try await accessoryManager.setFavoriteNode(
							node: node,
							connectedNodeNum: Int64(connectedNodeNum)
						)
					}

					Task { @MainActor in
						// Update CoreData
						node.favorite = !node.favorite

						do {
							try context.save()
						} catch {
							context.rollback()
							Logger.data.error("Save Node Favorite Error")
						}
						Logger.data.debug("Favorited a node")
					}
				} catch {

				}
			}
		} label: {
			Label {
				Text(node.favorite ? "Remove from favorites" : "Add to favorites")
			} icon: {
				Image(systemName: node.favorite ? "star.fill" : "star")
					.symbolRenderingMode(.multicolor)
			}
		}
	}
}
