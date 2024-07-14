import CoreData
import OSLog
import SwiftUI

struct FavoriteNodeButton: View {
	var bleManager: BLEManager
	var context: NSManagedObjectContext

	@ObservedObject
	var node: NodeInfoEntity

	var body: some View {
		Button {
			guard let connectedNodeNum = bleManager.connectedPeripheral?.num else {
				return
			}

			let success = if node.favorite {
				bleManager.removeFavoriteNode(
					node: node,
					connectedNodeNum: Int64(connectedNodeNum)
				)
			} else {
				bleManager.setFavoriteNode(
					node: node,
					connectedNodeNum: Int64(connectedNodeNum)
				)
			}
			if success {
				node.favorite = !node.favorite
				do {
					try context.save()
				} catch {
					context.rollback()
					Logger.data.error("Save Node Favorite Error")
				}

				Logger.data.debug("Favorited a node")
			}
		} label: {
			Label {
				Text(node.favorite ? "Remove from favorites" : "Add to favorites")
			} icon: {
				Image(systemName: node.favorite ? "star.slash" : "star")
					.symbolRenderingMode(.monochrome)
					.foregroundColor(.accentColor)
			}
		}
	}
}
