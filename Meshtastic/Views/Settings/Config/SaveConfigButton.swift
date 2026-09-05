import SwiftUI

struct SaveConfigButton: View {
	@EnvironmentObject var accessoryManager: AccessoryManager
	@State private var isPresentingSaveConfirm = false
	let node: NodeInfoEntity?
	@Binding var hasChanges: Bool
	let onConfirmation: () -> Void
	private let initiallyPresentingConfirmation: Bool

	init(
		node: NodeInfoEntity?,
		hasChanges: Binding<Bool>,
		initiallyPresentingConfirmation: Bool = false,
		onConfirmation: @escaping () -> Void
	) {
		self.node = node
		_hasChanges = hasChanges
		_isPresentingSaveConfirm = State(initialValue: false)
		self.onConfirmation = onConfirmation
		self.initiallyPresentingConfirmation = initiallyPresentingConfirmation
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
				.tint(Color("Colors/MeshtasticAccent"))
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
				.tint(Color.primary)
				.onAppear {
					if initiallyPresentingConfirmation {
						isPresentingSaveConfirm = true
					}
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
					Text("After config values save the node will reboot.")
				}
				.onAppear {
					if initiallyPresentingConfirmation {
						isPresentingSaveConfirm = true
					}
				}
			}
		}
	}
}

#Preview {
	SaveConfigButton(node: nil, hasChanges: .constant(true), onConfirmation: { })
		.environmentObject(AccessoryManager.shared)
}
