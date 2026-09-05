import SwiftUI

struct SaveConfigButton: View {
	@EnvironmentObject var accessoryManager: AccessoryManager
	@State private var isPresentingSaveConfirm = false
	let node: NodeInfoEntity?
	@Binding var hasChanges: Bool
	let confirmationMessage: String
	let onConfirmation: () -> Void

	init(
		node: NodeInfoEntity?,
		hasChanges: Binding<Bool>,
		confirmationMessage: String = "After config values save the node will reboot.".localized,
		onConfirmation: @escaping () -> Void
	) {
		self.node = node
		_hasChanges = hasChanges
		self.confirmationMessage = confirmationMessage
		self.onConfirmation = onConfirmation
	}
	
	var body: some View {
		if accessoryManager.isConnected && hasChanges {
			if #available(iOS 26.0, *) {
				Button {
					isPresentingSaveConfirm = true
				} label: {
					Label("Save", systemImage: "square.and.arrow.down")
				}
				.padding(.bottom)
				.controlSize(.large)
				.buttonStyle(.borderedProminent)
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
					Text(confirmationMessage)
				}
			} else {
				Button {
					isPresentingSaveConfirm = true
				} label: {
					Label("Save", systemImage: "square.and.arrow.down")
				}
				.padding(.bottom)
				.controlSize(.large)
				.buttonStyle(.borderedProminent)
				.buttonBorderShape(.capsule)
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
					Text(confirmationMessage)
				}
			}
		}
	}
}

#Preview {
	SaveConfigButton(node: nil, hasChanges: .constant(true), onConfirmation: { })
		.environmentObject(AccessoryManager.shared)
}
