import CoreData
import OSLog
import SwiftUI

struct NodeAlertsButton: View {
	var context: NSManagedObjectContext

	@ObservedObject
	var node: NodeInfoEntity

	@ObservedObject
	var user: UserEntity

	var body: some View {
		Button {
			user.mute = !user.mute
			context.refresh(node, mergeChanges: true)
			do {
				try context.save()
			} catch {
				context.rollback()
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
