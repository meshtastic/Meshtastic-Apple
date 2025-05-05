import SwiftUI

struct SaveConfigButton: View {
	@EnvironmentObject var bleManager: BLEManager

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
		.disabled(bleManager.connectedPeripheral == nil || !hasChanges)
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
			let buttonText = String.localizedStringWithFormat("save.config %@".localized, nodeName)
			Button(buttonText) {
				onConfirmation()
			}
		} message: {
			Text("config.save.confirm")
		}
	}
}
