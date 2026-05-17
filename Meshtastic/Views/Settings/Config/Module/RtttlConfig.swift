//
//  RingtoneConfig.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 3/25/23.
//

import SwiftUI
import OSLog

struct RtttlConfig: View {
	@Environment(\.modelContext) private var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.dismiss) private var goBack
	
	let node: NodeInfoEntity?
	
	@State private var isPresentingSaveConfirm: Bool = false
	@State var hasChanges = false
	@State var ringtone: String = ""
	
	var body: some View {
		Form {
			ConfigHeader(title: "Ringtone", config: \.rtttlConfig, node: node, onAppear: setRtttLConfigValue)
			
			Section(header: Text("Options")) {
				HStack {
					Label("Ringtone", systemImage: "music.quarternote.3")
					TextField("Ringtone Transfer Language", text: $ringtone, axis: .vertical)
						.foregroundColor(.gray)
						.autocapitalization(.none)
						.disableAutocorrection(true)
						.onChange(of: ringtone) {
							var totalBytes = ringtone.utf8.count
							// Only mess with the value if it is too big
							while totalBytes > 230 {
								ringtone = String(ringtone.dropLast())
								totalBytes = ringtone.utf8.count
							}
						}
						.foregroundColor(.gray)
				}
				.keyboardType(.default)
				.listRowSeparator(.hidden)
				Text("Ringtone Transfer Language(RTTTL) Ringtone String used by supported buzzers in external notifications.")
					.foregroundColor(.gray)
					.font(.callout)
			}
		}
		.disabled(!accessoryManager.isConnected || node?.rtttlConfig == nil)
		.safeAreaInset(edge: .bottom, alignment: .center) {
			HStack(spacing: 0) {
				SaveConfigButton(node: node, hasChanges: $hasChanges) {
					let connectedNode = getNodeInfo(id: accessoryManager.activeDeviceNum ?? -1, context: context)
					if connectedNode != nil {
						Task {
							_ = try await accessoryManager.saveRtttlConfig(ringtone: ringtone.trimmingCharacters(in: .whitespacesAndNewlines), fromUser: connectedNode!.user!, toUser: node!.user!)
							Task { @MainActor in
								// Should show a saved successfully alert once I know that to be true
								// for now just disable the button after a successful save
								hasChanges = false
								goBack()
							}
						}
					}
				}
			}
		}
		.navigationTitle("Ringtone Config")
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				ConnectedDevice(deviceConnected: accessoryManager.isConnected, name: accessoryManager.activeConnection?.device.shortName ?? "?")
			}
		}
		.onFirstAppear {
			requestRemoteConfig(
				node: node,
				context: context,
				accessoryManager: accessoryManager,
				configIsNil: { $0.rtttlConfig == nil },
				request: accessoryManager.requestRtttlConfig
			)
		}
		.onChange(of: ringtone) { _, newRingtone in
			if node != nil && node!.rtttlConfig != nil {
				if newRingtone != node!.rtttlConfig!.ringtone { hasChanges = true }
			}
		}
		
	}
	func setRtttLConfigValue() {
		self.ringtone = node?.rtttlConfig?.ringtone ?? ""
		self.hasChanges = false
	}
}

#Preview {
	RtttlConfig(node: nil)
		.environmentObject(AccessoryManager.shared)
		.modelContainer(PersistenceController.preview.container)
}
