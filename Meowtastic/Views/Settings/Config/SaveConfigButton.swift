import SwiftUI

struct SaveConfigButton: View {
	let node: NodeInfoEntity?
	@Binding
	var hasChanges: Bool
	let onConfirmation: () -> Void

	@EnvironmentObject
	private var bleManager: BLEManager
	@State
	private var isPresentingSaveConfirm = false

	@ViewBuilder
	var body: some View {
		Button {
			isPresentingSaveConfirm = true
		} label: {
			Label("save", systemImage: "square.and.arrow.down")
		}
		.disabled(bleManager.connectedPeripheral == nil || !hasChanges)
		.buttonStyle(.bordered)
		.buttonBorderShape(.capsule)
		.controlSize(.large)
		.padding()
		.confirmationDialog(
			"are.you.sure",
			isPresented: $isPresentingSaveConfirm,
			titleVisibility: .visible
		) {
			let nodeName = node?.user?.longName ?? "unknown".localized
			let buttonText = String.localizedStringWithFormat("save.config %@".localized, nodeName)
			Button(buttonText) {
				onConfirmation()
			}
		} message: {
			Text("config.save.confirm")
		}
	}
}
