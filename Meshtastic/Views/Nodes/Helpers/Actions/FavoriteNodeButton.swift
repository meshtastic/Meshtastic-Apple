import SwiftData
import OSLog
import SwiftUI

struct FavoriteNodeButton: View {

	@EnvironmentObject var accessoryManager: AccessoryManager
	/// The radio this window works with (feature 021, D-19).
	@Environment(\.windowRadio) private var windowRadio
	@Environment(\.modelContext) private var context

	@Bindable var node: NodeInfoEntity
	@State var isShowingClientBaseConfirmation = false

	var body: some View {
		let connectedRoleIsClientBase = accessoryManager.connectedDeviceRole == DeviceRoles.clientBase
		Button {
			// Special case for CLIENT_BASE: show confirmation when attempting to favorite a node
			if connectedRoleIsClientBase && !node.favorite {
				isShowingClientBaseConfirmation = true
				return
			}
			// Normal case: perform action immediately
			guard let connectedNodeNum = accessoryManager.nodeNum(for: windowRadio) else { return }
			Task {
				await assignFavorite(node: node, setToFavorite: !node.favorite, connectedNodeNum: Int64(connectedNodeNum))
			}
		} label: {
			Label {
				Text(node.favorite ? "Remove from favorites" : "Add to favorites")
			} icon: {
				Image(systemName: node.favorite ? "star.fill" : "star")
					.symbolRenderingMode(.multicolor)
			}
		}
		.confirmationDialog(
			"Are you sure?",
			isPresented: $isShowingClientBaseConfirmation,
			titleVisibility: .visible
		) {
			Button("Yes, I control this node") {
				guard let connectedNodeNum = accessoryManager.nodeNum(for: windowRadio) else { return }
				Task {
					await assignFavorite(node: node, setToFavorite: true, connectedNodeNum: Int64(connectedNodeNum))
				}
			}
			Button("Cancel", role: .cancel) { }
		} message: {
			Text("Client Base should only favorite other nodes you control. Improper use will hurt your local mesh.")
		}
	}

	private func assignFavorite (node: NodeInfoEntity, setToFavorite: Bool, connectedNodeNum: Int64) async {
		do {
			// Feature 021 (D-11): on every connected radio, starting with the first radio.
			try await accessoryManager.setFavorite(setToFavorite, node: node)

			Task { @MainActor in
				// Update CoreData
				node.favorite = setToFavorite

				do {
					try context.save()
				} catch {
					Logger.data.error("Save Node Favorite Error")
				}
				Logger.data.debug("Favorited a node")
			}
		} catch {

		}
	}
}

// TODO: Fix preview for SwiftData
/*
#Preview {
	let node = NodeInfoEntity()
	node.num = 123456789
	let user = UserEntity()
	user.longName = "Test Node"
	user.shortName = "TN"
	node.user = user
	FavoriteNodeButton(node: node)
		.environmentObject(AccessoryManager.shared)
		.modelContainer(PersistenceController.preview.container)
}
*/
