//
//  RingtoneConfig.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 3/25/23.
//

import SwiftUI

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
							.onChange(of: ringtone, perform: { _ in

								let totalBytes = ringtone.utf8.count
								// Only mess with the value if it is too big
								if totalBytes > 228 {

									let firstNBytes = Data(ringtone.utf8.prefix(228))
									if let maxBytesString = String(data: firstNBytes, encoding: String.Encoding.utf8) {
										// Set the ringtone back to the last place where it was the right size
										ringtone = maxBytesString
									}
								}
							})
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
			.navigationBarItems(trailing:
				ZStack {
					ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "?")
			})
			.onAppear {
				if self.bleManager.context == nil {
					self.bleManager.context = context
				}
				setRtttLConfigValue()
				// Need to request a Rtttl Config from the remote node before allowing changes
				if bleManager.connectedPeripheral != nil && (node?.rtttlConfig == nil || node?.rtttlConfig?.ringtone?.count ?? 0 == 0) {
					let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral.num, context: context)
					if node != nil && connectedNode != nil {
						_ = bleManager.requestRtttlConfig(fromUser: connectedNode!.user!, toUser: node!.user!, adminIndex: connectedNode?.myInfo?.adminIndex ?? 0)
					}
				}
			}
			.onChange(of: ringtone) { newRingtone in
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
