import SwiftData
import OSLog
import SwiftUI

struct IgnoreNodeButton: View {
	@Environment(\.modelContext) private var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	/// The radio this window works with (feature 021, D-19).
	@Environment(\.windowRadio) private var windowRadio

	@Bindable
	var node: NodeInfoEntity

	var body: some View {
		Button(role: .destructive) {
			guard accessoryManager.nodeNum(for: windowRadio) != nil else { return }
			Task {
				do {
					// Feature 021 (D-11): on every connected radio, the focused one first.
					try await accessoryManager.setIgnored(!node.ignored, node: node)
					Task {@MainActor in
						// CoreData Stuff
						node.ignored = !node.ignored
						do {
							try context.save()
						} catch {
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
				Text(node.ignored ? "Remove from ignored" : "Ignore")
			} icon: {
				Image(systemName: node.ignored ? "minus.circle.fill" : "minus.circle")
					.symbolRenderingMode(.multicolor)
			}
			// Accessibility: Label for VoiceOver
		}
	}
}

// TODO: Fix preview for SwiftData
/*
#Preview {
	let node = NodeInfoEntity()
	node.num = 123456789
	IgnoreNodeButton(node: node)
		.environmentObject(AccessoryManager.shared)
		.modelContainer(PersistenceController.preview.container)
}
*/
