import SwiftData
import OSLog
import SwiftUI

struct NodeAlertsButton: View {
	var context: ModelContext

	@Bindable
	var node: NodeInfoEntity

	@Bindable
	var user: UserEntity

	var body: some View {
		Button {
			user.mute = !user.mute
			do {
				try context.save()
			} catch {
				Logger.data.error("Save User Mute Error")
			}
		} label: {
			Label {
				Text(user.mute ? "Show alerts" : "Hide alerts")
			} icon: {
				Image(systemName: user.mute ? "bell.slash" : "bell")
					.symbolRenderingMode(.hierarchical)
			}
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
	NodeAlertsButton(context: context, node: node, user: user)
}
*/
