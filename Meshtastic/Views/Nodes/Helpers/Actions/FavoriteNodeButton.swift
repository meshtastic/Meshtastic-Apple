import CoreData
import OSLog
import SwiftUI

struct FavoriteNodeButton: View {

	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.managedObjectContext) var context

	@ObservedObject var node: NodeInfoEntity
	@State var isShowingClientBaseConfirmation = false

	var body: some View {
		let connectedRoleIsClientBase = accessoryManager.connectedDeviceRole == DeviceRoles.clientBase
		// FIXME: if (connectedRoleIsClientBase == true), we want to show a confirmation dialog when the user clicks "Add to favorites" (but not when they click "Remove from favorites") before doing the Task below.
		// if (connectedRoleIsClientBase == false), or they are clicking "Remove from favorites" regardless, then don't show the confirmation dialog and just do the Task immediately.
		Button {
			guard let connectedNodeNum = accessoryManager.activeDeviceNum else { return }
			Task {
				await assignFavorite(node: node, setToFavorite: !node.favorite, connectedNodeNum: connectedNodeNum)
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

	private func assignFavorite (node: NodeInfoEntity, setToFavorite: Bool, connectedNodeNum: Int64) async {
		do {
			if setToFavorite {
				try await accessoryManager.setFavoriteNode(
					node: node,
					connectedNodeNum: connectedNodeNum
				)
			} else {
				try await accessoryManager.removeFavoriteNode(
					node: node,
					connectedNodeNum: connectedNodeNum
				)
			}

			Task { @MainActor in
				// Update CoreData
				node.favorite = setToFavorite

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
}
