//
//  User.swift
//  Meshtastic Apple
//
//  Copyright (c) Garth Vander Houwen 6/27/22.
//
import SwiftUI

struct UserConfig: View {
	
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@Environment(\.dismiss) private var goBack
	
	var node: NodeInfoEntity?
	var connectedNode: NodeInfoEntity?
	
	@State private var isPresentingFactoryResetConfirm: Bool = false
	@State private var isPresentingSaveConfirm: Bool = false
	@State var hasChanges = false
	@State var shortName = ""
	@State var longName = ""
	
	var body: some View {
			
		VStack {
			Form {
				Section(header: Text("USER DETAILS")) {
					HStack {
						Label("Long Name", systemImage: "person.crop.rectangle.fill")
						TextField("Long Name", text: $longName)
							.onChange(of: longName, perform: { value in
								let totalBytes = longName.utf8.count
								// Only mess with the value if it is too big
								if totalBytes > 36 {
									let firstNBytes = Data(longName.utf8.prefix(36))
									if let maxBytesString = String(data: firstNBytes, encoding: String.Encoding.utf8) {
										// Set the longName back to the last place where it was the right size
										longName = maxBytesString
									}
								}
							})
					}
					.keyboardType(.default)
					.disableAutocorrection(true)
					Text("Long name can be up to 36 bytes long.")
						.font(.caption)
					HStack {
						Label("Short Name", systemImage: "circlebadge.fill")
						TextField("Long Name", text: $shortName)
							.foregroundColor(.gray)
							.onChange(of: shortName, perform: { value in
								let totalBytes = shortName.utf8.count
								// Only mess with the value if it is too big
								if totalBytes > 4 {
									let firstNBytes = Data(shortName.utf8.prefix(4))
									if let maxBytesString = String(data: firstNBytes, encoding: String.Encoding.utf8) {
										// Set the shortName back to the last place where it was the right size
										shortName = maxBytesString
									}
								}
							})
							.foregroundColor(.gray)
					}
					.keyboardType(.asciiCapable)
					.disableAutocorrection(true)
					Text("The short name is used in maps and messaging and will be appended to the last 4 of the device MAC address to set the device's BLE Name.  It can be up to 4 bytes long.")
						.font(.caption)
				}
			}
			.disabled(bleManager.connectedPeripheral == nil)
			HStack {
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
					Button("Save User Config to \(node?.user?.longName ?? "Unknown")?") {
						var u = User()
						u.shortName = shortName
						u.longName = longName
						let adminMessageId = bleManager.saveUser(config: u, fromUser: connectedNode!.user!, toUser: node!.user!, adminIndex: connectedNode?.myInfo?.adminIndex ?? 0)
						if adminMessageId > 0 {
							hasChanges = false
							goBack()
						}
					}
				} message: {
					Text("config.save.confirm")
				}
			}
			Spacer()
		}
		.navigationTitle("User Config")
		.navigationBarItems(trailing:
			ZStack {
				ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "????")
		})
		.onAppear {
			self.bleManager.context = context
			self.shortName = node?.user!.shortName ?? ""
			self.longName = node?.user!.longName ?? ""
			self.hasChanges = false
		}
		.onChange(of: shortName) { newShort in
			if node != nil && node!.user != nil {
				if newShort != node?.user!.shortName { hasChanges = true }
			}
		}
		.onChange(of: longName) { newLong in
			if node != nil && node!.user != nil {
				if newLong != node?.user!.longName { hasChanges = true }
			}
		}
	}
}
