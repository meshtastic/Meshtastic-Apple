//
//  RingtoneConfig.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 3/25/23.
//

import SwiftUI
import OSLog

struct RtttlConfig: View {
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@Environment(\.dismiss) private var goBack

	var node: NodeInfoEntity?

	@State private var isPresentingSaveConfirm: Bool = false
	@State var hasChanges = false
	@State var ringtone: String = ""

    var body: some View {
		VStack {
			Form {
				ConfigHeader(title: "ringtone", config: \.rtttlConfig, node: node, onAppear: setRtttLConfigValue)

				Section(header: Text("options")) {
					HStack {
						Label("ringtone", systemImage: "music.quarternote.3")
						TextField("config.ringtone.label", text: $ringtone, axis: .vertical)
							.foregroundColor(.gray)
							.autocapitalization(.none)
							.disableAutocorrection(true)
							.onChange(of: ringtone) {
								var totalBytes = ringtone.utf8.count
								// Only mess with the value if it is too big
								while totalBytes > 228 {
									ringtone = String(ringtone.dropLast())
									totalBytes = ringtone.utf8.count
								}
							}
							.foregroundColor(.gray)
					}
					.keyboardType(.default)
					.listRowSeparator(.hidden)
					Text("config.ringtone.description")
						.foregroundColor(.gray)
						.font(.callout)
				}
			}
			.disabled(self.bleManager.connectedPeripheral == nil || node?.rtttlConfig == nil)

			SaveConfigButton(node: node, hasChanges: $hasChanges) {
				let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral.num, context: context)
				if connectedNode != nil {
					let adminMessageId =  bleManager.saveRtttlConfig(ringtone: ringtone.trimmingCharacters(in: .whitespacesAndNewlines), fromUser: connectedNode!.user!, toUser: node!.user!, adminIndex: connectedNode?.myInfo?.adminIndex ?? 0)
					if adminMessageId > 0 {
						// Should show a saved successfully alert once I know that to be true
						// for now just disable the button after a successful save
						hasChanges = false
						goBack()
					}
				}
			}
			.navigationTitle("config.ringtone.title")
			.navigationBarItems(
				trailing: ZStack {
					ConnectedDevice(
						bluetoothOn: bleManager.isSwitchedOn,
						deviceConnected: bleManager.connectedPeripheral != nil,
						name: bleManager.connectedPeripheral?.shortName ?? "?"
					)
				}
			)
			.onFirstAppear {
				// Need to request a RtttlConfig from the remote node before allowing changes
				if let connectedPeripheral = bleManager.connectedPeripheral, let node {
					let connectedNode = getNodeInfo(id: connectedPeripheral.num, context: context)
					if let connectedNode {
						if node.num != connectedNode.num {
							if UserDefaults.enableAdministration && node.num != connectedNode.num {
								/// 2.5 Administration with session passkey
								let expiration = node.sessionExpiration ?? Date()
								if expiration < Date() || node.rtttlConfig == nil {
									Logger.mesh.info("⚙️ Empty or expired ringtone module config requesting via PKI admin")
									_ = bleManager.requestRtttlConfig(fromUser: connectedNode.user!, toUser: node.user!, adminIndex: connectedNode.myInfo?.adminIndex ?? 0)
								}
							} else {
								/// Legacy Administration
								Logger.mesh.info("☠️ Using insecure legacy admin, empty ringtone module config")
								_ = bleManager.requestRtttlConfig(fromUser: connectedNode.user!, toUser: node.user!, adminIndex: connectedNode.myInfo?.adminIndex ?? 0)
							}
						}
					}
				}
			}
			.onChange(of: ringtone) { _, newRingtone in
				if node != nil && node!.rtttlConfig != nil {
					if newRingtone != node!.rtttlConfig!.ringtone { hasChanges = true }
				}
			}
		}
    }
	func setRtttLConfigValue() {
		self.ringtone = node?.rtttlConfig?.ringtone ?? ""
		self.hasChanges = false
	}
}
