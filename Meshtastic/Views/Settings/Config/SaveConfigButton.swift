import SwiftUI

struct SaveConfigButton: View {
	@EnvironmentObject var accessoryManager: AccessoryManager
	@State private var isPresentingSaveConfirm = false
	let node: NodeInfoEntity?
	@Binding var hasChanges: Bool
	let onConfirmation: () -> Void

	var body: some View {
		Button {
			isPresentingSaveConfirm = true
		} label: {
			Label("Save", systemImage: "square.and.arrow.down")
		}
		.disabled(!accessoryManager.isConnected || !hasChanges)
		.buttonStyle(.bordered)
		.buttonBorderShape(.capsule)
		.controlSize(.large)
		.padding()
		.confirmationDialog(
			"Are you sure?",
			isPresented: $isPresentingSaveConfirm,
			titleVisibility: .visible
		) {
			let nodeName = node?.user?.longName ?? "Unknown".localized
			let buttonText = String.localizedStringWithFormat("Save Config for %@".localized, nodeName)
			Button(buttonText) {
				onConfirmation()
			}
		} message: {
			Text("After config values save the node will reboot.")
		}
	}
}
