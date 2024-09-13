import CoreData
import OSLog
import SwiftUI

struct FavoriteNodeButton: View {
	var node: NodeInfoEntity
	var nodeConfig: NodeConfig
	var context: NSManagedObjectContext

	@EnvironmentObject
	private var connectedDevice: ConnectedDevice

	var body: some View {
		Button {
			guard let connectedNodeNum = connectedDevice.device?.num else {
				return
			}

			let success = if node.favorite {
				nodeConfig.removeFavoriteNode(
					node: node,
					connectedNodeNum: Int64(connectedNodeNum)
				)
			}
			else {
				nodeConfig.saveFavoriteNode(
					node: node,
					connectedNodeNum: Int64(connectedNodeNum)
				)
			}

			if success {
				node.favorite.toggle()

				do {
					try context.save()
				}
				catch {
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
