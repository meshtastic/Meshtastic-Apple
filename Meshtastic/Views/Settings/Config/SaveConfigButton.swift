import SwiftUI

struct SaveConfigButton: View {
	@EnvironmentObject var accessoryManager: AccessoryManager
	@State private var isPresentingSaveConfirm = false
	let node: NodeInfoEntity?
	@Binding var hasChanges: Bool
	let onConfirmation: () -> Void
	
	var body: some View {
		if accessoryManager.isConnected && hasChanges {
			let feedback = node.map { accessoryManager.remoteAdminConfigFeedback?.targetNodeNum == $0.num ? accessoryManager.remoteAdminConfigFeedback?.message : nil } ?? nil
			let remoteSaveInProgress = node.flatMap {
				accessoryManager.remoteAdminConfigTracker.latest(for: $0.num, kind: .save, section: "save")
			}?.isFinished == false
			if let feedback {
				VStack(spacing: 8) {
					Label(feedback, systemImage: "exclamationmark.triangle")
						.foregroundColor(.red)
					Button("Retry") {
						accessoryManager.remoteAdminConfigFeedback = nil
						onConfirmation()
					}
				}
				.padding(.bottom)
			} else if remoteSaveInProgress {
				ProgressView("Saving…")
					.padding(.bottom)
			} else {
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
					Text("After config values save the node will reboot.")
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
			}
			}
		}
	}
}

#Preview {
	SaveConfigButton(node: nil, hasChanges: .constant(true), onConfirmation: { })
		.environmentObject(AccessoryManager.shared)
}
